{ config, pkgs, lib, ... }:

{
  # Install agent directories (shared between all AI tools)
  home.file.".agent/commands" = {
    source = ./agent/commands;
    recursive = true;
  };

  home.file.".agent/skills" = {
    source = ./agent/skills;
    recursive = true;
  };
}
