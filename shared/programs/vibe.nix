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
  # and project entries win on name collisions.
  home.file.".vibe/hooks.toml".text = ''
    [[hooks]]
    name = "secret-guard-pre-tool"
    type = "pre_tool"
    match = "bash"
    command = "python3 ${config.home.homeDirectory}/.vibe/hooks/secret_guard.py"
    description = "Deny bash commands that are likely to dump secrets to stdout."

    [[hooks]]
    name = "secret-guard-post-tool"
    type = "post_tool"
    match = "re:(bash|read_file|grep)"
    command = "python3 ${config.home.homeDirectory}/.vibe/hooks/secret_guard.py"
    description = "Redact secret-shaped strings from tool output before the model sees them."

    [[hooks]]
    name = "session-init-pre-tool"
    type = "pre_tool"
    match = "bash"
    command = "python3 ${config.home.homeDirectory}/.vibe/hooks/pre_tool.py"
    description = "Session initialization hook for AI Sessions Workspace."

    [[hooks]]
    name = "session-init-post-tool"
    type = "post_tool"
    match = "bash"
    command = "python3 ${config.home.homeDirectory}/.vibe/hooks/post_tool.py"
    description = "Session post-processing hook for AI Sessions Workspace."
  '';

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
    # Install hooks.toml for experimental hooks
    cp "${./vibe/hooks.toml}" "$HOME/.vibe/hooks.toml"
    chmod 644 "$HOME/.vibe/hooks.toml"
  '';
}
