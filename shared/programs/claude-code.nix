{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ./mcp-servers.nix ];

  options = {
    dotfiles.claudeJson = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };

    dotfiles.claude-code.mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };

    dotfiles.claude-code.model = lib.mkOption {
      type = lib.types.str;
      default = "sonnet";
    };
  };

  config = let
    nixClaudeJson = pkgs.writeText "claude-json-nix" (builtins.toJSON config.dotfiles.claudeJson);
  in {
    # Remote HTTP MCP servers from the shared dotfiles.httpMcpServers option.
    # The url (e.g. Windmill's issued MCP URL) already carries its own auth
    # token as a query param; Claude Code expands the ${VAR} placeholder from
    # its own process env at connect time, so the token is never written here.
    dotfiles.claude-code.mcpServers = (lib.mapAttrs (_: srv: {
      type = "http";
      url = srv.url;
    }) config.dotfiles.httpMcpServers) // {
      gitea = {
        command = "gitea-mcp";
        args = [
          "-host"
          "\${GITEA_HOST}"
          "-token"
          "\${GITEA_CLAUDE_BOT_TOKEN}"
        ];
        env = {
          GITEA_USER = "claude-bot";
        };
      };
    };

    dotfiles.claudeJson.mcpServers = config.dotfiles.claude-code.mcpServers;

    home.file.".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/commands";
    home.file.".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/skills";

    # Claude Code-specific subagents (not shared via ~/.agent — Vibe's agents
    # live in ~/.vibe/agents as TOML, incompatible with these markdown definitions).
    # explore.md overrides the built-in Explore agent to pin it to Haiku:
    # since v2.1.198 the built-in inherits the main session model, so
    # exploration on an Opus/Sonnet session burns expensive tokens.
    home.file.".claude/agents" = {
      source = ./claude-code/agents;
      recursive = true;
    };

    home.file.".claude/settings.json".text = builtins.toJSON {
      statusLine = {
        type = "command";
        command = "${config.home.homeDirectory}/dotfiles/scripts/claude-statusline.sh";
      };
      model = config.dotfiles.claude-code.model;
      hooks = {
        Stop = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "${config.home.homeDirectory}/dotfiles/scripts/claude-notify.sh || true";
              }
            ];
          }
        ];
        PermissionRequest = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "${config.home.homeDirectory}/dotfiles/scripts/claude-event-notify.sh || true";
              }
            ];
          }
        ];
        Notification = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "${config.home.homeDirectory}/dotfiles/scripts/claude-event-notify.sh || true";
              }
            ];
          }
        ];
      };
    };

    # Symlink to the Nix store — inspect this file to see what Nix contributes.
    home.file.".claude.json.nix".source = nixClaudeJson;

    # Deep-merge Nix config into ~/.claude.json on every home-manager switch.
    # References the Nix store path directly so it is available before home.file links are created.
    home.activation.claudeJson = lib.hm.dag.entryAfter ["writeBoundary"] ''
      claude_json="$HOME/.claude.json"
      tmp=$(mktemp)
      if [ -f "$claude_json" ]; then
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$claude_json" "${nixClaudeJson}" > "$tmp"
      else
        cp "${nixClaudeJson}" "$tmp"
      fi
      mv "$tmp" "$claude_json"
    '';
  };
}
