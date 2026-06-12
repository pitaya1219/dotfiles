#!/usr/bin/env bash
# Shared helpers for daily-report collectors.
# Run one helper directly:   bash scripts/lib.sh midnight_ts
# Or source from a script:   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG="${DAILY_REPORT_CONFIG:-$HOME/.agent/daily-report.json}"

# today: YYYY-MM-DD in local time.
today() { date +%Y-%m-%d; }

# midnight_ts: Unix timestamp for today's 00:00 JST — used as Slack search `after`.
# Gotcha: BSD date (macOS) and GNU date (Linux) take different flags; keep both branches.
midnight_ts() {
  date -j -f "%Y-%m-%d %H:%M:%S" "$(today) 00:00:00" "+%s" 2>/dev/null || \
  date -d "$(today) 00:00:00 JST" "+%s" 2>/dev/null
}

# Allow running a single helper directly: `bash lib.sh <fn> [args...]`
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "$#" -gt 0 ]; then "$@"; fi
