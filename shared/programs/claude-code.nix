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

    xdg.configFile."claude-code/mcp.json".text = builtins.toJSON {
      mcpServers = config.dotfiles.claude-code.mcpServers;
    };
  };
}
