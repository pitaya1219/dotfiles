# browse — one fzf picker over bookmarks, open browser tabs, browsing history
# and the GitHub review queue.
#
# Every source prints the same four tab-separated fields, which is what lets a
# single `open_target` handle any row the picker returns:
#
#   1 source   the tag shown at the left of the list; for bookmarks this is
#              the group the entry belongs to, so the list reads as folders
#   2 display  the human-readable label
#   3 target   a URL, `tab:<window id>:<tab index>` for an already-open tab,
#              or `group:<name>` for a folder row that drills in rather than
#              opening anything
#   4 url      the URL, kept separately so tab rows can still be matched and
#              bookmarked by URL
#
# Sources are switched inside fzf via reload(), which re-enters this script with
# `--source <name>`; that subcommand is also usable on its own. The group
# currently drilled into is held in a file rather than passed on the command
# line, so no user-authored text ever has to survive being pasted into an fzf
# action string.

BROWSER="${BROWSE_BROWSER:-Brave Browser}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/browse"
BOOKMARKS="$CONFIG_DIR/bookmarks.tsv"
DEFAULT_GROUP="inbox"
UNGROUPED_LABEL="-"
TAB=$'\t'

# Set by --state to a directory holding what a binding needs to hand to the
# next invocation: which folder is being browsed, and the one-line result of
# the last action. Deliberately not $WORKDIR itself -- sources drop scratch
# files there, and one named `group` or `status` would clobber picker state.
STATE_DIR=""

# Whether opening a row should also bring the browser forward. Off by default,
# because a selection is usually one step of a pass through the list rather
# than a decision to leave the terminal; --focus is the deliberate "take me
# there" that ctrl-l is bound to.
FOCUS=0

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# The history database lives under a per-browser path that has nothing to do
# with the application name, so it has to be mapped explicitly. Unknown
# browsers simply lose the history source rather than failing.
profile_dir() {
  case "$BROWSER" in
    "Brave Browser") printf '%s\n' "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default" ;;
    "Google Chrome") printf '%s\n' "$HOME/Library/Application Support/Google/Chrome/Default" ;;
    *) return 1 ;;
  esac
}

# Actions that change something but leave the list looking identical are
# indistinguishable from a key that did not register, so each one leaves a line
# here for the header to pick up.
set_status() {
  [ -n "$STATE_DIR" ] || return 0
  printf '%s' "$1" >"$STATE_DIR/status"
}

# Absent file means no filter at all; an existing but empty file means the
# ungrouped entries specifically. The two cases have to stay distinguishable,
# which is why this is not just a variable holding a possibly-empty string.
group_filter_active() {
  [ -n "$STATE_DIR" ] && [ -f "$STATE_DIR/group" ]
}

current_group() {
  group_filter_active || return 0
  cat "$STATE_DIR/group"
}

# The status line is consumed as it is read, so it survives exactly one redraw
# and the header falls back to the key legend on the next action. The blank
# third line is printed even when empty to keep the list from shifting up and
# down as messages come and go.
picker_header() {
  local status=""
  if [ -n "$STATE_DIR" ] && [ -f "$STATE_DIR/status" ]; then
    status=$(cat "$STATE_DIR/status")
    rm -f "$STATE_DIR/status"
  fi
  printf '%s\n' 'enter 開く(裏で) / ctrl-l 開いて前面へ / ctrl-t tab / ctrl-r 履歴 / ctrl-g PR / ctrl-y issue'
  printf '%s\n' 'ctrl-f フォルダ / ctrl-b 全件 / ctrl-s 登録 / ctrl-o フォルダへ / ctrl-x 閉じる / ctrl-e 編集 / esc 終了'
  printf '%s\n' "${status:+» $status}"
}

# ---------------------------------------------------------------- sources ---

# Emits canonical `group / label / url` per entry: comments dropped, and the
# two-column `label / url` form widened with an empty group so a file written
# by hand in the older shape still works. The shape of a bookmark line is
# spelled out here and, apart from the rewrite in move_bookmark, nowhere else.
normalize_bookmarks() {
  [ -f "$BOOKMARKS" ] || return 0
  awk -F'\t' 'BEGIN { OFS = "\t" }
    /^[[:space:]]*#/ { next }
    NF >= 3 { print $1, $2, $3; next }
    NF == 2 { print "", $1, $2 }
  ' "$BOOKMARKS"
}

source_bookmarks() {
  local on=0 want=""
  if group_filter_active; then
    on=1
    want=$(current_group)
  fi
  normalize_bookmarks | awk -F'\t' -v on="$on" -v want="$want" -v none="$UNGROUPED_LABEL" '
    on == 1 && $1 != want { next }
    { printf "%s\t%s\t%s\t%s\n", ($1 == "" ? none : $1), $2, $3, $3 }
  '
}

