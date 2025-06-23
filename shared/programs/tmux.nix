{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [ tmux ];
  
  # Create the main tmux configuration file
  home.file.".tmux.conf".source = ./tmux/tmux.conf;
}
