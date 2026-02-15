{ config, pkgs, lib, ... }:

{
  # Use shared AI commands directory
  home.file.".claude/commands" = {
    source = ./ai-commands;
    recursive = true;
  };

  # Claude Code settings (statusLine + default model)
  home.file.".claude/settings.json".text = builtins.toJSON {
    statusLine = {
      type = "command";
      command = "${config.home.homeDirectory}/dotfiles/scripts/claude-statusline.sh";
    };
    model = "sonnet";
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
