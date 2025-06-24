{ config, pkgs, lib, ... }:

let
  # Base starship configuration from shared
  baseStarshipConfig = builtins.readFile ./starship/default.toml;
  starshipConfigFile = pkgs.writeText "starship.toml" baseStarshipConfig;
in
{
  programs.starship = {
    enable = true;
  };
  home.file = {
    ".config/starship.toml".source = starshipConfigFile;
  };
}
