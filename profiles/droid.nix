{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-linux";
      overlays = [ overlays.mistral-vibe overlays.fix-neovim-lua-passthru overlays.pipx-no-check overlays.pipx-proot-unpack overlays.logseq-view overlays.nix-claude-code ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        dotfiles.agent.logseq = {
          url = { command = "passage show logseq/http-api/host"; };
          token = { command = "passage show logseq/http-api/claude-code/token"; };
        };

        imports = [
          ../shared/programs/bare.nix
          ../shared/programs/logseq-view.nix
          ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "droid")
          ../shared/programs/bash.nix
          ../shared/programs/claude-code.nix
          ../shared/programs/opencode.nix
          ../shared/programs/vibe.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ../shared/activations/huggingface_hub.nix
          ../shared/activations/proton-pass.nix
          ./droid/activations/termux-font.nix
          ./droid/packages/shellm.nix
          ./droid/ssh/config.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "droid")
          ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "droid")
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "droid")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        home = {
          username = "droid";
          homeDirectory = "/home/droid";
          stateVersion = "23.11";
          packages = with pkgs; [
            android-tools
            cloudflared
            jq
            llama-cpp
            mistral-vibe
            rclone
          ];
        };
      })
    ];
  };
}
