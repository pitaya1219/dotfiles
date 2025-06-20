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
      profileLib = import ./lib/profiles.nix { inherit (nixpkgs) lib; };
      
      overlays = {
        neovim-nightly = neovim-nightly-overlay.overlays.default;
      };
      
      # Load all profiles automatically
      profiles = profileLib.loadProfiles {
        profilesPath = ./profiles;
        inherit nixpkgs home-manager overlays;
      };
      
      # Generate home configurations from profiles  
      homeConfigurations = builtins.mapAttrs 
        (name: profile: profile.mkHomeConfiguration) 
        profiles;

    in
    {
      inherit homeConfigurations;
    };
}
