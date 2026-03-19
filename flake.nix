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
    mistral-vibe = {
      url = "github:pitaya1219/mistral-vibe-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    homelab.url = "git+https://git.pitaya.f5.si/pitaya1219/homelab.git";
  };

  outputs = { self, nixpkgs, home-manager, neovim-nightly-overlay, mistral-vibe, homelab }:
    let
      profileLib = import ./lib/profiles.nix { inherit (nixpkgs) lib; };

      overlays = {
        neovim-nightly = neovim-nightly-overlay.overlays.default;
        mistral-vibe = mistral-vibe.overlays.default;
      };
      
      # Load all profiles automatically
      profiles = profileLib.loadProfiles {
        profilesPath = ./profiles;
        inherit nixpkgs home-manager overlays homelab;
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
