{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ];

  options = {
    dotfiles.claudeJson = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };

    dotfiles.claude-code.mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };

  config = let
    nixClaudeJson = pkgs.writeText "claude-json-nix" (builtins.toJSON config.dotfiles.claudeJson);
  in {
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
        PreToolUse = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "${config.home.homeDirectory}/dotfiles/scripts/claude-session-dir-check.sh";
              }
            ];
          }
        ];
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
