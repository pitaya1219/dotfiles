{ pkgs, lib, config, ... }:

{
  plugins = with pkgs.vimPlugins; [];
  extraPackages = with pkgs; [];
}