# The folder listing. Selecting a row here drills into the group rather than
# opening anything -- see handle_enter.
source_groups() {
  normalize_bookmarks | awk -F'\t' -v none="$UNGROUPED_LABEL" '
    { if (!($1 in count)) order[++n] = $1; count[$1]++ }
    END {
      for (i = 1; i <= n; i++) {
        g = order[i]
        printf "group\t%s (%d)\tgroup:%s\t\n", (g == "" ? none : g), count[g], g
      }
    }
  '
}

# Titles and URLs are fetched a column at a time rather than tab by tab. Every
# attribute read is an Apple Event, so the per-tab form costs three round trips
# per tab where this costs two per window -- the difference is what makes
# listing a large window fast enough to sit behind a keypress.
source_tabs() {
  command -v osascript >/dev/null 2>&1 || return 0
  osascript <<APPLESCRIPT 2>/dev/null || true
tell application "$BROWSER"
  set fieldSep to (ASCII character 9)
  set out to ""
  repeat with w in windows
    set wid to id of w
    set titles to title of tabs of w
    set links to URL of tabs of w
    repeat with i from 1 to (count of titles)
      set out to out & "tab" & fieldSep & (item i of titles) & fieldSep & ¬
        "tab:" & wid & ":" & i & fieldSep & (item i of links) & linefeed
    end repeat
  end repeat
  return out
end tell
APPLESCRIPT
}

# Review requests and own pull requests are two separate searches, run
# concurrently because each round trip costs well over a second.
source_prs() {
  command -v gh >/dev/null 2>&1 || return 0
  gh search prs --review-requested=@me --state=open --limit 40 \
    --json repository,number,title,url >"$WORKDIR/review.json" 2>/dev/null &
  gh search prs --author=@me --state=open --limit 40 \
    --json repository,number,title,url >"$WORKDIR/mine.json" 2>/dev/null &
  wait
  for f in review mine; do
    [ -s "$WORKDIR/$f.json" ] || printf '[]' >"$WORKDIR/$f.json"
  done
  jq -rs '
    (.[0] | map(. + {tag: "pr:review"})) + (.[1] | map(. + {tag: "pr:mine"}))
    | unique_by(.url)
    | .[]
    | [.tag, "\(.repository.nameWithOwner)#\(.number) \(.title)", .url, .url]
    | @tsv
  ' "$WORKDIR/review.json" "$WORKDIR/mine.json"
}

source_issues() {
  command -v gh >/dev/null 2>&1 || return 0
  { gh search issues --assignee=@me --state=open --limit 40 \
      --json repository,number,title,url 2>/dev/null || printf '[]'; } |
    jq -r '
      .[]
      | ["issue", "\(.repository.nameWithOwner)#\(.number) \(.title)", .url, .url]
      | @tsv
    '
}

# The live database is locked while the browser runs, so query a copy. The -wal
# file has to come along or recent visits are missing from the copy.
source_history() {
  local dir db
  dir=$(profile_dir) || return 0
  db="$dir/History"
  [ -f "$db" ] || return 0
  cp "$db" "$WORKDIR/History" 2>/dev/null || return 0
  if [ -f "$db-wal" ]; then
    cp "$db-wal" "$WORKDIR/History-wal" 2>/dev/null || true
  fi
  # Chromium stores timestamps as microseconds since 1601-01-01; 11644473600 is
  # the offset from there to the Unix epoch.
  sqlite3 -separator "$TAB" "$WORKDIR/History" "
    SELECT replace(replace(title, char(9), ' '), char(10), ' '), url
      FROM urls
     WHERE title <> ''
       AND last_visit_time > (strftime('%s', 'now', '-90 days') + 11644473600) * 1000000
     ORDER BY visit_count DESC, last_visit_time DESC
     LIMIT 200;
  " 2>/dev/null |
    awk -F'\t' 'NF >= 2 { printf "history\t%s\t%s\t%s\n", $1, $2, $2 }'
}

# Which source the list is showing. Actions that only change data -- filing an
# entry away, editing the file -- have to put the list back the way they found
# it, and reloading a fixed source would dump someone browsing tabs into the
# bookmark list instead.
current_source() {
  if [ -n "$STATE_DIR" ] && [ -s "$STATE_DIR/source" ]; then
    cat "$STATE_DIR/source"
  else
    printf 'bookmarks'
  fi
}

