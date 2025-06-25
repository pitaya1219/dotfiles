{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    gnused
    tree
    curl
    expect        # for using unbuffer
    sqlite
    pipx          # for installing python made tool into global
    claude-code
    ollama
    tmux
    nerd-fonts.daddy-time-mono
    nerd-fonts.shure-tech-mono
  ];
}
