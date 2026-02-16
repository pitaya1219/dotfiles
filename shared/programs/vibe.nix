{ config, pkgs, lib, ... }:

{
  # Use shared AI commands directory
  home.file.".vibe/commands" = {
    source = ./ai-commands;
    recursive = true;
  };

  # Vibe settings (TOML format) with MCP server configuration
  home.file.".vibe/config.toml".source = ./vibe-config.toml;
}