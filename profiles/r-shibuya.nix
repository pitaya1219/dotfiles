{ nixpkgs, home-manager, overlays }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-darwin";
      overlays = [ overlays.neovim-nightly ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        imports = [
          ../shared/activations/aider.nix
          ../shared/programs/bare.nix
          (import ../shared/programs/neovim.nix { inherit config pkgs lib; profileName = "r-shibuya"; })
          (import ../shared/programs/unfree.nix { additionalPackages = [ "copilot.vim" ]; })
        ];

        home = {
          username = "r-shibuya";
          homeDirectory = "/Users/r-shibuya";
          stateVersion = "23.11";
          packages = with pkgs; [
            jq
          ];
        };
      })
    ];
  };
}
