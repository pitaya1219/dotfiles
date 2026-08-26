#!/usr/bin/env bash
# Workspace-level counterpart to nvim's <A-j> (ToggleTerm): jumps between the
# current workspace and a dedicated shell workspace paired with it. Neither
# side is ever closed, only defocused, so the shell's running process and
# scrollback survive the round trip the way a hidden ToggleTerm buffer does.
# A pane-local equivalent (shrink/zoom a split) was ruled out: herdr enforces
# a 10% minimum split ratio, so a "closed" pane would always leave a visible
# sliver behind rather than disappearing.
#
# The pairing needs no separate state store: the shell workspace's own label
# carries it (`term:<source_workspace_id>`), so either direction is a single
# lookup and can't drift out of sync with reality.
#
# HERDR_ACTIVE_PANE_ID and HERDR_BIN_PATH are exported by herdr to every
# custom-command keybinding; the pane id is captured before this runs, so it
# still names the pane the user was looking at.

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
label_prefix="term:"

pane_id=${HERDR_ACTIVE_PANE_ID:-}
if [[ -z $pane_id ]]; then
  echo "herdr-toggle-terminal: no active pane" >&2
  exit 1
fi

pane=$("$herdr_bin" pane get "$pane_id")
current_ws=$(jq -r '.result.pane.workspace_id' <<<"$pane")
cwd=$(jq -r '.result.pane.cwd' <<<"$pane")
current_label=$("$herdr_bin" workspace get "$current_ws" | jq -r '.result.workspace.label // empty')

if [[ $current_label == "$label_prefix"* ]]; then
  # Already in a shell workspace: jump back to the one it shadows. If that
  # workspace was closed in the meantime this just fails silently, matching
  # herdr's own behavior when a goto target no longer exists.
  "$herdr_bin" workspace focus "${current_label#"$label_prefix"}" >/dev/null
  exit 0
fi

shadow_label="$label_prefix$current_ws"
shadow_id=$("$herdr_bin" workspace list | jq -r --arg label "$shadow_label" \
  '.result.workspaces[] | select(.label == $label) | .workspace_id' | head -n1)

if [[ -n $shadow_id ]]; then
  "$herdr_bin" workspace focus "$shadow_id" >/dev/null
else
  "$herdr_bin" workspace create --cwd "$cwd" --label "$shadow_label" --focus >/dev/null
fi
