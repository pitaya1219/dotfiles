{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ];  # Agent directories are managed in agent.nix

  # Symlink .claude/commands -> .agent/commands
  home.file.".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/commands";

  # Symlink .claude/skills -> .agent/skills
  home.file.".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/skills";

  # Claude Code settings (statusLine + default model + Stop hook)
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
    mcpServers = {
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
  };
}
