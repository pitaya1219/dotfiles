{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    tree
    curl
    expect        # for using unbuffer
    sqlite
    git
    pipx          # for installing python made tool into global
    claude-code
    ollama
    tmux
  ];
}
