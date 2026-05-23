{ config, pkgs, lib, ... }:

let
  # Base neovim plugins from shared configuration
  baseNeovimPlugins = import ./neovim/plugins.nix { inherit pkgs lib config; };
  
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
  
  # Read base coc-settings.json
  baseCocSettings = builtins.fromJSON (builtins.readFile ./neovim/coc-settings.json);
  cocSettingsFile = pkgs.writeText "coc-settings.json" (builtins.toJSON baseCocSettings);
in
{
  programs.neovim = {
    enable = true;
    package = pkgs.neovim;
    defaultEditor = true;
    viAlias = false;
    vimAlias = true;

    initLua = lib.fileContents ./neovim/init.lua;
    
    plugins = baseNeovimPlugins.plugins;
    extraPackages = baseNeovimPlugins.extraPackages;
  };

  # Create symlinks for lua configuration files (excluding init.lua)
  home.file = lib.mapAttrs' (name: _: {
    name = ".config/nvim/${name}";
    value.source = ./neovim/${name};
  }) luaFiles // lib.mapAttrs' (name: path: {
    name = ".config/nvim/${name}";
    value.source = path;
  }) pluginFiles;

  # Deploy coc-settings.json as regular file via activation (not symlink)
  # Use lib.mkDefault so profile overrides can take precedence
  home.activation.deployCocSettings = lib.mkDefault (lib.hm.dag.entryAfter ["checkLinkTargets"] ''
    mkdir -p "$HOME/.config/nvim"
    
    # Backup existing file only if content differs
    if [ -f "$HOME/.config/nvim/coc-settings.json" ] && ! diff -q "${cocSettingsFile}" "$HOME/.config/nvim/coc-settings.json" >/dev/null; then
      cp "$HOME/.config/nvim/coc-settings.json" "$HOME/.config/nvim/coc-settings.json.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    cp "${cocSettingsFile}" "$HOME/.config/nvim/coc-settings.json"
    chmod 644 "$HOME/.config/nvim/coc-settings.json"
  '');
}
