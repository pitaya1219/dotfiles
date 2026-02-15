#!/usr/bin/env bash
# Claude Code statusline script
# Displays: model, git branch, context percentage indicator

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
context=$(echo "$input" | jq -r '.context_window.used_percentage // null')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
cd "$cwd" 2>/dev/null
branch=$(git branch --show-current 2>/dev/null)

# Check if context is available
if [ "$context" = "null" ] || [ -z "$context" ]; then
  icon="─"
  context_display="N/A"
else
  # Icon based on context percentage
  if [ "$context" -le 20 ]; then icon="○"
  elif [ "$context" -le 40 ]; then icon="◔"
  elif [ "$context" -le 60 ]; then icon="◐"
  elif [ "$context" -le 80 ]; then icon="◕"
  else icon="●"
  fi
  context_display="${context}%"
fi

# Format output with colors
if [ -n "$branch" ]; then
  printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;130m⎇ %s\033[0m \033[38;5;240m%s %s\033[0m' "$model" "$branch" "$icon" "$context_display"
else
  printf '\033[38;5;166m＊ %s ＊\033[0m \033[38;5;240m%s %s\033[0m' "$model" "$icon" "$context_display"
fi
