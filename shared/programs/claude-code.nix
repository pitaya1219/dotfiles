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
      command = ''input=$(cat); model=$(echo "$input" | jq -r '.model.display_name'); cwd=$(echo "$input" | jq -r '.workspace.current_dir'); cd "$cwd" 2>/dev/null; branch=$(git branch --show-current 2>/dev/null); if [ -n "$branch" ]; then printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;130m⎇ %s\033[0m' "$model" "$branch"; else printf '\033[38;5;166m＊ %s ＊\033[0m' "$model"; fi'';
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
