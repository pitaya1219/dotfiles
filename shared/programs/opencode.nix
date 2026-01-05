{ config, pkgs, lib, ... }:

{
  # OpenCode commands directory
  home.file.".opencode/command" = {
    source = ./ai-commands;
    recursive = true;
  };
}
