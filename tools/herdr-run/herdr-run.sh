# herdr-run — a command palette over the herdr actions that
# shared/programs/herdr.nix otherwise only exposes as prefix+alt+... chords:
# agent-open (resuming and starting), focus_agent, and the herdr-mirror
# plugin_action bindings.
# alt+... chords depend on the terminal forwarding the alt modifier, which
# some (Termux and other droid-profile terminals) never do, so those actions
# have no way to fire there at all. Every row below reaches the same
# functionality through the herdr CLI's own socket API, which needs no
# keybinding to invoke.
#
# Every row, static or dynamic, is a <id>\t<title>\t<command> triple; the
# picker and every dispatcher below only ever look at those three fields, by
# position, never by what kind of row it is. That is what keeps this
# extensible: a new static action is one more line in static_rows(), and a
# new dynamic source (worktrees, workspaces, ...) is one more `*_rows`
# function with the same three-column shape, appended to all_rows(). Neither
# addition touches the picker or the dispatch logic.
#
# focus_agent jumps to a sidebar row by index; `herdr agent focus` only takes
# a pane id or agent name, so the agent rows below carry pane ids instead of
# reproducing the row numbering.

usage() {
  cat <<'EOF'
usage: herdr-run [resume|focus|mirror] [target-or-action-id]

With no arguments, opens an fzf palette over every action below — resuming a
session, focusing any live agent, every herdr-mirror plugin action, and
moving the current tab to another workspace ("Move tab to:" rows, palette
only).
`focus`/`mirror` with no id open the same palette pre-filtered to that
category; give an explicit id to skip the palette and run it directly.

  herdr-run                       full palette                  (prefix+f)
  herdr-run resume                 open the agent-open picker    (prefix+alt+r)
  herdr-run new                    start a new agent session     (prefix+alt+a)
  herdr-run focus [pane-id]        focus an agent, or filter to  (prefix+alt+1..9)
                                    "Focus:" rows with no id
  herdr-run mirror [action-id]     invoke a mirror action, or    (prefix+shift+m/s/b,
                                    filter to "Mirror:" rows       prefix+alt+d/n/c/v/minus,
                                    with no id                     prefix+m popup)
EOF
}

# id, title, command — one line per static action. Add a new one here; the
# palette and every other row source pick it up automatically.
static_rows() {
  printf '%s\t%s\t%s\n' \
    resume 'Resume an agent session' 'agent-open' \
    new 'Start a new agent session' 'agent-open --new' \
    shelf 'Open the session shelf' 'agent-open --shelf' \
    shelve 'Keep this session on the shelf' 'agent-open --shelve' \
    toggle-term 'Toggle terminal workspace' "$HOME/dotfiles/scripts/herdr-toggle-terminal.sh"
}

agent_rows() {
  herdr agent list | jq -r '
    .result.agents[]?
    | (.title // .terminal_title_stripped // .terminal_title // "(untitled)") as $title
    | [.pane_id, "Focus: " + $title, "herdr agent focus " + (.pane_id | @sh)]
    | @tsv
  '
}

mirror_rows() {
  # .title already reads "Mirror: <action>" (see `herdr plugin action list`),
  # so this doesn't add its own prefix the way agent_rows does for "Focus: ".
  herdr plugin action list --plugin mirror | jq -r '
    .result.actions[]?
    | [.action_id, .title, "herdr plugin action invoke " + (.action_id | @sh) + " --plugin mirror"]
    | @tsv
  '
}

# herdr has no tab-to-workspace move, only `pane move`, so the tab is carried
# over by moving its pane into a new tab there. A split tab would come out as
# separate tabs, so move_tab refuses it rather than reassembling the layout.
# The "term:" workspaces belong to herdr-toggle-terminal.sh and are skipped.
move_rows() {
  local pane="${HERDR_ACTIVE_PANE_ID:-}" ws
  [ -n "$pane" ] || return 0
  ws=$(herdr pane get "$pane" | jq -r '.result.pane.workspace_id')
  herdr workspace list | jq -r --arg ws "$ws" --arg pane "$pane" '
    .result.workspaces[]
    | select(.workspace_id != $ws and (.label | startswith("term:") | not))
    | [.workspace_id, "Move tab to: " + .label, "move_tab " + ($pane | @sh) + " " + (.workspace_id | @sh)]
    | @tsv
  '
}

move_tab() {
  local pane="$1" ws="$2" tab info label count
  tab=$(herdr pane get "$pane" | jq -r '.result.pane.tab_id')
  info=$(herdr tab get "$tab")
  label=$(jq -r '.result.tab.label' <<<"$info")
  count=$(jq -r '.result.tab.pane_count' <<<"$info")
  if [ "$count" -gt 1 ]; then
    printf 'tab "%s" has %s panes; only single-pane tabs can be moved\n' "$label" "$count" >&2
    read -rsn1 _ </dev/tty || true
    return 1
  fi
  herdr pane move "$pane" --new-tab --workspace "$ws" --label "$label" --no-focus >/dev/null
}

all_rows() {
  static_rows
  agent_rows
  mirror_rows
  move_rows
}

# $1, if given, seeds the fzf query so callers can open the palette
# pre-filtered (e.g. to just the "Mirror:" rows) without a separate code path.
palette() {
  local query="${1:-}" sel cmd
  sel=$(all_rows | fzf --delimiter=$'\t' --with-nth=2 --prompt='herdr> ' --query="$query") || return 0
  [ -n "$sel" ] || return 0
  cmd=$(cut -f3 <<<"$sel")
  eval "$cmd"
}

cmd_resume() {
  exec agent-open
}

cmd_new() {
  local agent="${1:-}"
  if [ -z "$agent" ]; then
    exec agent-open --new
  fi
  exec agent-open --new "$agent"
}

cmd_focus() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    palette 'Focus: '
    return 0
  fi
  herdr agent focus "$target"
}

cmd_mirror() {
  local action="${1:-}"
  if [ -z "$action" ]; then
    palette 'Mirror: '
    return 0
  fi
  herdr plugin action invoke "$action" --plugin mirror
}

main() {
  case "${1:-}" in
    resume) shift; cmd_resume "$@" ;;
    new)    shift; cmd_new "$@" ;;
    focus)  shift; cmd_focus "$@" ;;
    mirror) shift; cmd_mirror "$@" ;;
    "")     palette "" ;;
    -h|--help) usage ;;
    *) usage >&2; return 2 ;;
  esac
}

main "$@"
