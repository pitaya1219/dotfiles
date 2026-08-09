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

  # secret_guard.py imports the shared scanner from ~/.agent/secret_guard
  # (see agent.nix) via a relative sys.path insert.
  home.file.".vibe/hooks" = {
    source = ./vibe/hooks;
    recursive = true;
  };

  # Global hooks.toml (~/.vibe/hooks.toml) — loaded for every project unless
  # a project-local .vibe/hooks.toml also exists, in which case both apply
  # and project entries win on name collisions. Symlinked straight from the
  # repo (single source of truth) — do not also write/cp this path from
  # home.activation below, that raced against this symlink and left the
  # session-tab-pointer hooks never actually installed.
  home.file.".vibe/hooks.toml".source = ./vibe/hooks.toml;

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
}
