{ config, pkgs, lib, ... }:

let
  # Base neovim plugins from shared configuration
  baseNeovimPlugins = import ./neovim/plugins.nix { inherit pkgs lib config; };
  
  # Profile-specific plugins - fallback to empty if not found
  profilePluginsPath = ../../profiles/${config.home.username}/neovim/plugins.nix;
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
    name = "plugins/${name}";
    value = ./neovim/plugins/${name};
  }) (lib.filterAttrs (name: type: 
    type == "regular" && lib.hasSuffix ".lua" name
  ) (builtins.readDir ./neovim/plugins));
  
  # Profile-specific coc-settings path
  profileCocSettingsPath = ../../profiles/${config.home.username}/neovim/coc-settings.json;
  cocSettingsSource = if builtins.pathExists profileCocSettingsPath
    then profileCocSettingsPath
    else ./neovim/coc-settings.json;
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
  }) pluginFiles // {
    ".config/nvim/coc-settings.json".source = cocSettingsSource;
  };
}
