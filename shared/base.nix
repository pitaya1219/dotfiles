{ config, pkgs, lib, ... }:

{
  imports = [
    ./activations/aider.nix
    ./programs/bare.nix
  ];
}
