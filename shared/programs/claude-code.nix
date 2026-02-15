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
      command = ''input=$(cat); model=$(echo "$input" | jq -r '.model.display_name'); context=$(echo "$input" | jq -r '.context.percentage // 0'); cwd=$(echo "$input" | jq -r '.workspace.current_dir'); cd "$cwd" 2>/dev/null; branch=$(git branch --show-current 2>/dev/null); if [ "$context" -le 20 ]; then icon="○"; elif [ "$context" -le 40 ]; then icon="◔"; elif [ "$context" -le 60 ]; then icon="◐"; elif [ "$context" -le 80 ]; then icon="◕"; else icon="●"; fi; if [ -n "$branch" ]; then printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;130m⎇ %s\033[0m \033[38;5;240m%s %s%%\033[0m' "$model" "$branch" "$icon" "$context"; else printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;240m%s %s%%\033[0m' "$model" "$icon" "$context"; fi'';
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
