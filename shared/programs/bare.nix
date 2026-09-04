{ pkgs, ... }:
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
    fzf
    age
    passage
    direnv
    pipx          # for installing python made tool into global
    poetry
    claude-code
    opencode
    ollama
    openssh
    nerd-fonts.daddy-time-mono
    nerd-fonts.shure-tech-mono
  ];
}
