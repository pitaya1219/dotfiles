{ config, pkgs, lib, ... }:

{
  imports = [
    ../shared/activations/aider.nix
    ../shared/programs/bare.nix
    (import ../shared/programs/neovim.nix { inherit config pkgs lib; profileName = "r-shibuya"; })
    (import ../shared/programs/unfree.nix { additionalPackages = [ "copilot.vim" ]; })
  ];

  home.packages = with pkgs; [
    jq
  ];
}
