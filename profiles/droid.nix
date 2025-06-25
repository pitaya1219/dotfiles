{ nixpkgs, home-manager, overlays }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-linux";
      overlays = [ overlays.neovim-nightly ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        imports = [
          ../shared/activations/aider.nix
          ../shared/programs/bare.nix
          ../shared/programs/bash.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ((import ../lib/neovim-extension.nix { inherit lib; }).forProfile "droid")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        home = {
          username = "droid";
          homeDirectory = "/home/droid";
          stateVersion = "23.11";
          packages = with pkgs; [
            jq
          ];
        };
      })
    ];
  };
}
