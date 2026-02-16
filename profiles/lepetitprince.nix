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
          ../shared/activations/rootless-docker.nix
          ../shared/activations/proton-pass.nix
          ../shared/programs/bash.nix
          ../shared/programs/bare.nix
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
          ./lepetitprince/rclone/config.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "lepetitprince")
          ((import ../lib/neovim-extension.nix { inherit lib; }).forProfile "lepetitprince")
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
          ];
        };
      })
    ];
  };
}
