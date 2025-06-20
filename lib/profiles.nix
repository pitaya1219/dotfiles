{ lib }:

rec {
  # Automatically discover profile names from profiles/*.nix files
  discoverProfiles = profilesPath:
    let
      # Read the profiles directory
      profileFiles = builtins.readDir profilesPath;
      
      # Filter only .nix files and extract profile names
      nixFiles = lib.filterAttrs (name: type: 
        type == "regular" && lib.hasSuffix ".nix" name
      ) profileFiles;
      
      # Extract profile names by removing .nix extension
      profileNames = map (fileName: 
        lib.removeSuffix ".nix" fileName
      ) (lib.attrNames nixFiles);
      
    in profileNames;

  # Load all profiles from a directory
  loadProfiles = { profilesPath, nixpkgs, home-manager, overlays }:
    let
      profileNames = discoverProfiles profilesPath;
    in
    builtins.listToAttrs (map (profileName: {
      name = profileName;
      value = import (profilesPath + "/${profileName}.nix") {
        inherit nixpkgs home-manager overlays;
      };
    }) profileNames);
}
