#!/usr/bin/env bash
# Workspace-level counterpart to nvim's <A-j> (ToggleTerm): jumps between the
# current tab and a dedicated shell tab paired with it. Neither side is ever
# closed, only defocused, so the shell's running process and scrollback
# survive the round trip the way a hidden ToggleTerm buffer does. A
# pane-local equivalent (shrink/zoom a split) was ruled out: herdr enforces a
# 10% minimum split ratio, so a "closed" pane would always leave a visible
# sliver behind rather than disappearing.
#
# HERDR_ACTIVE_PANE_ID and HERDR_BIN_PATH are exported by herdr to every
# custom-command keybinding; the pane id is captured before this runs, so it
# still names the pane the user was looking at.
#
# Local and remote (herdr-mirror) tabs both get a shell tab paired with them
# via pair_state, keyed by tab id, but they differ in *where* that shell tab
# lives:
#
# Local: in a dedicated shell workspace, one per source workspace, found via
# its own label (`term:<source_workspace_id>`) rather than pair_state, so
# that lookup needs no separate state at all.
#
# Remote (mirror): in the *same* mirrored workspace as the source tab, not a
# separate one. A first version mirrored the local design exactly — a
# dedicated shell workspace, opened via the mirror plugin's
# remote-new-workspace action — but every remote-new-workspace call risks
# herdr-mirror's own daemon (src/daemon.rs, nikok6/herdr-mirror) reconciling
# it twice: its poll loop and its workspace-creation-event handler can both
# run a "converge" pass concurrently with no id-based dedup between them, so
# one call occasionally mirrors back as two local proxies instead of one,
# confirmed live via `herdr plugin log list` (two separate "workspace.created"
# intercept events for one remote-new-workspace call) — and the daemon can
# tombstone either one *later*, well outside a single script run, so even a
# workspace that looked fine right after creation could vanish out from
# under the next toggle. remote-new-tab has the same daemon underneath it,
# but staying inside the one mirrored workspace the source tab already lives
# in — rather than opening a fresh workspace on every first toggle — means
# never calling remote-new-workspace at all, so this only has the tab-level
# instance of the race to contend with, not the workspace-level one, and
# tabs are labeled "sh: <name>" to stay visually distinct from the tabs
# actually being worked in, sharing the same workspace as they now do.
#
# herdr-mirror workspaces are labeled "<prefix>: <name>", where <prefix> is
# whatever hosts.toml sets per host (not a fixed string), so detecting one
# means reading the same file rather than guessing a convention.

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
label_prefix="term:"
shell_tab_prefix="sh: "
mirror_hosts_toml="$HOME/.config/herdr-mirror/hosts.toml"
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
pair_state="$state_home/herdr/toggle-terminal-pairs.json"
remote_timeout_s=${HERDR_TOGGLE_TERMINAL_REMOTE_TIMEOUT_S:-30}
remote_dedupe_settle_s=${HERDR_TOGGLE_TERMINAL_REMOTE_DEDUPE_SETTLE_S:-10}

