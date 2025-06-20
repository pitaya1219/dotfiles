{ lib, pkgs }:

rec {
  forProfile = profileName:
    let
      # Profile-specific starship.toml
      profileStarshipPath = ../profiles/${profileName}/starship/starship.toml;
      profileStarshipConfig = if builtins.pathExists profileStarshipPath
        then builtins.readFile profileStarshipPath
        else "";

      # Base starship.toml from shared
      sharedStarshipPath = ../shared/programs/starship/starship.toml;
      baseStarshipConfig = if builtins.pathExists sharedStarshipPath
        then builtins.readFile sharedStarshipPath
        else "";

      # Parse TOML configurations
      parseToml = content: 
        if content == "" then {}
        else builtins.fromTOML content;

      baseStarshipSettings = parseToml baseStarshipConfig;
      profileStarshipSettings = parseToml profileStarshipConfig;

      # Deep merge function for nested objects
      deepMerge = a: b:
        if builtins.isAttrs a && builtins.isAttrs b
        then lib.recursiveUpdate a b
        else b;

      # Merge starship settings
      mergedStarshipSettings = deepMerge baseStarshipSettings profileStarshipSettings;

      # Convert back to TOML format
      starshipConfigFile = pkgs.writeText "starship.toml" (lib.generators.toTOML {} mergedStarshipSettings);

    in {
      # Return the merged configuration file
      configFile = starshipConfigFile;
      
      # Return the merged settings as attribute set
      settings = mergedStarshipSettings;
      
      # Convenience function to get the config content as string
      configContent = builtins.readFile starshipConfigFile;
    };
}