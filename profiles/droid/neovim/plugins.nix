{ pkgs, lib, config, ... }:

{
  # Profile-specific plugins for droid
  plugins = with pkgs.vimPlugins; [
    # Add droid-specific plugins here
  ];

  # Profile-specific extra packages
  extraPackages = with pkgs; [
    # Add any droid specific packages here
  ];
}
