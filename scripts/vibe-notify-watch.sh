#!/usr/bin/env bash
# Monitors Vibe session logs; sends RocketChat notification when Vibe goes idle.
# Per-session rate limiting: each session has its own throttle state.
# Usage: vibe-notify-watch.sh [LOG_DIR]
# Meant to run as background process alongside vibe.

NOTIFY="$HOME/.agent/skills/agent-rocket-chat-notify/notify.sh"
NVIM_NOTIFY="$HOME/dotfiles/scripts/nvim-notify.sh"
LOG_DIR="${1:-${VIBE_HOME:-$HOME/.vibe}/logs/session}"
IDLE_THRESHOLD="${VIBE_NOTIFY_IDLE:-3}"
RATE_LIMIT="${VIBE_NOTIFY_RATE:-10}"
SESSION_EVENTS_FILE="${VIBE_SESSION_EVENTS:-/tmp/vibe-session-events}"

# Prevent duplicate instances via PID file
PIDFILE="/tmp/vibe-notify-watch.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "[vibe-notify-watch] Already running (PID $(cat "$PIDFILE")), exiting."
  exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT INT TERM

last_active=$(date +%s)
was_active=false
current_session=""

get_latest_dir() {
  ls -dt "$LOG_DIR"/session_*/ 2>/dev/null | head -1
}

get_session_id() {
  local dir="$1"
  [ -n "$dir" ] && basename "$dir" | sed 's/^session_//' || echo "unknown"
}

get_dir_mtime() {
  find "$1" -maxdepth 2 -printf '%T@\n' 2>/dev/null | sort -rn | head -1
}

prev_dir=$(get_latest_dir)
prev_mtime=$(get_dir_mtime "${prev_dir:-.}")
current_session=$(get_session_id "$prev_dir")

echo "[vibe-notify-watch] Watching: $LOG_DIR (idle threshold: ${IDLE_THRESHOLD}s)"
[ -n "$current_session" ] && echo "[vibe-notify-watch] Current session: $current_session"

while true; do
  sleep 1

  latest_dir=$(get_latest_dir)
  new_session=$(get_session_id "$latest_dir")

  # New session started — reset state
  if [ "$new_session" != "$current_session" ]; then
    current_session="$new_session"
    prev_mtime=$(get_dir_mtime "${latest_dir:-.}")
    last_active=$(date +%s)
    was_active=false
    echo "[vibe-notify-watch] New session detected: $current_session"
    # Publish event for Neovim to consume: "<epoch> <session_dir>"
    echo "$(date +%s) $latest_dir" >> "$SESSION_EVENTS_FILE"
    # Trim to last 500 entries to prevent unbounded growth
    if [ -f "$SESSION_EVENTS_FILE" ] && [ "$(wc -l < "$SESSION_EVENTS_FILE")" -gt 1000 ]; then
      tail -n 500 "$SESSION_EVENTS_FILE" > "${SESSION_EVENTS_FILE}.tmp" \
        && mv "${SESSION_EVENTS_FILE}.tmp" "$SESSION_EVENTS_FILE"
    fi
    continue
  fi

  curr_mtime=$(get_dir_mtime "${latest_dir:-.}")
  now=$(date +%s)

  if [ "$curr_mtime" != "$prev_mtime" ]; then
    prev_mtime=$curr_mtime
    last_active=$now
    was_active=true
  elif $was_active && (( now - last_active >= IDLE_THRESHOLD )); then
    # Per-session rate limit state file
    state_file="/tmp/vibe-notify-${current_session}"
    last_notify=$(cat "$state_file" 2>/dev/null || echo 0)

    if (( now - last_notify >= RATE_LIMIT )); then
      # Only notify if last message is a final assistant response (not mid-tool-call)
      IS_WAITING=$(MESSAGES_FILE="${latest_dir}/messages.jsonl" python3 -c "
import json, os
try:
    last = None
    with open(os.environ['MESSAGES_FILE']) as f:
        for line in f:
            line = line.strip()
            if line:
                try: last = json.loads(line)
                except: pass
    if last and last.get('role') == 'assistant' and last.get('content') and not last.get('tool_calls'):
        print('yes')
    else:
        print('no')
except Exception:
    print('no')
" 2>/dev/null || echo "no")

      if [ "$IS_WAITING" = "yes" ]; then
        # Extract session title from meta.json as summary
        SUMMARY=$(METAFILE="${latest_dir}/meta.json" python3 -c "
import json, os
try:
    with open(os.environ['METAFILE']) as f:
        print(json.load(f).get('title', ''))
except Exception:
    print('')
" 2>/dev/null || true)
        # Notify all registered nvim instances via vim.notify() (registry-based; no $NVIM set for daemon)
        "$NVIM_NOTIFY" \
          --title "Vibe" \
          --message "${SUMMARY:+${SUMMARY} | }Waiting for response (session: ${current_session:0:8})" \
          --level WARN \
          &>/dev/null || true
        "$NOTIFY" \
          --agent-type mistral-vibe \
          --session-id "$current_session" \
          --summary "$SUMMARY" \
          --type info \
          --confirmation "Mistral Vibe is waiting for your response (session: ${current_session})" \
          &>/dev/null || true
        echo "$now" > "$state_file"
        echo "[vibe-notify-watch] Notification sent at $(date -Is) for session $current_session"
      else
        echo "[vibe-notify-watch] Idle but Vibe still processing, skipping notification"
      fi
    fi
    was_active=false
  fi
done