emit_source() {
  local name="$1"
  [ "$name" = current ] && name=$(current_source)
  [ -n "$STATE_DIR" ] && printf '%s' "$name" >"$STATE_DIR/source"
  case "$name" in
    bookmarks) source_bookmarks ;;
    groups)    source_groups ;;
    tabs)      source_tabs ;;
    prs)       source_prs ;;
    issues)    source_issues ;;
    history)   source_history ;;
    *)         printf 'browse: unknown source: %s\n' "$name" >&2; return 1 ;;
  esac
}

# ----------------------------------------------------------------- opening ---

# Without --focus the browser is never activated: the tab is put in front of
# its window and left there for whenever the browser is next looked at.
activate_tab() {
  local wid="$1" idx="$2" raise=""
  [ "$FOCUS" = 1 ] && raise="activate"
  osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "$BROWSER"
  set active tab index of window id $wid to $idx
  set index of window id $wid to 1
  $raise
end tell
APPLESCRIPT
}

activate_tab_target() {
  local rest=${1#tab:}
  activate_tab "${rest%%:*}" "${rest#*:}"
}

# Tabs are addressed by position, so closing one renumbers every tab after it
# in the same window. The reload this prints is therefore not cosmetic: without
# it the next close would land on the wrong tab. It is also why there is no
# multi-select close -- a batch would have to be closed in descending order,
# and 60 tabs closed at once is not something the browser can undo one at a
# time in any useful way.
close_tab() {
  local target="$1" label="${2:-}" rest
  case "$target" in
    tab:*) ;;
    *) set_status "タブの行ではありません"; return 0 ;;
  esac
  rest=${target#tab:}
  if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "$BROWSER" to close tab ${rest#*:} of window id ${rest%%:*}
APPLESCRIPT
  then
    set_status "閉じました: ${label:-$target}"
    printf 'reload(%s --state %s --source tabs)+change-prompt(tab> )\n' "$0" "$STATE_DIR"
  else
    set_status "閉じられませんでした: ${label:-$target}"
  fi
}

launch_url() {
  local prev
  if [ "$FOCUS" = 1 ]; then
    open -a "$BROWSER" "$1"
    return
  fi
  # Two separate problems here.
  #
  # The tab is created through `open` rather than AppleScript because a tab
  # made by script becomes a child of the active one under Brave's tree tabs,
  # while one arriving through the URL handler has no opener and lands at the
  # top level.
  #
  # `open -g` then only solves half of the focus problem: it stops `open` from
  # activating the browser, but the browser raises itself when it handles the
  # URL. So the frontmost application is noted and put back afterwards. If
  # System Events cannot be scripted the page still opens; it just takes the
  # focus with it.
  prev=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null) || prev=""
  open -g -a "$BROWSER" "$1"
  [ -n "$prev" ] || return 0
  osascript >/dev/null 2>&1 <<APPLESCRIPT || true
delay 0.3
tell application "System Events" to set frontmost of process "${prev//\"/}" to true
APPLESCRIPT
}

# Raising the existing tab rather than opening a second one is the whole point:
# picking the same bookmark twice must not grow the tab strip.
open_url() {
  local url="$1" hit
  hit=$(source_tabs | awk -F'\t' -v u="$url" '$4 == u { print $3; exit }')
  if [ -n "$hit" ] && activate_tab_target "$hit"; then
    return 0
  fi
  launch_url "$url"
}

open_target() {
  local target="$1"
  case "$target" in
    tab:*) activate_tab_target "$target" || launch_url "$2" ;;
    "")    return 0 ;;
    *)     open_url "$target" ;;
  esac
}

# --------------------------------------------------------------- bookmarks ---

# A folder row carries no URL, and a browser-internal page cannot be reopened
# from a launcher. Both would otherwise be storable as an entry that can never
# be followed, so the one predicate guards every way in.
bookmarkable_url() {
  case "$1" in
    ""|chrome://*|brave://*|about:*|file://*) return 1 ;;
    *) return 0 ;;
  esac
}

ensure_bookmarks_file() {
  mkdir -p "$CONFIG_DIR"
  [ -f "$BOOKMARKS" ] && return 0
  cat >"$BOOKMARKS" <<'EOF'
# browse bookmarks — one entry per line: <group><TAB><label><TAB><url>
#
# The group is the folder the entry shows up under; leaving it blank files the
# entry as ungrouped. Moving an entry between folders is editing this column.
# Lines starting with # are ignored, and a two-column <label><TAB><url> line is
# read as ungrouped.
EOF
}

bookmark_has_url() {
  normalize_bookmarks | awk -F'\t' -v u="$1" '$3 == u { found = 1 } END { exit !found }'
}

