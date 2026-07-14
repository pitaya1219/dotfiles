{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ overlays.neovim-nightly overlays.mistral-vibe overlays.pipx-no-check overlays.logseq-view overlays.nix-claude-code ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        dotfiles.agent.logseq = {
          url = { command = "passage show logseq/http-api/host"; };
          token = { command = "passage show logseq/http-api/claude-code/token"; };
        };

        imports = [
          ../shared/activations/rootless-docker.nix
          ../shared/activations/proton-pass.nix
          ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "lepetitprince")
          ../shared/programs/bash.nix
          ../shared/programs/bare.nix
          ../shared/programs/logseq-view.nix
          ../shared/programs/rust.nix
          ../shared/programs/claude-code.nix
          ../shared/programs/opencode.nix
          ../shared/programs/vibe.nix
          ../shared/programs/direnv.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "lepetitprince")
          ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "lepetitprince")
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "lepetitprince")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        home = {
          username = "lepetitprince";
          homeDirectory = "/home/lepetitprince";
          stateVersion = "23.11";
          packages = with pkgs; [
            gitea-mcp-server
            cloudflared
            rclone
            passt
            mistral-vibe
            tailscale
            go-task
          ];
        };
      })
    ];
  };
}
