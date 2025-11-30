{ nixpkgs, home-manager, overlays }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ overlays.neovim-nightly ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        imports = [
          ../shared/activations/aider.nix
          ../shared/programs/bash.nix
          ../shared/programs/bare.nix
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
            cloudflared
            rclone
          ];
        };
      })
    ];
  };
}