add_bookmark() {
  local url="$1" label="${2:-}" group="${3:-$DEFAULT_GROUP}"
  if ! bookmarkable_url "$url"; then
    set_status "登録できる行ではありません"
    return 0
  fi
  ensure_bookmarks_file
  if bookmark_has_url "$url"; then
    set_status "登録済み: ${label:-$url}"
    return 0
  fi
  printf '%s\t%s\t%s\n' "$group" "${label:-$url}" "$url" >>"$BOOKMARKS"
  set_status "$group に追加: ${label:-$url}"
}

group_names() {
  normalize_bookmarks | awk -F'\t' '$1 != "" && !seen[$1]++ { print $1 }'
}

# Picking the destination is itself an fzf, which is why the binding runs this
# under execute() rather than execute-silent: the nested picker needs the
# terminal. Typing a name that matches nothing creates that folder, so there is
# no separate "new folder" step.
choose_group() {
  local out rc=0
  out=$(group_names | fzf --print-query --prompt='移動先> ' \
    --height=60% --layout=reverse --border \
    --header='既存を選ぶか、新しい名前を入力 / esc で中止') || rc=$?
  case "$rc" in
    # A match was accepted: the query is the first line, the selection second.
    0) printf '%s' "$out" | sed -n '2p' ;;
    # Nothing matched, so the typed query is the new folder name.
    1) printf '%s' "$out" | sed -n '1p' ;;
    *) return 1 ;;
  esac
}

# Works from any source, not just bookmarks: a tab or history row that is not
# saved yet gets added straight into the chosen folder, which makes this the
# one-key "file this away properly" next to ctrl-s's "dump it in inbox".
move_bookmark() {
  local url="$1" label="${2:-}" group
  if ! bookmarkable_url "$url"; then
    set_status "移動できる行ではありません"
    return 0
  fi
  ensure_bookmarks_file
  if ! group=$(choose_group) || [ -z "$group" ]; then
    set_status "移動を中止しました"
    return 0
  fi
  if ! bookmark_has_url "$url"; then
    add_bookmark "$url" "$label" "$group"
    return 0
  fi
  # Rewrites the raw file rather than the normalized stream, because the
  # comment header has to survive.
  awk -F'\t' -v u="$url" -v g="$group" 'BEGIN { OFS = "\t" }
    /^[[:space:]]*#/ { print; next }
    {
      if (NF >= 3)      { grp = $1; label = $2; link = $3 }
      else if (NF == 2) { grp = "";  label = $1; link = $2 }
      else              { print; next }
      if (link == u) grp = g
      print grp, label, link
    }
  ' "$BOOKMARKS" >"$WORKDIR/bookmarks.tsv"
  mv "$WORKDIR/bookmarks.tsv" "$BOOKMARKS"
  set_status "$group へ移動: ${label:-$url}"
}

add_open_tabs() {
  local before after label url
  ensure_bookmarks_file
  before=$(normalize_bookmarks | wc -l | tr -d ' ')
  while IFS=$'\t' read -r _ label _ url; do
    add_bookmark "$url" "$label"
  done < <(source_tabs)
  after=$(normalize_bookmarks | wc -l | tr -d ' ')
  printf 'browse: %d 件を取り込みました (合計 %d 件)\n' "$((after - before))" "$after"
}

# ------------------------------------------------------------------ picker ---

# Called through fzf's transform(), so stdout here is a list of fzf actions.
# Folder rows turn into a reload; anything else is opened on the spot and emits
# nothing, which is what keeps the picker open across a selection.
handle_enter() {
  local target="$1" url="${2:-}" name shown
  case "$target" in
    group:*)
      name=${target#group:}
      printf '%s' "$name" >"$STATE_DIR/group"
      # Parentheses would terminate the change-prompt action early, so they are
      # dropped from the prompt only -- the filter itself keeps the real name.
      shown=$(printf '%s' "$name" | tr -d '()')
      [ -n "$shown" ] || shown="$UNGROUPED_LABEL"
      printf 'reload(%s --state %s --source bookmarks)+change-prompt(%s> )+first\n' \
        "$0" "$STATE_DIR" "$shown"
      ;;
    *)
      if [ -n "$target" ] && [ "$FOCUS" = 1 ]; then
        set_status "開く(前面へ): ${url:-$target}"
      elif [ -n "$target" ]; then
        set_status "開く: ${url:-$target}"
      fi
      # transform() blocks the picker until this returns and opening costs an
      # AppleScript round trip, so it is detached. Nothing downstream of here
      # produces an action for fzf to run, so there is nothing to wait for.
      # The status is set first, before the detached half can outlive the read.
      ( open_target "$target" "$url" >/dev/null 2>&1 & )
      ;;
  esac
}

