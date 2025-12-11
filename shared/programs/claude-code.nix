{ config, pkgs, lib, ... }:

{
  home.file.".claude/commands" = {
    source = ./claude-code/commands;
    recursive = true;
  };
}
