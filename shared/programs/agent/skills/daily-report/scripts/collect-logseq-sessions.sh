#!/usr/bin/env bash
# Collect today's agent session pages from Logseq.
# Exits silently if Logseq is unavailable or no sessions found today.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

CFG="$HOME/.agent/logseq.json"
[ -f "$CFG" ] || exit 0

resolve_val() {
  local KEY="$1"
  local TYPE; TYPE=$(jq -r "$KEY | type" "$CFG")
  case "$TYPE" in
    string) jq -r "$KEY" "$CFG" ;;
    object)
      local SUBKEY; SUBKEY=$(jq -r "$KEY | keys[0]" "$CFG")
      case "$SUBKEY" in
        file)    cat "$(jq -r "$KEY.file" "$CFG" | sed "s|~|$HOME|")" 2>/dev/null ;;
        command) eval "$(jq -r "$KEY.command" "$CFG")" 2>/dev/null ;;
      esac ;;
  esac
}

URL=$(resolve_val '.url')
TOK=$(resolve_val '.token')

curl -sf --max-time 3 \
  -H "Authorization: Bearer $TOK" \
  -H "Content-Type: application/json" \
  -d '{"method":"logseq.App.getUserConfigs","args":[]}' \
  "$URL/api" > /dev/null 2>&1 || exit 0

TODAY=$(today)

# Pull every session page together with its properties in one datascript query.
#
# Deliberately NOT filtered on :block/created-at: that timestamp reflects when
# the page entered the *local* graph database, so a re-index (or a fresh clone
# on another device) rewrites it to the re-index time for every page at once.
# A whole day of sessions then silently drops out of the report. The `date::`
# property is written by session-save and stays put, so it is the only
# trustworthy notion of "which day did this session happen".
QUERY='[:find (pull ?p [:block/name :block/original-name :block/properties]) :where [?p :block/name ?name] [(clojure.string/starts-with? ?name "session/")] [?p :block/properties _]]'

PAGES=$(curl -sf \
  -H "Authorization: Bearer $TOK" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg q "$QUERY" '{method: "logseq.DB.datascriptQuery", args: [$q]}')" \
  "$URL/api" 2>/dev/null)

[ -z "$PAGES" ] && exit 0

# Property keys come back in their on-disk kebab-case form here (git-branch),
# unlike logseq.Editor.getPage which camel-cases them (gitBranch).
#
# `date` may be an array ["2026-06-15"], a plain string, or a page ref
# "[[2026-06-15]]"; stringifying the whole value covers all three.
echo "$PAGES" | jq -r --arg today "$TODAY" '
  def one(v): if (v | type) == "array" then (v[0] // "") else (v // "") end;

  [ .[][] | select((.properties.date | tostring) | contains($today)) ]
  | sort_by(.name)
  | .[]
  | (.["original-name"] // .name) as $name
  | one(.properties.objective)    as $objective
  | one(.properties.repository)   as $repo
  | one(.properties["git-branch"]) as $branch
  | one(.properties.pr)           as $pr
  | one(.properties.status)       as $status
  | one(.properties.model)        as $model
  | "=== \($name) ===",
    (if $objective != "" then "  Objective : \($objective)" else empty end),
    (if $repo != "" then "  Repository: \($repo)\(if $branch != "" then " @ \($branch)" else "" end)" else empty end),
    (if $pr != "" then "  PR        : \($pr)" else empty end),
    (if $status != "" then "  Status    : \($status)" else empty end),
    (if $model != "" then "  Model     : \($model)" else empty end),
    ""
' 2>/dev/null
