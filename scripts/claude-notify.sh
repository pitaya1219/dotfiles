#!/usr/bin/env bash
# Throttled notification wrapper for Claude Code Stop hook.
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
TRANSCRIPT="$HOME/.claude/projects/${PROJECT_PATH}/${SESSION_ID}.jsonl"
SUMMARY=$(TRANSCRIPT="$TRANSCRIPT" python3 -c "
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

# Extract the first line of the last assistant message
LAST_MSG=$(TRANSCRIPT="$TRANSCRIPT" python3 -c "
import json, os
try:
    with open(os.environ['TRANSCRIPT']) as f:
        for line in reversed(f.readlines()):
            obj = json.loads(line)
            if obj.get('type') == 'assistant':
                msg = obj.get('message', {})
                content = msg.get('content', '')
                text = ''
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get('type') == 'text':
                            text = block.get('text', '')
                            break
                elif isinstance(content, str):
                    text = content
                if text:
                    print(text.split('\n')[0][:200])
                    break
except Exception:
    pass
" 2>/dev/null || true)

# Per-session throttle state file
STATE_FILE="/tmp/claude-notify-${SESSION_ID}"

now=$(date +%s)
last=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

if (( now - last >= THROTTLE )); then
  echo "$now" > "$STATE_FILE"

  SHORT_SESSION="${SESSION_ID:0:8}"
  CONFIRMATION="Claude Code is waiting for your response (session: ${SESSION_ID})"
  if [ -n "$LAST_MSG" ]; then
    CONFIRMATION="${LAST_MSG}"
  fi
  NVIM_MSG="${SUMMARY:+${SUMMARY} | }${CONFIRMATION}"
  SCRIPTS_DIR="$HOME/dotfiles/scripts"

  "$SCRIPTS_DIR/nvim-notify.sh" \
    --title "Claude Code" \
    --message "$NVIM_MSG" \
    --level WARN \
    2>/dev/null &

  "$SCRIPTS_DIR/rocketchat-notify.sh" \
    --agent-type claude-code \
    --session-id "$SESSION_ID" \
    --summary "$SUMMARY" \
    --type info \
    --priority medium \
    --confirmation "$CONFIRMATION" \
    2>/dev/null &

  wait
fi
