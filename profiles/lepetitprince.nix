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
          ../shared/programs/bare.nix
          ../shared/programs/neovim.nix
          ((import ../lib/neovim-extension.nix { inherit lib; }).forProfile "lepetitprince")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        home = {
          username = "r-shibuya";
          homeDirectory = "/home/lepetitprince";
          stateVersion = "23.11";
          packages = with pkgs; [];
        };
      })
    ];
  };
}
