{ config, pkgs, lib, profileName, ... }:

let
  # Base neovim plugins from shared configuration
  baseNeovimPlugins = import ./neovim/plugins.nix { inherit pkgs lib config; };
  
  # Profile-specific plugins - fallback to empty if not found
  profilePluginsPath = ../../profiles/${profileName}/neovim/plugins.nix;
  profilePlugins = if builtins.pathExists profilePluginsPath
    then import profilePluginsPath { inherit pkgs lib config; }
    else { plugins = []; extraPackages = []; };
  
  # Merge base and profile-specific configurations
  allPlugins = baseNeovimPlugins.plugins ++ profilePlugins.plugins;
  allExtraPackages = baseNeovimPlugins.extraPackages ++ profilePlugins.extraPackages;
  
  # Get all .lua files except init.lua and plugins directory
  luaFiles = lib.filterAttrs (name: type: 
    type == "regular" && lib.hasSuffix ".lua" name && name != "init.lua"
  ) (builtins.readDir ./neovim);
  
  # Get plugin lua files from plugins directory
  pluginFiles = lib.mapAttrs' (name: _: {
    name = "plugin/${name}";
    value = ./neovim/plugin/${name};
  }) (lib.filterAttrs (name: type: 
    type == "regular" && lib.hasSuffix ".lua" name
  ) (builtins.readDir ./neovim/plugin));
  
  # Get profile-specific after/plugin files
  profileAfterPluginPath = ../../profiles/${profileName}/neovim/after/plugin;
  profileAfterPluginFiles = if builtins.pathExists profileAfterPluginPath
    then lib.mapAttrs' (name: _: {
      name = "after/plugin/${name}";
      value = profileAfterPluginPath + "/${name}";
    }) (lib.filterAttrs (name: type: 
      type == "regular" && lib.hasSuffix ".lua" name
    ) (builtins.readDir profileAfterPluginPath))
    else {};
  
  # Merge coc-settings.json from shared and profile-specific sources
  baseCocSettings = builtins.fromJSON (builtins.readFile ./neovim/coc-settings.json);
  profileCocSettingsPath = ../../profiles/${profileName}/neovim/coc-settings.json;
  profileCocSettings = if builtins.pathExists profileCocSettingsPath
    then builtins.fromJSON (builtins.readFile profileCocSettingsPath)
    else {};
  
  # Deep merge function for nested objects
  deepMerge = a: b:
    if builtins.isAttrs a && builtins.isAttrs b
    then lib.recursiveUpdate a b
    else b;
  
  # Merged coc settings
  mergedCocSettings = deepMerge baseCocSettings profileCocSettings;
  cocSettingsFile = pkgs.writeText "coc-settings.json" (builtins.toJSON mergedCocSettings);
in
{
  programs.neovim = {
    enable = true;
    package = pkgs.neovim;
    defaultEditor = true;
    viAlias = false;
    vimAlias = true;

    extraLuaConfig = lib.fileContents ./neovim/init.lua;
    
    plugins = allPlugins;
    extraPackages = allExtraPackages;
  };

  # Create symlinks for lua configuration files (excluding init.lua)
  home.file = lib.mapAttrs' (name: _: {
    name = ".config/nvim/${name}";
    value.source = ./neovim/${name};
  }) luaFiles // lib.mapAttrs' (name: path: {
    name = ".config/nvim/${name}";
    value.source = path;
  }) pluginFiles // lib.mapAttrs' (name: path: {
    name = ".config/nvim/${name}";
    value.source = path;
  }) profileAfterPluginFiles // {
    ".config/nvim/coc-settings.json".source = cocSettingsFile;
  };
}
