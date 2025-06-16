{ config, pkgs, lib, ... }:

let
  neovimPlugins = import ./neovim/plugins.nix { inherit pkgs lib config; };
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
in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = false;
    vimAlias = true;

    extraLuaConfig = lib.fileContents ./neovim/init.lua;
    
    plugins = neovimPlugins.plugins;
    extraPackages = neovimPlugins.extraPackages;
  };

  # Create symlinks for lua configuration files (excluding init.lua)
  home.file = lib.mapAttrs' (name: _: {
    name = ".config/nvim/${name}";
    value.source = ./neovim/${name};
  }) luaFiles // lib.mapAttrs' (name: path: {
    name = ".config/nvim/${name}";
    value.source = path;
  }) pluginFiles // {
    ".config/nvim/coc-settings.json".source = ./neovim/coc-settings.json;
  };
}
