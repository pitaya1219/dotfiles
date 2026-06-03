#!/usr/bin/env bash
# Throttled RocketChat notification for Claude Code Stop hook.
# Sends at most once per CLAUDE_NOTIFY_THROTTLE seconds per session (default 30).
# Reads {"session_id": "..."} from stdin (provided by Claude Code Stop hook).

THROTTLE="${CLAUDE_NOTIFY_THROTTLE:-30}"

# Parse session ID from hook JSON input
HOOK_INPUT=$(cat)
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    print('')
" 2>/dev/null)
SESSION_ID="${SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"

# Extract session title from transcript as summary
PROJECT_PATH=$(pwd | sed 's|/|-|g')
SUMMARY=$(TRANSCRIPT="$HOME/.claude/projects/${PROJECT_PATH}/${SESSION_ID}.jsonl" python3 -c "
import json, os
title = ''
try:
    with open(os.environ['TRANSCRIPT']) as f:
        for line in f:
            try:
                obj = json.loads(line)
                if obj.get('type') == 'ai-title':
                    title = obj.get('aiTitle', '')
            except Exception:
                pass
except Exception:
    pass
print(title)
" 2>/dev/null || true)

# Per-session throttle state file
STATE_FILE="/tmp/claude-notify-${SESSION_ID}"

now=$(date +%s)
last=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

if (( now - last >= THROTTLE )); then
  echo "$now" > "$STATE_FILE"

  # Notify the nvim that hosts this claude terminal (only when running inside nvim)
  if [ -n "${NVIM:-}" ]; then
    NVIM_MSG="${SUMMARY:+${SUMMARY} | }Waiting for response (session: ${SESSION_ID:0:8})"
    "$HOME/dotfiles/scripts/nvim-notify.sh" \
      --title "Claude Code" \
      --message "$NVIM_MSG" \
      --level WARN \
      --skip-registry 2>/dev/null || true
  fi

  exec "$HOME/.agent/skills/agent-rocket-chat-notify/notify.sh" \
    --agent-type claude-code \
    --session-id "$SESSION_ID" \
    --summary "$SUMMARY" \
    --type info \
    --confirmation "Claude Code is waiting for your response (session: ${SESSION_ID})" \
    "$@"
fi
