{ config, pkgs, lib, ... }:

{
  imports = [
    ../shared/activations/aider.nix
    ../shared/programs/bare.nix
    ../shared/programs/neovim.nix
    (import ../shared/programs/unfree.nix { additionalPackages = [ "copilot.vim" ]; })
  ];

  home.packages = with pkgs; [
    jq
  ];
}
