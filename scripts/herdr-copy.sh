#!/usr/bin/env bash
# Clipboard-free counterpart to herdr's built-in copy mode, run from a popup
# keybinding. Herdr's own copy mode can only yank into the system clipboard,
# so this dumps the pane's history into nvim instead and lets nvim's
# registers do the work; scripts/herdr-copy.lua writes the yank to the
# register file that scripts/herdr-paste.py reads back.
#
# For an agent pane the history does not come from the scrollback. Claude Code
# and Vibe both draw on the alternate screen, which keeps every line inside the
# process and leaves herdr with nothing to scroll, so scripts/agent-transcript.py
# reads the agent's own session log instead. It exits non-zero for anything it
# cannot resolve — a shell pane, opencode, an agent whose session id has not
# been reported yet — and then the scrollback is still the best available
# source.
#
# HERDR_ACTIVE_PANE_ID, HERDR_BIN_PATH and HERDR_SOCKET_PATH are exported by
# herdr to every custom-command keybinding. The pane id is captured before the
# popup opens, so it still names the pane the user was looking at.

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
lines=${HERDR_COPY_LINES:-10000}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
register=${HERDR_PASTE_REGISTER:-$state_home/herdr/paste-register}

if [[ -z ${HERDR_ACTIVE_PANE_ID:-} ]]; then
  echo "herdr-copy: no active pane" >&2
  exit 1
fi

mkdir -p "$(dirname "$register")"

here=$(dirname "${BASH_SOURCE[0]}")

buffer=$(mktemp "${TMPDIR:-/tmp}/herdr-copy.XXXXXX")
trap 'rm -f "$buffer"' EXIT

if ! "$here/agent-transcript.py" --pane "$HERDR_ACTIVE_PANE_ID" >"$buffer" 2>/dev/null; then
  "$herdr_bin" pane read "$HERDR_ACTIVE_PANE_ID" --source recent --lines "$lines" >"$buffer"
fi

HERDR_PASTE_REGISTER=$register \
  nvim --noplugin -u "$here/herdr-copy.lua" -- "$buffer"
