#!/usr/bin/env bash
# Collect the report date's agent session pages from Logseq.
# Exits silently if Logseq is unavailable or no sessions match that day.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

command -v logseq-db >/dev/null 2>&1 || exit 0
logseq-db status || exit 0

DATE=$(report_date) || exit 1

# Matched on the `date` property, which session-save writes and which stays
# put, rather than on when the page entered the local database: a fresh
# download of the graph rewrites that for every page at once.
PAGES=$(logseq-db pages --date "$DATE" --tag claude-code-session --tag vibe-session --tag unknown-session 2>/dev/null)

[ -z "$PAGES" ] && exit 0

echo "$PAGES" | jq -r '
  sort_by(.title)
  | .[]
  | .properties as $p
  | "=== \(.title) ===",
    (if $p.objective then "  Objective : \($p.objective)" else empty end),
    (if $p.repository then "  Repository: \($p.repository)\(if $p["git-branch"] then " @ \($p["git-branch"])" else "" end)" else empty end),
    (if $p.pr then "  PR        : \($p.pr)" else empty end),
    (if $p.status then "  Status    : \($p.status)" else empty end),
    (if $p.model then "  Model     : \($p.model)" else empty end),
    ""
' 2>/dev/null
