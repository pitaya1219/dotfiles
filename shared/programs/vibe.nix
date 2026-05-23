{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ];  # Agent directories are managed in agent.nix

  # Symlink .vibe/commands -> .agent/commands
  home.file.".vibe/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/commands";

  # Symlink .vibe/skills -> .agent/skills
  home.file.".vibe/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/skills";

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

  # Auto-start vibe-notify-watch on shell login (cross-platform; script handles dedup via PID file)
  programs.bash.initExtra = ''
    nohup "${config.home.homeDirectory}/dotfiles/scripts/vibe-notify-watch.sh" \
      "${config.home.homeDirectory}/agent-sessions/.vibe/logs/session" \
      > /dev/null 2>&1 &
    disown
  '';
}
