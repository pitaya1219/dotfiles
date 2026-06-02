{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ];

  options.dotfiles.claude-code.mcpServers = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
  };

  config = {
    dotfiles.claude-code.mcpServers = {
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

    home.file.".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/commands";
    home.file.".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/skills";

    home.file.".claude/settings.json".text = builtins.toJSON {
      statusLine = {
        type = "command";
        command = "${config.home.homeDirectory}/dotfiles/scripts/claude-statusline.sh";
      };
      model = "sonnet";
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

    # Merge MCP servers into ~/.claude.json (user scope).
    # Runs on every home-manager switch; Nix-defined servers always win.
    home.activation.claudeCodeMcpServers = lib.hm.dag.entryAfter ["writeBoundary"] ''
      claude_json="$HOME/.claude.json"
      if [ -f "$claude_json" ]; then
        tmp=$(mktemp)
        ${pkgs.jq}/bin/jq --argjson servers '${builtins.toJSON config.dotfiles.claude-code.mcpServers}' \
          '.mcpServers = ((.mcpServers // {}) + $servers)' \
          "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
      fi
    '';
  };
}
