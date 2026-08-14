#!/usr/bin/env bash
# Notification wrapper for Vibe hooks.
# Reads hook JSON from stdin, applies throttling, then dispatches
# notifications to all configured channels.
#
# Only post_agent (agent turn completion) is registered in hooks.toml.
# post_agent fires once per completed user turn — the "waiting for
# response" signal, equivalent to Claude Code's Stop hook.

HOOK_INPUT=$(cat)

# --- Extract fields from hook JSON ------------------------------------------
read_json() {
  printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('$1', ''))
except Exception:
    print('')
" 2>/dev/null
}

SESSION_ID=$(read_json session_id)
TRANSCRIPT_PATH=$(read_json transcript_path)

SESSION_ID="${SESSION_ID:-${VIBE_SESSION_ID:-unknown}}"
SHORT_SESSION="${SESSION_ID:0:8}"

# --- Throttle: at most once per VIBE_NOTIFY_RATE seconds per session --------
RATE_LIMIT="${VIBE_NOTIFY_RATE:-10}"
STATE_FILE="/tmp/vibe-notify-${SESSION_ID}"
NOW=$(date +%s)
LAST_NOTIFY=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
if (( NOW - LAST_NOTIFY < RATE_LIMIT )); then
    echo '{}'
    exit 0
fi
echo "$NOW" > "$STATE_FILE"

# --- Extract session summary from transcript metadata ----------------------
SESSION_SUMMARY=""
LAST_MSG=""
if [ -n "$TRANSCRIPT_PATH" ]; then
    TRANSCRIPT_DIR="$(dirname "$TRANSCRIPT_PATH")"
    METAFILE="${TRANSCRIPT_DIR}/meta.json"
    MESSAGES="${TRANSCRIPT_DIR}/messages.jsonl"

    if [ -f "$METAFILE" ]; then
        SESSION_SUMMARY=$(METAFILE="$METAFILE" python3 -c "
import json, os
try:
    with open(os.environ['METAFILE']) as f:
        print(json.load(f).get('title', ''))
except Exception:
    print('')
" 2>/dev/null || true)
    fi

    # Extract the first line of the last non-empty assistant message
    if [ -f "$MESSAGES" ]; then
        LAST_MSG=$(MESSAGES="$MESSAGES" python3 -c "
import json, os
try:
    with open(os.environ['MESSAGES']) as f:
        for line in reversed(f.readlines()):
            obj = json.loads(line)
            if obj.get('role') == 'assistant':
                content = obj.get('content', '')
                if content:
                    print(content.split('\n')[0][:200])
                    break
except Exception:
    pass
" 2>/dev/null || true)
    fi
fi

# --- Build notification content ---------------------------------------------
CONFIRMATION_ITEM="Agent turn completed - awaiting next input"
if [ -n "$LAST_MSG" ]; then
    CONFIRMATION_ITEM="${LAST_MSG}"
fi
MESSAGE_TYPE="info"
PRIORITY="low"
NVIM_TITLE="Vibe"
NVIM_MSG="${SESSION_SUMMARY:+${SESSION_SUMMARY} | }Waiting for response (session: ${SHORT_SESSION})"
NVIM_LEVEL="WARN"

# --- Dispatch notifications -------------------------------------------------
SCRIPTS_DIR="$HOME/dotfiles/scripts"

"$SCRIPTS_DIR/nvim-notify.sh" \
  --title "$NVIM_TITLE" \
  --message "$NVIM_MSG" \
  --level "$NVIM_LEVEL" \
  >/dev/null 2>&1 &

"$SCRIPTS_DIR/rocketchat-notify.sh" \
  --agent-type mistral-vibe \
  --session-id "$SESSION_ID" \
  --summary "$SESSION_SUMMARY" \
  --type "$MESSAGE_TYPE" \
  --priority "$PRIORITY" \
  --confirmation "$CONFIRMATION_ITEM" \
  >/dev/null 2>&1 &

wait
echo '{}'
exit 0
