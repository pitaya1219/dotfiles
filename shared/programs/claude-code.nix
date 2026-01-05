{ config, pkgs, lib, ... }:

{
  # Use shared AI commands directory
  home.file.".claude/commands" = {
    source = ./ai-commands;
    recursive = true;
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
