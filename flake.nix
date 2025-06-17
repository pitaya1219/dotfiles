{
  description = "Multi-profile dotfiles configuration with Nix Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      # Supported systems
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" "x86_64-darwin" ];
      
      # User configuration data
      users = {
        r-shibuya = {
          system = "aarch64-darwin";
          profile = "r-shibuya";
        };
        droid = {
          system = "aarch64-linux";
          profile = "droid";
        };
      };

      # Helper functions
      helpers = {
        # Determine home directory based on system
        getHomeDirectory = system: profile:
          if nixpkgs.legacyPackages.${system}.stdenv.isDarwin 
          then "/Users/${profile}"
          else "/home/${profile}";

        # Generate Home Manager configuration for a user
        generateHomeConfiguration = userConfig:
          let
            inherit (userConfig) system profile;
            pkgs = nixpkgs.legacyPackages.${system};
          in
          home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              # Profile-specific configuration
              ./profiles/${profile}.nix
              
              # User-specific settings
              {
                home = {
                  username = profile;
                  homeDirectory = helpers.getHomeDirectory system profile;
                  stateVersion = "23.11";
                };
              }
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
