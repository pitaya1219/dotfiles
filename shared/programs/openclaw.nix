{ config, pkgs, lib, ... }:

{
  # OpenClaw settings
  home.file.".openclaw/settings.json".text = builtins.toJSON {
    statusLine = {
      type = "command";
      command = "input=$(cat); model=$(echo \"$input\" | jq -r '.model.display_name'); cwd=$(echo \"$input\" | jq -r '.workspace.current_dir'); cd \"$cwd\" 2>/dev/null; branch=$(git branch --show-current 2>/dev/null); if [ -n \"$branch\" ]; then printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;130m⎇ %s\033[0m' \"$model\" \"$branch\"; else printf '\033[38;5;166m＊ %s ＊\033[0m' \"$model\"; fi";
    };
    model = "haiku";
  };

  xdg.configFile."openclaw/mcp.json".text = builtins.toJSON {
    mcpServers = {
      gitea = {
        command = "gitea-mcp";
        args = [
          "-host"
          "${config.env.GITEA_HOST or ""}"
          "-token"
          "${config.env.GITEA_AI_BOT_TOKEN or ""}"
        ];
        env = {
          GITEA_USER = "ai-bot";
        };
      };
    };
  };
}