{ nixpkgs, home-manager, overlays }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ overlays.neovim-nightly overlays.mistral-vibe ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
         imports = [
           ../shared/activations/huggingface_hub.nix
           ../shared/activations/rootless-docker.nix
           ../shared/activations/proton-pass.nix
           ../shared/programs/bash.nix
           ../shared/programs/bare.nix
           ../shared/programs/rust.nix
           ../shared/programs/claude-code.nix
           ../shared/programs/opencode.nix
           ../shared/programs/openclaw.nix
           ../shared/programs/direnv.nix
           ../shared/programs/git.nix
           ../shared/programs/neovim.nix
           ../shared/programs/tmux.nix
           ../shared/programs/starship.nix
           ../shared/programs/readline.nix
           ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "rose")
           ((import ../lib/neovim-extension.nix { inherit lib; }).forProfile "rose")
           (import ../shared/programs/unfree.nix { additionalPackages = []; })
         ];

        home = {
          username = "rose";
          homeDirectory = "/home/rose";
          stateVersion = "23.11";
          packages = with pkgs; [
            gitea-mcp-server
            mistral-vibe
            passt
            tea
          ];
        };
      })
    ];
  };
}
