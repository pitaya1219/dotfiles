{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    htop
    tree
  ];
}