is_mirror_workspace() {
  local label=$1
  [[ -f $mirror_hosts_toml ]] || return 1
  local prefix
  while IFS= read -r prefix; do
    [[ -n $prefix && $label == "$prefix: "* ]] && return 0
  done < <(sed -nE 's/^[[:space:]]*prefix[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$mirror_hosts_toml")
  return 1
}

tab_exists() {
  "$herdr_bin" tab get "$1" >/dev/null 2>&1
}

# Generic id -> id lookup, used for both the remote and local tab pairing.
paired_id() {
  [[ -f $pair_state ]] || return 0
  jq -r --arg id "$1" '.pairs[$id] // empty' "$pair_state"
}

# True if $1 is the shadow half of a pair recorded by record_pair (its
# second argument at the time). The local case never needs this — its
# workspace label already says which side it's on — but a remote shell tab
# lives in the same workspace as its source and has no marking of its own
# beyond the "sh: " label, so knowing which side we're on comes from here.
is_shadow_id() {
  [[ -f $pair_state ]] || return 1
  jq -e --arg id "$1" '(.shadows // []) | index($id) != null' "$pair_state" >/dev/null 2>&1
}

# Both directions are recorded so a lookup from either side of the pair is a
# single flat read. $2 (the side just created) is additionally tracked as a
# shadow for is_shadow_id.
record_pair() {
  mkdir -p "$(dirname "$pair_state")"
  local existing="{}"
  [[ -f $pair_state ]] && existing=$(cat "$pair_state")
  local tmp
  tmp=$(mktemp "$pair_state.XXXXXX")
  jq --arg a "$1" --arg b "$2" \
    '.pairs = ((.pairs // {}) + {($a): $b, ($b): $a})
     | .shadows = (((.shadows // []) + [$b]) | unique)' \
    <<<"$existing" >"$tmp"
  mv "$tmp" "$pair_state"
}

# An already-mirrored, unclaimed "sh: " tab in $1, left behind by a prior
# remote-new-tab call that either raced into a duplicate (see the file
# header) or whose paired half got tombstoned later. Recreating from scratch
# every time that happens would hit the same race again on every toggle, so
# this is tried before calling remote-new-tab.
find_orphaned_shell_tab() {
  local ws=$1
  local candidate
  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    is_shadow_id "$candidate" && continue
    echo "$candidate"
    return 0
  done < <("$herdr_bin" tab list --workspace "$ws" | jq -r \
    --arg p "$shell_tab_prefix" '.result.tabs[] | select(.label // "" | startswith($p)) | .tab_id')
  return 0
}

# remote-new-tab runs async (ssh + mirror reconciliation), so the result is
# a log to poll rather than a tab id in the invoke response. The log
# reaching "succeeded" only means the remote-side command exited; the new
# tab still has to show up here via the mirror daemon's own,
# separately-timed reconciliation pass, confirmed live to lag behind by a
# second or two. So poll tab list itself rather than trusting a single diff
# taken right when the log succeeds, and if more than one new tab shows up
# at once (the daemon race from the file header), wait a bit longer for the
# count to settle back to one — state.rs tracks a tombstoned flag, implying
# the daemon does eventually notice and clean the extra one up — before
# just pairing with whichever sorts first.
open_remote_tab() {
  local source_tab=$1 ws=$2
  local before after log_id status tries=0 settle_tries=0 new_tabs=""

  before=$("$herdr_bin" tab list --workspace "$ws" | jq -r '.result.tabs[].tab_id' | sort)

  log_id=$("$herdr_bin" plugin action invoke remote-new-tab --plugin mirror |
    jq -r '.result.log.log_id')
  if [[ -z $log_id ]]; then
    echo "herdr-toggle-terminal: remote-new-tab did not return a log id" >&2
    return 1
  fi

  while [[ -z $new_tabs && $tries -lt $remote_timeout_s ]]; do
    sleep 1
    tries=$((tries + 1))
    status=$("$herdr_bin" plugin log list --plugin mirror --limit 50 |
      jq -r --arg id "$log_id" '.result.logs[] | select(.log_id == $id) | .status')
    if [[ $status == "failed" ]]; then
      echo "herdr-toggle-terminal: remote-new-tab failed" >&2
      return 1
    fi
    after=$("$herdr_bin" tab list --workspace "$ws" | jq -r '.result.tabs[].tab_id' | sort)
    new_tabs=$(comm -13 <(echo "$before") <(echo "$after"))
  done
  if [[ -z $new_tabs ]]; then
    echo "herdr-toggle-terminal: could not identify the new remote tab within ${remote_timeout_s}s" >&2
    return 1
  fi

  while [[ $(wc -l <<<"$new_tabs") -gt 1 && $settle_tries -lt $remote_dedupe_settle_s ]]; do
    sleep 1
    settle_tries=$((settle_tries + 1))
    after=$("$herdr_bin" tab list --workspace "$ws" | jq -r '.result.tabs[].tab_id' | sort)
    new_tabs=$(comm -13 <(echo "$before") <(echo "$after"))
  done
  if [[ $(wc -l <<<"$new_tabs") -gt 1 ]]; then
    echo "herdr-toggle-terminal: remote-new-tab produced $(wc -l <<<"$new_tabs") local tabs for one call (a known herdr-mirror daemon race) and they didn't settle back to one within ${remote_dedupe_settle_s}s; pairing with $(head -n1 <<<"$new_tabs"), leaving stray $(tail -n +2 <<<"$new_tabs" | tr '\n' ' ')for manual cleanup" >&2
  fi

  local new_tab
  new_tab=$(head -n1 <<<"$new_tabs")
  record_pair "$source_tab" "$new_tab"
  echo "$new_tab"
}

pane_id=${HERDR_ACTIVE_PANE_ID:-}
if [[ -z $pane_id ]]; then
  echo "herdr-toggle-terminal: no active pane" >&2
  exit 1
fi

pane=$("$herdr_bin" pane get "$pane_id")
current_ws=$(jq -r '.result.pane.workspace_id' <<<"$pane")
cwd=$(jq -r '.result.pane.cwd' <<<"$pane")
current_label=$("$herdr_bin" workspace get "$current_ws" | jq -r '.result.workspace.label // empty')

current_tab=$(jq -r '.result.pane.tab_id' <<<"$pane")
current_tab_label=$("$herdr_bin" tab get "$current_tab" | jq -r '.result.tab.label // empty')

if is_mirror_workspace "$current_label"; then
  if is_shadow_id "$current_tab"; then
    # Already in one of our own shell tabs: jump back to the specific
    # source tab it's paired with. If that pairing is gone (a stray tab
    # created some other way, or its source was closed) this is just a
    # no-op, matching herdr's own behavior when a goto target no longer
    # exists.
    paired_tab=$(paired_id "$current_tab")
    if [[ -n $paired_tab ]] && tab_exists "$paired_tab"; then
      "$herdr_bin" tab focus "$paired_tab" >/dev/null
    fi
    exit 0
  fi

  shell_label="$shell_tab_prefix${current_tab_label:-$current_tab}"
  paired_tab=$(paired_id "$current_tab")
  if [[ -n $paired_tab ]] && tab_exists "$paired_tab"; then
    shadow_tab=$paired_tab
  else
    orphan=$(find_orphaned_shell_tab "$current_ws")
    if [[ -n $orphan ]]; then
      record_pair "$current_tab" "$orphan"
      shadow_tab=$orphan
    else
      shadow_tab=$(open_remote_tab "$current_tab" "$current_ws")
    fi
  fi

  "$herdr_bin" tab rename "$shadow_tab" "$shell_label" >/dev/null
  "$herdr_bin" tab focus "$shadow_tab" >/dev/null
  exit 0
fi

if [[ $current_label == "$label_prefix"* ]]; then
  # Already in a shell tab: jump back to the specific source tab it's paired
  # with. If that tab (or its pairing) is gone, fall back to the workspace
  # this shadow shadows, landing on whatever tab was last active there —
  # matching herdr's own behavior when a goto target no longer exists.
  paired_tab=$(paired_id "$current_tab")
  if [[ -n $paired_tab ]] && tab_exists "$paired_tab"; then
    "$herdr_bin" tab focus "$paired_tab" >/dev/null
  else
    "$herdr_bin" workspace focus "${current_label#"$label_prefix"}" >/dev/null
  fi
  exit 0
fi

shadow_label="$label_prefix$current_ws"
shadow_ws=$("$herdr_bin" workspace list | jq -r --arg label "$shadow_label" \
  '.result.workspaces[] | select(.label == $label) | .workspace_id' | head -n1)

if [[ -z $shadow_ws ]]; then
  # First toggle from this workspace: reuse the new workspace's own root tab
  # as the shell tab for the current source tab, rather than leaving it as
  # unpaired clutter alongside a second, separately created tab.
  shadow_tab=$("$herdr_bin" workspace create --cwd "$cwd" --label "$shadow_label" --no-focus |
    jq -r '.result.tab.tab_id')
  record_pair "$current_tab" "$shadow_tab"
else
  paired_tab=$(paired_id "$current_tab")
  if [[ -n $paired_tab ]] && tab_exists "$paired_tab"; then
    shadow_tab=$paired_tab
  else
    shadow_tab=$("$herdr_bin" tab create --workspace "$shadow_ws" --cwd "$cwd" --no-focus |
      jq -r '.result.tab.tab_id')
    record_pair "$current_tab" "$shadow_tab"
  fi
fi

[[ -n $current_tab_label ]] && "$herdr_bin" tab rename "$shadow_tab" "$current_tab_label" >/dev/null
"$herdr_bin" tab focus "$shadow_tab" >/dev/null
