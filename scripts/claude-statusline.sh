#!/usr/bin/env bash
# Claude Code statusline script
# Displays: model, git branch, context percentage indicator

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
context=$(echo "$input" | jq -r '.context_window.used_percentage // null')
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
cd "$cwd" 2>/dev/null
branch=$(git branch --show-current 2>/dev/null)

# Check if context is available
if [ "$context" = "null" ] || [ -z "$context" ]; then
  icon="─"
  context_display="N/A"
else
  # 8-block bar: ████░░░░
  filled=$(( context * 8 / 100 ))
  [ "$filled" -gt 8 ] && filled=8
  empty=$(( 8 - filled ))
  icon=""
  for i in $(seq 1 $filled); do icon="${icon}█"; done
  for i in $(seq 1 $empty); do icon="${icon}░"; done
  context_display="${context}%"
fi

# Format output with colors
if [ -n "$branch" ]; then
  printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;130m⎇ %s\033[0m \033[38;5;240m%s %s\033[0m\n' "$model" "$branch" "$icon" "$context_display"
else
  printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;240m%s %s\033[0m\n' "$model" "$icon" "$context_display"
fi

# Display session ID on the bottom line
printf '\033[38;5;240m󰠮 %s\033[0m' "$session_id"
