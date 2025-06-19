{ config, pkgs, lib, ... }:

{

  imports = [
    ../shared/activations/aider.nix
    (import ../shared/programs/unfree.nix {})
    ../shared/programs/bare.nix
    (import ../shared/programs/neovim.nix { inherit config pkgs lib; profileName = "droid"; })
  ];

  home.packages = with pkgs; [
    htop
  ];
}
