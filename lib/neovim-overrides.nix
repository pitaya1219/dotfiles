# Shared neovim profile overrides
{ lib }:

{
  # Creates a neovim profile overrides module
  # Usage: import (neovimOverrides.forProfile "profile-name")
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
      
      # Profile-specific coc-settings.json path
      profileCocSettingsPath = ../profiles/${profileName}/neovim/coc-settings.json;
    in
    {
      # Extend neovim with profile-specific plugins
      programs.neovim.plugins = lib.mkAfter profilePlugins.plugins;
      programs.neovim.extraPackages = lib.mkAfter profilePlugins.extraPackages;

      # Add profile-specific files
      home.file = lib.mapAttrs' (name: path: {
        name = ".config/nvim/${name}";
        value.source = path;
      }) profileAfterPluginFiles;

      # Deploy profile-specific coc-settings.json using mkOutOfStoreSymlink (overriding base)
      # Use lib.mkForce to ensure this takes precedence over the base config
      # Only set if the profile-specific file exists
      home.file.".config/nvim/coc-settings.json".source = 
        lib.mkIf (builtins.pathExists profileCocSettingsPath) (
          lib.mkForce (config.lib.file.mkOutOfStoreSymlink profileCocSettingsPath)
        );
    };
}
