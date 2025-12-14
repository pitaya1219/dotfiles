{ config, pkgs, lib, ... }:

{
  home.file.".claude/commands" = {
    source = ./claude-code/commands;
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
          "\${GITEA_ACCESS_TOKEN}"
        ];
      };
    };
  };
}