run_picker() {
  local query="${1:-}" initial="bookmarks"
  STATE_DIR="$WORKDIR/state"
  mkdir -p "$STATE_DIR"
  # An empty bookmark file would open onto a blank list, which reads as if the
  # tool were broken; fall back to the tabs that are open right now.
  if [ -z "$(source_bookmarks)" ]; then
    initial="tabs"
  fi

  local common="$0 --state $STATE_DIR"
  # Every binding has to refresh the header, or the previous result would sit
  # there stale; the suffix is written once and appended rather than repeated.
  local hdr="+transform-header($common --header)"
  local binds=() spec key prompt src
  for spec in ctrl-f:folder:groups ctrl-t:tab:tabs ctrl-g:pr:prs \
              ctrl-y:issue:issues ctrl-r:history:history; do
    IFS=: read -r key prompt src <<<"$spec"
    binds+=(--bind "$key:change-prompt($prompt> )+reload($common --source $src)$hdr")
  done
  binds+=(--bind "enter:transform($common --enter {3} {4})$hdr")
  binds+=(--bind "ctrl-l:transform($common --focus --enter {3} {4})$hdr")
  binds+=(--bind "ctrl-b:execute-silent(rm -f $STATE_DIR/group)+change-prompt(bookmark> )+reload($common --source bookmarks)$hdr")
  binds+=(--bind "ctrl-s:execute-silent($common --add {4} {2})$hdr")
  binds+=(--bind "ctrl-o:execute($common --move {4} {2})+reload($common --source current)$hdr")
  binds+=(--bind "ctrl-x:transform($common --close {3} {2})$hdr")
  binds+=(--bind "ctrl-e:execute($common --edit)+reload($common --source current)$hdr")

  emit_source "$initial" | fzf \
    --delimiter="$TAB" --with-nth=1,2 --tabstop=12 \
    --height=80% --layout=reverse --border \
    --prompt='browse> ' \
    --query="$query" \
    --preview='printf %s {4}' --preview-window=down,2,wrap \
    --header="$(picker_header)" \
    "${binds[@]}" || return 0
}

usage() {
  cat <<EOF
usage: browse [query]
       browse --source {bookmarks|groups|tabs|prs|issues|history|current}
       browse --open <url>
       browse --add <url> [label] [group]
       browse --move <url> [label]
       browse --close <tab target> [label]
       browse --add-open-tabs
       browse --edit

Opens the fzf picker, which stays open across a selection -- leave it with esc.

  enter   open the row without leaving the terminal, or drill into the folder
  ctrl-l  open it and bring the browser forward
  ctrl-f  list folders          ctrl-b  back to every bookmark
  ctrl-t  open tabs             ctrl-r  history
  ctrl-g  pull requests         ctrl-y  issues
  ctrl-s  bookmark this row     ctrl-o  file it into a folder
  ctrl-x  close that browser tab  ctrl-e  edit the bookmark file

Selecting a row raises the tab that already shows that URL, and only opens a
new one when there is none. The browser is not activated unless you ask for it
with ctrl-l, so a pass through the list never takes the focus away.

Bookmarks: $BOOKMARKS
Browser:   $BROWSER (override with BROWSE_BROWSER)
EOF
}

main() {
  while :; do
    case "${1:-}" in
      --state) STATE_DIR="${2:-}"; shift 2 ;;
      --focus) FOCUS=1; shift ;;
      *) break ;;
    esac
  done
  case "${1:-}" in
    --source)        shift; emit_source "${1:-bookmarks}" ;;
    --header)        picker_header ;;
    --enter)         shift; handle_enter "${1:-}" "${2:-}" ;;
    --move)          shift; move_bookmark "${1:-}" "${2:-}" ;;
    --close)         shift; close_tab "${1:-}" "${2:-}" ;;
    --open)          shift; open_url "${1:-}" ;;
    --add)           shift; add_bookmark "${1:-}" "${2:-}" "${3:-}" ;;
    --add-open-tabs) add_open_tabs ;;
    --edit)
      ensure_bookmarks_file
      "${EDITOR:-vi}" "$BOOKMARKS"
      set_status "編集を反映しました ($(normalize_bookmarks | wc -l | tr -d ' ') 件)"
      ;;
    -h|--help)       usage ;;
    -*)              usage >&2; return 2 ;;
    *)               run_picker "${1:-}" ;;
  esac
}

main "$@"
