{ config, pkgs, ... }:

{

  imports = [
    ../shared/activations/aider.nix
    (import ../shared/programs/unfree.nix {})
    ../shared/programs/bare.nix
    ../shared/programs/neovim.nix
  ];

  home.packages = with pkgs; [
    htop
  ];
}
