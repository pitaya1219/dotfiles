{ pkgs, lib, config, ... }:

{
  # Profile-specific plugins for r-shibuya
  plugins = with pkgs.vimPlugins; [];

  # Profile-specific extra packages
  extraPackages = with pkgs; [];

}
