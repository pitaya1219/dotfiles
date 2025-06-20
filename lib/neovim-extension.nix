# Shared neovim profile extension utilities
{ lib }:

{
  # Creates a neovim profile extension module
  # Usage: import (neovimExtension.forProfile "profile-name")
  forProfile = profileName: 
    { config, pkgs, lib, ... }:
    
    let
      # Profile-specific plugins
      profilePluginsPath = ../profiles/${profileName}/neovim/plugins.nix;
      profilePlugins = if builtins.pathExists profilePluginsPath
        then import profilePluginsPath { inherit pkgs lib config; }
        else { plugins = []; extraPackages = []; };
      
      # Get profile-specific after/plugin files
      profileAfterPluginPath = ../profiles/${profileName}/neovim/after/plugin;
      profileAfterPluginFiles = if builtins.pathExists profileAfterPluginPath
        then lib.mapAttrs' (name: _: {
          name = "after/plugin/${name}";
          value = profileAfterPluginPath + "/${name}";
        }) (lib.filterAttrs (name: type: 
          type == "regular" && lib.hasSuffix ".lua" name
        ) (builtins.readDir profileAfterPluginPath))
        else {};
      
      # Profile-specific coc-settings.json
      profileCocSettingsPath = ../profiles/${profileName}/neovim/coc-settings.json;
      profileCocSettings = if builtins.pathExists profileCocSettingsPath
        then builtins.fromJSON (builtins.readFile profileCocSettingsPath)
        else {};
      
      # Deep merge function for nested objects
      deepMerge = a: b:
        if builtins.isAttrs a && builtins.isAttrs b
        then lib.recursiveUpdate a b
        else b;
      
      # Base coc settings from shared
      sharedCocSettingsPath = ../shared/programs/neovim/coc-settings.json;
      baseCocSettings = if builtins.pathExists sharedCocSettingsPath
        then builtins.fromJSON (builtins.readFile sharedCocSettingsPath)
        else {};
      
      # Merge coc settings
      mergedCocSettings = deepMerge baseCocSettings profileCocSettings;
      cocSettingsFile = pkgs.writeText "coc-settings.json" (builtins.toJSON mergedCocSettings);
    in
    {
      # Extend neovim with profile-specific plugins
      programs.neovim.plugins = lib.mkAfter profilePlugins.plugins;
      programs.neovim.extraPackages = lib.mkAfter profilePlugins.extraPackages;

      # Add profile-specific files
      home.file = lib.mapAttrs' (name: path: {
        name = ".config/nvim/${name}";
        value.source = path;
      }) profileAfterPluginFiles // lib.optionalAttrs (profileCocSettings != {}) {
        ".config/nvim/coc-settings.json" = lib.mkForce { source = cocSettingsFile; };
      };
    };
}