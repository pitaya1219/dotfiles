# herdr-run — typed entry points for the herdr actions that shared/programs/herdr.nix
# only exposes as prefix+alt+... chords: agent-resume, focus_agent, and the
# herdr-mirror plugin_action bindings. alt+... chords depend on the terminal
# forwarding the alt modifier, which some (Termux and other droid-profile
# terminals) never do, so those actions have no way to fire there at all. Every
# subcommand below reaches the same functionality through the herdr CLI's own
# socket API, which needs no keybinding to invoke.
#
# focus_agent jumps to a sidebar row by index; `herdr agent focus` only takes a
# pane id or agent name, so `herdr-run focus` lists live agents by pane id
# instead of reproducing the row numbering.

usage() {
  cat <<'EOF'
usage: herdr-run resume
       herdr-run focus [pane-id-or-agent-name]
       herdr-run mirror [action-id]

  resume  open the agent-resume picker            (prefix+alt+r)
  focus   focus a running agent; lists candidates  (prefix+alt+1..9)
          when no argument is given
  mirror  invoke a herdr-mirror plugin action;      (prefix+shift+m/s/b,
          lists available actions when no           prefix+alt+d/n/c/v/minus)
          argument is given
EOF
}

cmd_resume() {
  exec agent-resume
}

cmd_focus() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    herdr agent list | jq -r '
      .result.agents[]?
      | "\(.pane_id)  \(.agent_status)  \(.title // .terminal_title_stripped // .terminal_title // "(untitled)")"
    '
    return 0
  fi
  herdr agent focus "$target"
}

cmd_mirror() {
  local action="${1:-}"
  if [ -z "$action" ]; then
    herdr plugin action list --plugin mirror | jq -r '
      .result.actions[]? | "\(.action_id)  \(.title)"
    '
    return 0
  fi
  herdr plugin action invoke "$action" --plugin mirror
}

main() {
  case "${1:-}" in
    resume) shift; cmd_resume "$@" ;;
    focus)  shift; cmd_focus "$@" ;;
    mirror) shift; cmd_mirror "$@" ;;
    -h|--help|"") usage ;;
    *) usage >&2; return 2 ;;
  esac
}

main "$@"
