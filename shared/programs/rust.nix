{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    rustc
    cargo
    rustfmt
    clippy
    rust-analyzer
    cargo-watch    # for auto-rebuild on file changes
    cargo-edit     # for cargo add/rm/upgrade commands
  ];
}
