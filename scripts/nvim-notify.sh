#!/usr/bin/env bash
# Send vim.notify() to nvim instances.
#
# Discovers targets in two ways:
#   1. $NVIM env var — set automatically when running inside a nvim terminal buffer
#   2. ~/.local/share/nvim/servers — registry written by 94_server_registry.lua
#
# Usage: nvim-notify.sh --message TEXT [--title TEXT] [--level LEVEL] [--skip-registry]
#   --message TEXT      Notification body (required)
#   --title TEXT        Prefix shown as "[TITLE] message"
#   --level LEVEL       vim.log.levels name: INFO, WARN, ERROR (default: WARN)
#   --skip-registry     Only use $NVIM; do not fall back to the server registry

MESSAGE=""
TITLE=""
LEVEL="WARN"
SKIP_REGISTRY=0
SERVER_LIST="$HOME/.local/share/nvim/servers"

while [[ $# -gt 0 ]]; do
  case $1 in
    --message)       MESSAGE="$2"; shift 2 ;;
    --title)         TITLE="$2"; shift 2 ;;
    --level)         LEVEL="$2"; shift 2 ;;
    --skip-registry) SKIP_REGISTRY=1; shift ;;
    *) shift ;;
  esac
done

[ -z "$MESSAGE" ] && exit 0

DISPLAY="${TITLE:+[${TITLE}] }${MESSAGE}"

send_to_nvim() {
  local server="$1"
  [ -z "$server" ] && return
  [ -S "$server" ] || return

  # Escape single quotes for VimL single-quoted string: ' -> ''
  local escaped
  escaped=$(printf '%s' "$DISPLAY" | sed "s/'/''/g")

  # execute() runs an ex command without requiring normal mode.
  # vim.schedule() ensures the notification fires on the main loop safely.
  timeout 2 nvim --server "$server" \
    --remote-expr "execute('lua vim.schedule(function() vim.notify(''${escaped}'', vim.log.levels.${LEVEL}) end)')" \
    2>/dev/null || true
}

# Notify the parent nvim when running inside a nvim terminal buffer
if [ -n "${NVIM:-}" ]; then
  send_to_nvim "$NVIM"
fi

# Notify other known nvim instances from the server registry (unless skipped)
if [ "$SKIP_REGISTRY" -eq 0 ] && [ -f "$SERVER_LIST" ]; then
  while IFS= read -r server; do
    [ -z "$server" ] && continue
    [ "$server" = "${NVIM:-}" ] && continue
    send_to_nvim "$server"
  done < "$SERVER_LIST"
fi
