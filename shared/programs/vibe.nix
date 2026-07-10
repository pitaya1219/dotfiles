{ config, pkgs, lib, ... }:

let
  tomlFormat = pkgs.formats.toml { };

  # Remote HTTP MCP servers from the shared dotfiles.httpMcpServers option.
  # `url` (e.g. Windmill's issued MCP URL, token and all) contains the
  # `${WINDMILL_MCP_URL}`-style placeholder from mcp-servers.nix; it's
  # resolved below via envsubst at activation time (see installVibeConfig) —
  # Vibe has no runtime env expansion for `url`, unlike Claude Code.
  generatedMcpServers = lib.mapAttrsToList (name: srv: {
    inherit name;
    transport = "http";
    url = srv.url;
  }) config.dotfiles.httpMcpServers;

  generatedMcpConfig = tomlFormat.generate "vibe-mcp-servers.toml" {
    mcp_servers = generatedMcpServers;
  };
in
{
  imports = [ ./agent.nix ./mcp-servers.nix ];  # Agent directories are managed in agent.nix

  # Symlink .vibe/commands -> .agent/commands
  home.file.".vibe/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/commands";

  # Symlink .vibe/skills -> .agent/skills
  home.file.".vibe/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/skills";

  # Custom agents. explore.toml overrides the builtin explore subagent to run
  # on a cheap model instead of inheriting the main session model.
  home.file.".vibe/agents" = {
    source = ./vibe/agents;
    recursive = true;
  };

  # Gitea MCP wrapper script
  home.file.".vibe/gitea-mcp-wrapper.sh" = {
    text = builtins.readFile ../../scripts/gitea-mcp-wrapper.sh;
    executable = true;
  };

  # Copy vibe config to home directory (writable copy with envsubst).
  # Static config.toml (theme, gitea stdio entry) plus generated http
  # mcp_servers entries (e.g. windmill) are concatenated, then envsubst
  # resolves the `${WINDMILL_MCP_URL}`-style placeholder in `url` fields,
  # since Vibe has no runtime env expansion there (unlike Claude Code).
  home.activation.installVibeConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.vibe"
    cat "${./vibe/config.toml}" "${generatedMcpConfig}" | envsubst > "$HOME/.vibe/config.toml"
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
