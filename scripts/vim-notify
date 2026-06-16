#!/usr/bin/env bash
# Notify the parent Neovim instance when a command finishes.
# Usage: long-command && vim-notify 'Done!'
#
# Must be run inside a Neovim terminal buffer ($NVIM set automatically).
# The notification includes the PID of the calling shell.

set -euo pipefail

MESSAGE="${1:-Done}"
PID="${PPID}"
FULL="${MESSAGE} (PID: ${PID})"

if [[ -z "${NVIM:-}" ]]; then
    exit 0
fi

# Escape single quotes for a VimL single-quoted string: ' → ''
escaped=$(printf '%s' "$FULL" | sed "s/'/''/g")

# Use --remote-send (nvim_input) NOT --remote-expr (nvim_eval).
# nvim_eval requires Neovim to run its event loop and return a result —
# calling it from inside a terminal buffer deadlocks because Neovim is
# busy waiting on the terminal.  nvim_input just queues keystrokes and
# returns immediately; Neovim processes them once the terminal yields.
nvim --server "${NVIM}" \
    --remote-send "<Cmd>lua vim.notify('${escaped}', vim.log.levels.INFO, {title='shell'})<CR>" \
    2>/dev/null || true
