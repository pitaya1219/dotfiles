#!/usr/bin/env bash
# List agent session directories last modified on the report date, with their
# contents. mtime is a proxy for "worked on that day" and drifts if a directory
# is touched later, so treat the result as a hint and prefer the Logseq pages.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

SESSIONS_DIR=$(jq -r '.sources.sessions.dir' "$CONFIG" | sed "s|~|$HOME|")
DATE=$(report_date) || exit 1
for d in "$SESSIONS_DIR"/session-*/; do
  [ "$(date -r "$d" +%Y-%m-%d 2>/dev/null)" = "$DATE" ] && echo "=== $d ===" && ls "$d"
done
