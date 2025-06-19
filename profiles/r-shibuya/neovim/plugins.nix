{ pkgs, lib, config, ... }:

{
  # Profile-specific plugins for r-shibuya
  plugins = with pkgs.vimPlugins; [
    copilot-vim
  ];

  # Profile-specific extra packages
  extraPackages = with pkgs; [
    # Add any r-shibuya specific packages here
  ];

}
