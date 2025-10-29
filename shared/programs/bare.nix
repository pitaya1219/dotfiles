{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    gnused
    tree
    curl
    expect        # for using unbuffer
    zstd
    nodejs
    sqlite
    duckdb
    ripgrep
    pipx          # for installing python made tool into global
    poetry
    claude-code
    ollama
    nerd-fonts.daddy-time-mono
    nerd-fonts.shure-tech-mono
  ];
}
