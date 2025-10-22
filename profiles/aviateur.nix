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
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "aviateur")
          ((import ../lib/neovim-extension.nix { inherit lib; }).forProfile "aviateur")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        home = {
          username = "aviateur";
          homeDirectory = "/home/aviateur";
          stateVersion = "23.11";
          packages = with pkgs; [
            rclone
          ];
        };
      })
    ];
  };
}
