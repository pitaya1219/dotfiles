{ lib, ... }:

rec {
  forProfile = profileName:
    let
      # Profile-specific split configuration files
      profileAliasesPath = ../profiles/${profileName}/bash/aliases.nix;
      profileShellOptionsPath = ../profiles/${profileName}/bash/shell_options.nix;
      profileBashrcPath = ../profiles/${profileName}/bash/bashrc.nix;
      profileEnvPath = ../profiles/${profileName}/bash/env.nix;

      # Import profile configurations if they exist
      profileAliases = if builtins.pathExists profileAliasesPath
        then import profileAliasesPath
        else {};

      profileShellOptions = if builtins.pathExists profileShellOptionsPath
        then import profileShellOptionsPath
        else [];

      profileBashrcContent = if builtins.pathExists profileBashrcPath
        then import profileBashrcPath
        else "";

      profileEnv = if builtins.pathExists profileEnvPath
        then import profileEnvPath
        else {};

    in {
      programs.bash = lib.mkMerge [
        # Profile-specific shell aliases (merged with shared)
        (lib.mkIf (profileAliases != {}) {
          shellAliases = profileAliases.shellAliases or profileAliases;
        })
        
        # Profile-specific shell options (merged with shared)
        (lib.mkIf (profileShellOptions != []) {
          shellOptions = profileShellOptions;
        })
        
        # Profile-specific bashrc content (executed after shared)
        (lib.mkIf (profileBashrcContent != "") {
          bashrcExtra = lib.mkAfter profileBashrcContent;
        })

        # Profile-specific environment (executed after shared)
        (lib.mkIf (profileEnv != "") {
          sessionVariables = lib.mkAfter profileEnv;
        })
      ];
    };
}
