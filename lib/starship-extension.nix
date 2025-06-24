{ lib, pkgs }:

rec {
  forProfile = profileName:
    let
      # Profile-specific starship.toml
      profileStarshipPath = ../profiles/${profileName}/starship/override.toml;
      profileStarshipConfig = if builtins.pathExists profileStarshipPath
        then builtins.readFile profileStarshipPath
        else "";

      # Base starship.toml from shared
      sharedStarshipPath = ../shared/programs/starship/default.toml;
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

      # Convert back to TOML format using pkgs.formats.toml
      tomlFormat = pkgs.formats.toml {};

      starshipConfigFile = tomlFormat.generate "starship.toml" mergedStarshipSettings;

    in {
      home.file = {
        ".config/starship.toml".source = lib.mkForce starshipConfigFile;
      };
    };
}
