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

MIDNIGHT_MS=$(( $(midnight_ts) * 1000 ))
EOD_MS=$(( MIDNIGHT_MS + 86400000 ))

# Query session pages (namespace "session/...") created today via datascript
QUERY="[:find (pull ?p [:block/name :block/original-name :block/created-at]) :where [?p :block/name ?name] [(clojure.string/starts-with? ?name \"session/\")] [?p :block/created-at ?ts] [(>= ?ts ${MIDNIGHT_MS})] [(< ?ts ${EOD_MS})]]"

PAGES=$(curl -sf \
  -H "Authorization: Bearer $TOK" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg q "$QUERY" '{method: "logseq.DB.datascriptQuery", args: [$q]}')" \
  "$URL/api" 2>/dev/null)

[ -z "$PAGES" ] && exit 0
COUNT=$(echo "$PAGES" | jq 'length' 2>/dev/null)
[ "$COUNT" = "0" ] && exit 0

TODAY=$(today)

echo "$PAGES" | jq -r '.[][] | .["original-name"] // .["name"]' 2>/dev/null | \
while IFS= read -r PAGE_NAME; do
  [ -z "$PAGE_NAME" ] && continue

  PAGE=$(curl -sf \
    -H "Authorization: Bearer $TOK" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg p "$PAGE_NAME" '{method: "logseq.Editor.getPage", args: [$p]}')" \
    "$URL/api" 2>/dev/null)

  # Filter by date property — only show sessions whose date == today.
  # date may be an array ["2026-06-15"] (Logseq page ref) or a raw string "[[2026-06-15]]".
  DATE_VAL=$(echo "$PAGE" | jq -r '.properties.date // ""')
  case "$DATE_VAL" in
    *"$TODAY"*) ;;  # string contains today → pass
    *)
      DATE_MATCH=$(echo "$PAGE" | jq -r --arg d "$TODAY" \
        'if (.properties.date | type) == "array" then (.properties.date | any(. == $d)) else false end' 2>/dev/null)
      [ "$DATE_MATCH" = "true" ] || continue ;;
  esac

  OBJECTIVE=$(echo "$PAGE" | jq -r 'if (.properties.objective | type) == "array" then .properties.objective[0] else (.properties.objective // "") end')
  REPO=$(echo "$PAGE"      | jq -r '.properties.repository // ""')
  BRANCH=$(echo "$PAGE"    | jq -r '.properties.gitBranch // ""')
  STATUS=$(echo "$PAGE"    | jq -r '.properties.status // ""')
  PR=$(echo "$PAGE"        | jq -r '.properties.pr // ""')
  MODEL=$(echo "$PAGE"     | jq -r '.properties.model // ""')

  echo "=== $PAGE_NAME ==="
  [ -n "$OBJECTIVE" ] && echo "  Objective : $OBJECTIVE"
  [ -n "$REPO" ]      && echo "  Repository: $REPO${BRANCH:+ @ $BRANCH}"
  [ -n "$PR" ]        && echo "  PR        : $PR"
  [ -n "$STATUS" ]    && echo "  Status    : $STATUS"
  [ -n "$MODEL" ]     && echo "  Model     : $MODEL"
  echo ""
done
