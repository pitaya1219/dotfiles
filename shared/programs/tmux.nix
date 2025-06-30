{ config, pkgs, lib, ... }:

{
  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      resurrect
      continuum
    ];
  };
  
  # Create the main tmux configuration file
  home.file.".tmux.conf".source = ./tmux/tmux.conf;
}
