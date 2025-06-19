{
  description = "Multi-profile dotfiles configuration with Nix Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, neovim-nightly-overlay }:
    let
      # Supported systems
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" "x86_64-darwin" ];
      
      # User configuration data
      users = {
        r-shibuya = rec {
          system = "aarch64-darwin";
          profile = "r-shibuya";
          username = profile;
        };
        droid = rec {
          system = "aarch64-linux";
          profile = "droid";
          username = profile;
        };
      };

      # Helper functions
      helpers = {
        # Generate Home Manager configuration for a user
        generateHomeConfiguration = userConfig:
          home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = userConfig.system;
              overlays = [ neovim-nightly-overlay.overlays.default ];
            };
            modules = [
              # Profile-specific configuration
              ./profiles/${userConfig.profile}.nix
            ];
          };
      };

      # Generate all home configurations from user data
      homeConfigurations = builtins.mapAttrs 
        (name: userConfig: helpers.generateHomeConfiguration userConfig) 
        users;

    in
    {
      inherit homeConfigurations;
    };
}
