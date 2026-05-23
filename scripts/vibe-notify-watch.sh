#!/usr/bin/env bash
# Monitors Vibe session logs; sends RocketChat notification when Vibe goes idle.
# Per-session rate limiting: each session has its own throttle state.
# Usage: vibe-notify-watch.sh [LOG_DIR]
# Meant to run as background process alongside vibe.

NOTIFY="$HOME/.agent/skills/agent-rocket-chat-notify/notify.sh"
LOG_DIR="${1:-${VIBE_HOME:-$HOME/.vibe}/logs/session}"
IDLE_THRESHOLD="${VIBE_NOTIFY_IDLE:-3}"
RATE_LIMIT="${VIBE_NOTIFY_RATE:-10}"

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
      # Extract session title from meta.json as summary
      SUMMARY=$(METAFILE="${latest_dir}/meta.json" python3 -c "
import json, os
try:
    with open(os.environ['METAFILE']) as f:
        print(json.load(f).get('title', ''))
except Exception:
    print('')
" 2>/dev/null || true)
      "$NOTIFY" \
        --agent-type mistral-vibe \
        --session-id "$current_session" \
        --summary "$SUMMARY" \
        --type info \
        --confirmation "Mistral Vibe is waiting for your response (session: ${current_session})" \
        &>/dev/null || true
      echo "$now" > "$state_file"
      echo "[vibe-notify-watch] Notification sent at $(date -Is) for session $current_session"
    fi
    was_active=false
  fi
done
