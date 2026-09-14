#!/usr/bin/env bash
# Shared helpers for daily-report collectors.
# Run one helper directly:   bash scripts/lib.sh day_start_ts
# Or source from a script:   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG="${DAILY_REPORT_CONFIG:-$HOME/.agent/daily-report.json}"

# report_date: the day the report covers, YYYY-MM-DD in local time.
# DAILY_REPORT_DATE points every collector at a past day; unset means today.
report_date() {
  local d="${DAILY_REPORT_DATE:-}"
  if [ -z "$d" ]; then
    date +%Y-%m-%d
    return
  fi
  case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) echo "$d" ;;
    *) echo "DAILY_REPORT_DATE must be YYYY-MM-DD, got '$d'" >&2; return 1 ;;
  esac
}

# Gotcha: BSD date (macOS) and GNU date (Linux) take different flags; keep both
# branches in each helper below.
_midnight_ts() {
  date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" "+%s" 2>/dev/null || \
  date -d "$1 00:00:00" "+%s" 2>/dev/null
}

_next_day() {
  date -j -v+1d -f "%Y-%m-%d" "$1" "+%Y-%m-%d" 2>/dev/null || \
  date -d "$1 + 1 day" "+%Y-%m-%d" 2>/dev/null
}

# day_start_ts / day_end_ts: Unix timestamps bounding the report date in local
# time, as the half-open range [start, end). Slack search takes them as `after`
# and `before`; without the upper bound a past date returns everything since.
day_start_ts() { _midnight_ts "$(report_date)"; }
day_end_ts() { _midnight_ts "$(_next_day "$(report_date)")"; }

# utc_iso: a Unix timestamp as the UTC instant APIs stamp their records with.
utc_iso() {
  date -u -r "$1" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
  date -u -d "@$1" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}

# Allow running a single helper directly: `bash lib.sh <fn> [args...]`
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "$#" -gt 0 ]; then "$@"; fi
