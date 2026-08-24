#!/usr/bin/env bash
# Clipboard-free counterpart to herdr's built-in copy mode, run from a popup
# keybinding. Herdr's own copy mode can only yank into the system clipboard,
# so this dumps the pane's scrollback into nvim instead and lets nvim's
# registers do the work; scripts/herdr-copy.lua writes the yank to the
# register file that scripts/herdr-paste.py reads back.
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

scrollback=$(mktemp "${TMPDIR:-/tmp}/herdr-copy.XXXXXX")
trap 'rm -f "$scrollback"' EXIT

"$herdr_bin" pane read "$HERDR_ACTIVE_PANE_ID" --source recent --lines "$lines" >"$scrollback"

HERDR_PASTE_REGISTER=$register \
  nvim --noplugin -u "$(dirname "${BASH_SOURCE[0]}")/herdr-copy.lua" -- "$scrollback"
