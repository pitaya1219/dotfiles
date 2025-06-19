{ config, pkgs, lib, ... }:

{
  imports = [
    ../shared/activations/aider.nix
    (import ../shared/programs/unfree.nix {})
    ../shared/programs/bare.nix
    (import ../shared/programs/neovim.nix { inherit config pkgs lib; profileName = "droid"; })
  ];

  home = {
    username = "droid";
    homeDirectory = "/home/droid";
    stateVersion = "23.11";
    packages = with pkgs; [
      htop
    ];
  };
}
