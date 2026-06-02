{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ];

  options = {
    # Generic deep-merge target for ~/.claude.json.
    # Any module can contribute top-level keys here.
    dotfiles.claudeJson = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };

    # MCP servers collected from all profiles; merged into claudeJson.mcpServers.
    # Kept separate so multiple modules can extend it without conflict.
    dotfiles.claude-code.mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
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

    dotfiles.claudeJson.mcpServers = config.dotfiles.claude-code.mcpServers;

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

    # Deep-merge dotfiles.claudeJson into ~/.claude.json on every home-manager switch.
    # jq `*` recursively merges objects; Nix-defined values win on conflict.
    home.activation.claudeJson = lib.hm.dag.entryAfter ["writeBoundary"] ''
      claude_json="$HOME/.claude.json"
      tmp=$(mktemp)
      if [ -f "$claude_json" ]; then
        ${pkgs.jq}/bin/jq --argjson patch '${builtins.toJSON config.dotfiles.claudeJson}' \
          '. * $patch' "$claude_json" > "$tmp"
      else
        echo '${builtins.toJSON config.dotfiles.claudeJson}' > "$tmp"
      fi
      mv "$tmp" "$claude_json"
    '';
  };
}
