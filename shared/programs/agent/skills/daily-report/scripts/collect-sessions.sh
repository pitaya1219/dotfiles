#!/usr/bin/env bash
# List agent session directories modified today, with their contents.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

SESSIONS_DIR=$(jq -r '.sources.sessions.dir' "$CONFIG" | sed "s|~|$HOME|")
TODAY=$(today)
for d in "$SESSIONS_DIR"/session-*/; do
  [ "$(date -r "$d" +%Y-%m-%d 2>/dev/null)" = "$TODAY" ] && echo "=== $d ===" && ls "$d"
done
