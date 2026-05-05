{ config, pkgs, lib, ... }:

{
  # Use shared AI commands directory
  home.file.".vibe/commands" = {
    source = ./ai-commands;
    recursive = true;
  };

  # Gitea MCP wrapper script
  home.file.".vibe/gitea-mcp-wrapper.sh" = {
    text = builtins.readFile ../../scripts/gitea-mcp-wrapper.sh;
    executable = true;
  };

  # Copy vibe config to home directory (writable copy with envsubst)
  home.activation.installVibeConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.vibe"
    envsubst < "${./vibe/config.toml}" > "$HOME/.vibe/config.toml"
    chmod 644 "$HOME/.vibe/config.toml"
  '';
}
