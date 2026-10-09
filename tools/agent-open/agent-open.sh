# agent-open — opens a coding agent as a herdr tab in the current workspace,
# either fresh (`--new <agent>`) or by resuming a past session picked out of
# fzf, in which case the tab starts in the directory that session ran in.
#
# Sessions on the hosts herdr-mirror folds into this sidebar are listed next to
# the local ones, and resuming one opens its tab on that host rather than here.
# See the remote section for why the host list is taken from the mirror's
# config and not one of its own.
#
# A resumed tab is labeled with the session's title, cut to the width
# herdr-tab-name asks agents to keep to; `--new`, which has no title yet, and a
# session without one get the target directory's git branch instead. Either is
# a placeholder as much as a label: the agent is expected to replace it with a
# short task name through herdr-tab-name (see shared/programs/herdr.nix), and
# the placeholder is what stays visible until it does — or forever, if it does
# not.
#
# Every source prints the same seven tab-separated fields, which is what lets a
# single launcher handle any row the picker returns:
#
#   1 display  the preformatted list line: agent, last activity, project, title
#   2 agent    claude | vibe — also the binary that gets resumed
#   3 id       resume argument for that agent
#   4 cwd      working directory the session ran in
#   5 log      transcript path, read by the preview
#   6 host     herdr-mirror host the session lives on, empty when it is local
#   7 title    the session's title on one line, empty on a host whose
#              agent-open predates this field
#
# Only field 1 is shown (--with-nth); the rest stay addressable as {2}..{6} in
# --preview, which sees the untransformed line.
#
# Rows are streamed to fzf in the order they are produced — local first, then
# one group per host — and never held back to be merged into a single
# timeline. Scanning this machine alone takes tens of seconds (one `jq` over
# every transcript, and this is where that shows), so anything that has to see
# the last row before it can emit the first leaves the picker empty for that
# whole stretch. Grouped rows that arrive as they are found beat sorted rows
# that arrive together.
#
# Sources are switched inside fzf via reload(), which re-enters this script
# with `--source <name>`; that subcommand is also usable on its own.

LIMIT="${AGENT_OPEN_LIMIT:-80}"
TAB=$'\t'

# Set by --host, and read by row() rather than passed to it: it labels every
# row a run produces, and threading it through both sources and every call
# site would say the same thing eight times over. A remote listing is a whole
# process invoked with the flag, so the value never changes mid-run.
HOST_LABEL=""

# What `--new` offers, in the order the picker lists them, which is also the
# order of how often they get picked. Only claude and vibe keep the session
# logs the resume half reads, so opencode appears here and nowhere else.
NEW_AGENTS=(claude vibe opencode)

# A popup closes the moment its command exits, so an error written on the way
# out is never seen. Hold the window open until a key is pressed whenever there
# is a terminal to hold.
die() {
  printf 'agent-open: %s\n' "$1" >&2
  if [ -t 0 ]; then
    printf '\nPress any key to close.\n' >&2
    read -r -n 1 -s || true
  fi
  exit 1
}

# Reading a file's mtime and formatting it are two separate BSD/GNU splits, and
# a single machine can serve one of each depending on what is ahead on PATH, so
# neither flavour may be inferred from the other. Both probes below test for GNU
# and fall back to BSD, which has no -c and no -d at all: an affirmative GNU
# test cannot be fooled the way `date -r 0` can be by a file named 0.
if stat -c %Y . >/dev/null 2>&1; then
  epoch_of() { stat -c %Y "$1"; }
else
  epoch_of() { stat -f %m "$1"; }
fi

if date -d @0 '+%Y' >/dev/null 2>&1; then
  format_epoch() { date -d "@$1" '+%Y-%m-%d %H:%M'; }
else
  format_epoch() { date -r "$1" '+%Y-%m-%d %H:%M'; }
fi

mtime_of() { format_epoch "$(epoch_of "$1")"; }

# Bash slices by character under a UTF-8 locale, so a Japanese prompt is cut at
# a character boundary rather than mid-sequence the way cut -c would.
one_line() {
  local text
  text=$(printf '%s' "$1" | tr '\n\t' '  ' | tr -s ' ')
  printf '%s' "${text:0:100}"
}

# Field 1 is preformatted rather than left to --with-nth: fzf renders the
# remaining tabs at 8-column stops, which no combination of field widths lines
# up reliably.
#
# Every local session shares a handful of working directories, so the project
# column alone rarely tells two rows apart; on a listing spanning hosts the
# host is the part that does, and it goes in front of the project for that
# reason.
# The one place the row schema is spelled out: four display columns, then the
# six fields behind them. Both callers below assemble arguments for it rather
# than carrying a copy of the format, so the shape has a single definition to
# change.
emit_row() {
  printf '%-6s  %-16s  %-24s  %s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

row() {
  local agent="$1" when="$2" project="$3" title="$4" id="$5" cwd="$6" log="$7"
  local place="$project" line
  [ -z "$HOST_LABEL" ] || place="$HOST_LABEL:$project"
  line=$(one_line "$title")
  emit_row "$agent" "$when" "${place:0:24}" "$line" \
    "$agent" "$id" "$cwd" "$log" "$HOST_LABEL" "$line"
}

# A host that cannot be reached gets a row of its own rather than dropping out
# of the listing: a host that is silently absent looks exactly like a host with
# no sessions on it, and not being able to tell those apart is the whole reason
# this picker grew a remote half. It stands where that host's sessions would
# have been, and carries no agent, which is how the launcher and the preview
# tell it apart from a session.
status_row() {
  local host="$1" note="$2"
  emit_row '!' '' "${host:0:24}" "$note" '' '' '' '' "$host" 
}

# ---------------------------------------------------------------- sources ---

# Claude Code writes one .jsonl per session under a directory named after the
# project path, but that name is a lossy encoding (both slashes and dashes in
# the path become dashes), so the working directory is read from the transcript.
source_claude() {
  local dir="$HOME/.claude/projects"
  [ -d "$dir" ] || return 0
  local f id cwd title
  # shellcheck disable=SC2012  # ls -t is the portable way to order by mtime
  { ls -t "$dir"/*/*.jsonl 2>/dev/null || true; } | head -n "$LIMIT" | while IFS= read -r f; do
    id=$(basename "$f" .jsonl)
    # Both values sit in the opening messages; 80 lines clears the header
    # without reading megabytes of transcript.
    IFS="$TAB" read -r cwd title <<<"$(
      head -n 80 "$f" | jq -rs '
        ([.[] | select(.cwd != null) | .cwd] | first // "") as $cwd
        | ([.[]
             | select(.type == "user" and (.isSidechain | not))
             | .message.content
             | if type == "string" then .
               elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
               else "" end
             | gsub("\\s+"; " ") | ltrimstr(" ")]
           # Slash-command turns and the caveat Claude Code prepends to them
           # are markup, not a description of the session.
           | map(select(. != "" and (startswith("<") | not))) | first // "") as $title
        | [$cwd, $title] | @tsv
      ' 2>/dev/null
    )"
    [ -n "$cwd" ] && [ -d "$cwd" ] || continue
    row claude "$(mtime_of "$f")" "$(basename "$cwd")" "$title" "$id" "$cwd" "$f"
  done
}

# Vibe names its session directories session_<YYYYMMDD>_<HHMMSS>_<id8>, and the
# id8 suffix is exactly what `vibe --resume` takes, so neither the id nor the
# timestamp needs a file read; meta.json is opened only for cwd and title.
#
# A session directory can carry its own VIBE_HOME to keep per-session config out
# of the shared one, so those are scanned alongside it.
source_vibe() {
  local roots=("${VIBE_HOME:-$HOME/.vibe}"/logs/session/session_*)
  roots+=("$HOME"/agent-sessions/*/.vibe/logs/session/session_*)
  local d meta id when cwd title stamp
  # shellcheck disable=SC2012
  { ls -dt "${roots[@]}" 2>/dev/null || true; } | head -n "$LIMIT" | while IFS= read -r d; do
    d="${d%/}"
    meta="$d/meta.json"
    [ -f "$meta" ] || continue
    stamp=$(basename "$d")
    id="${stamp##*_}"
    when="${stamp:8:4}-${stamp:12:2}-${stamp:14:2} ${stamp:17:2}:${stamp:19:2}"
    IFS="$TAB" read -r cwd title <<<"$(
      jq -r '[(.environment.working_directory // ""),
              ((.title // "") | gsub("\\s+"; " "))] | @tsv' "$meta" 2>/dev/null
    )"
    [ -n "$cwd" ] && [ -d "$cwd" ] || continue
    row vibe "$when" "$(basename "$cwd")" "$title" "$id" "$cwd" "$d/messages.jsonl"
  done
}

source_local() {
  case "$1" in
    claude) source_claude ;;
    vibe)   source_vibe ;;
    *)      source_claude; source_vibe ;;
  esac
}

# ----------------------------------------------------------------- remote ---

# The hosts worth scanning are the ones herdr-mirror already folds into this
# sidebar (~/.config/herdr-mirror/hosts.toml, written per profile in
# profiles/*.nix): resuming a remote session opens its tab on that host, so
# without a mirror carrying it back there would be nothing to look at. Reusing
# the mirror's file rather than adding a second host list is what keeps the two
# from drifting into disagreeing about which hosts exist.
#
# Only the [hosts.<name>] headers and their target are read; every other key in
# that file belongs to herdr-mirror.
MIRROR_HOSTS="${AGENT_OPEN_HOSTS:-$HOME/.config/herdr-mirror/hosts.toml}"

mirror_hosts() {
  [ -f "$MIRROR_HOSTS" ] || return 0
  awk '
    /^[[:space:]]*\[hosts\.[^]]+\][[:space:]]*$/ {
      name = $0
      sub(/^[^.]*\./, "", name)
      sub(/\][[:space:]]*$/, "", name)
      next
    }
    # Any other table ends the one whose keys we are reading, so a `target`
    # belonging to some future [something.else] is not attributed to the host
    # above it.
    /^[[:space:]]*\[/ { name = ""; next }
    /^[[:space:]]*target[[:space:]]*=/ {
      if (name == "") next
      v = $0
      sub(/^[^=]*=[[:space:]]*/, "", v)
      gsub(/^"|"[[:space:]]*$/, "", v)
      print name "\t" v
    }
  ' "$MIRROR_HOSTS"
}

target_for() {
  local want="$1" name target
  while IFS="$TAB" read -r name target; do
    [ "$name" = "$want" ] || continue
    printf '%s' "$target"
    return 0
  done < <(mirror_hosts)
  return 1
}

# herdr-mirror's own per-host id map (remote id → { localId, tombstone, ... },
# see its src/state.rs): the same file remote_action.rs reverse-looks-up to
# turn a mirror pane's local ids into the real remote workspace/pane behind
# it. Reading it here is what lets `--new` land beside the remote session a
# mirrored pane is showing instead of in herdr-mirror's own `.mirror-pane`
# placeholder — see open_new().
MIRROR_STATE_DIR="${AGENT_OPEN_MIRROR_STATE:-$HOME/.local/state/herdr-mirror}"

# Prints "host\tremote_ws_id\tremote_pane_id" for the first host whose map
# claims local_ws as a mirrored workspace (a workspace only ever mirrors one
# host), empty with a non-zero exit when none does. remote_pane_id comes back
# empty when local_pane itself isn't the mirrored pane the map knows about —
# some other, unmirrored pane focused inside an otherwise-mirrored workspace —
# and the caller has to cope with that rather than assume it.
mirror_lookup() {
  local local_ws="$1" local_pane="$2" name target map rws rpane
  while IFS="$TAB" read -r name target; do
    [ -n "$name" ] || continue
    map="$MIRROR_STATE_DIR/$name-map.json"
    [ -f "$map" ] || continue
    rws=$(jq -r --arg lid "$local_ws" '
      (.workspaces // {}) | to_entries[]
      | select(.value.localId == $lid and ((.value.tombstone // false) | not))
      | .key' "$map" 2>/dev/null | head -1)
    [ -n "$rws" ] || continue
    rpane=$(jq -r --arg lid "$local_pane" '
      (.panes // {}) | to_entries[]
      | select(.value.localId == $lid and ((.value.tombstone // false) | not))
      | .key' "$map" 2>/dev/null | head -1)
    printf '%s\t%s\t%s\n' "$name" "$rws" "$rpane"
    return 0
  done < <(mirror_hosts)
  return 1
}

# One multiplexed connection per host: the picker calls out once to build the
# listing and again on every preview redraw, and a fresh handshake per cursor
# move is the difference between a preview that keeps up and one that does not.
# %C hashes the whole connection tuple, which keeps the socket path inside the
# 108-byte sun_path limit however long the target is.
SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o ControlMaster=auto
  -o ControlPath="${TMPDIR:-/tmp}/agent-open-%C"
  -o ControlPersist=60s
)

shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# PATH on a non-interactive `ssh host cmd` never picks up ~/.nix-profile/bin —
# the same gap herdr-mirror documents for its own remote_bin setting — so the
# lookup is spelled out here instead of left to the remote shell. Generic over
# the binary so a mirrored pane's own herdr can be queried (its real cwd) the
# same way agent-open itself is re-entered on the remote end.
remote_run_bin() {
  local target="$1" binname="$2" arg
  shift 2
  # shellcheck disable=SC2016  # $HOME and $bin are the remote shell's to expand
  local cmd="if command -v $binname >/dev/null 2>&1; then bin=$binname; else bin=\"\$HOME/.nix-profile/bin/$binname\"; fi; \"\$bin\""
  for arg in "$@"; do
    cmd="$cmd $(shq "$arg")"
  done
  # shellcheck disable=SC2029  # the command line is assembled here deliberately,
  # and shq() has already quoted every part of it that has to survive the hop
  ssh "${SSH_OPTS[@]}" "$target" "$cmd"
}

remote_run() { remote_run_bin "$1" agent-open "${@:2}"; }

# The scan is split in two so the hosts can be working while this machine is:
# every host is a `ls -t | head | jq` sweep of its own transcripts, and so is
# the local half, so starting the ssh calls first and reading their output last
# costs the longer of the two instead of their sum.
#
# The tmpdir is a global rather than a return value because a `$( )` would run
# this in a subshell, and the background jobs it starts would then be orphaned
# where the collector's `wait` could not see them.
#
# --no-remote keeps a host from scanning its own mirrors: droid mirrors
# dragonfruit, which mirrors rose, and without it rose's sessions would arrive
# twice under two different labels.
REMOTE_TMP=""

remote_scan_start() {
  local what="$1" name target
  REMOTE_TMP=$(mktemp -d) || { REMOTE_TMP=""; return 0; }
  while IFS="$TAB" read -r name target; do
    [ -n "$name" ] && [ -n "$target" ] || continue
    case "$name" in */*) continue ;; esac
    # ssh's own diagnostics are held back rather than let loose in the middle
    # of the rows; a host that fails is reported as a row instead, on collect.
    (
      remote_run "$target" --source "$what" --no-remote --host "$name" \
        >"$REMOTE_TMP/$name.rows" 2>"$REMOTE_TMP/$name.err" ||
        printf '%s' "$name" >"$REMOTE_TMP/$name.failed"
    ) &
  done < <(mirror_hosts)
}

# Hosts are emitted in the order hosts.toml lists them, which is the order they
# were thought worth mirroring in, rather than whatever order they answered in.
remote_scan_collect() {
  local name target
  [ -n "$REMOTE_TMP" ] || return 0
  wait
  while IFS="$TAB" read -r name target; do
    [ -e "$REMOTE_TMP/$name.failed" ] &&
      status_row "$name" "$(head -n 1 "$REMOTE_TMP/$name.err" 2>/dev/null || true)"
    [ -e "$REMOTE_TMP/$name.rows" ] && cat "$REMOTE_TMP/$name.rows"
  done < <(mirror_hosts)
  rm -rf "$REMOTE_TMP"
  REMOTE_TMP=""
}

source_rows() {
  local what="$1" remote="$2"
  [ "$remote" = "yes" ] && remote_scan_start "$what"
  source_local "$what"
  [ "$remote" = "yes" ] && remote_scan_collect
  return 0
}

# ---------------------------------------------------------------- preview ---

preview() {
  local agent="$1" id="$2" cwd="$3" log="$4" host="${5:-}"

  # A status row names a host and carries no session.
  if [ -z "$agent" ]; then
    printf '%s\n\nThis host is in %s but did not answer.\nCheck its herdr-mirror ssh target, and that it is on a\ndotfiles generation carrying agent-open.\n' \
      "$host" "$MIRROR_HOSTS"
    return 0
  fi

  # Reading a remote transcript means reaching the host anyway, so the whole
  # preview is rendered over there rather than copying the log back to format
  # it here.
  if [ -n "$host" ]; then
    local target
    target=$(target_for "$host") || {
      printf '%s: no target in %s\n' "$host" "$MIRROR_HOSTS"
      return 0
    }
    printf '%s  ' "$host"
    remote_run "$target" --preview "$agent" "$id" "$cwd" "$log" 2>&1 ||
      printf '\n(%s unreachable)\n' "$host"
    return 0
  fi

  printf '%s  %s\n%s\n\n' "$agent" "$id" "$cwd"
  [ -f "$log" ] || { printf '(no transcript)\n'; return 0; }
  case "$agent" in
    claude)
      tail -n 200 "$log" | jq -r '
        select(.type == "user" or .type == "assistant")
        | select(.isSidechain | not)
        | (.message.content
           | if type == "string" then .
             elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
             else "" end) as $text
        | select($text != "")
        | "\(.type | ascii_upcase): \($text)"
      ' 2>/dev/null | tail -n 20
      ;;
    vibe)
      tail -n 200 "$log" | jq -r '
        select((.role == "user" or .role == "assistant") and .injected != true)
        | (.content | if type == "string" then . else tostring end) as $text
        | select($text != "")
        | "\(.role | ascii_upcase): \($text)"
      ' 2>/dev/null | tail -n 20
      ;;
  esac
}

# ----------------------------------------------------------------- launch ---

# What a tab is called before the agent renames itself. A branch says more than
# a session id about what a tab is for, and in ~/agent-sessions — where every
# session directory is its own clone — it is usually the only thing that tells
# two tabs of the same project apart.
tab_label_for() {
  local cwd="$1" branch=""
  branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null) ||
    branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null) ||
    branch=""
  printf '%s' "${branch:-$(basename "$cwd")}"
}

# The first 12 terminal columns of a one-line title, the width herdr-tab-name
# is asked to keep to (~/.agent/conventions.md): herdr's tab bar divides its
# width among every tab in the workspace. The wide ranges are the CJK and emoji
# blocks a title realistically contains, not the full East Asian Width table.
title_label() {
  local text="$1" out="" width=0 c cp w i
  for ((i = 0; i < ${#text}; i++)); do
    c="${text:i:1}"
    printf -v cp '%d' "'$c"
    w=1
    if ((cp >= 0x1100 && cp <= 0x115F)) || ((cp >= 0x2E80 && cp <= 0xA4CF)) ||
      ((cp >= 0xAC00 && cp <= 0xD7A3)) || ((cp >= 0xF900 && cp <= 0xFAFF)) ||
      ((cp >= 0xFE30 && cp <= 0xFE4F)) || ((cp >= 0xFF00 && cp <= 0xFF60)) ||
      ((cp >= 0xFFE0 && cp <= 0xFFE6)) || ((cp >= 0x1F300 && cp <= 0x1FAFF)) ||
      ((cp >= 0x20000 && cp <= 0x3FFFD)); then
      w=2
    fi
    ((width + w <= 12)) || break
    out+="$c"
    width=$((width + w))
  done
  # A cut can land right after a space, which herdr would show as a gap.
  printf '%s' "${out%" "}"
}

# With no workspace given, a workspace whose label matches the project gets a
# new tab instead of a second workspace being created.
# `workspace create --cwd` falls back to the server's own directory when the
# path does not exist instead of failing, which is why cwd is checked first.
#
# workspace_label overrides the project name for both the lookup and the
# label of a workspace created here: a shelved session goes back to the
# workspace it was shelved from, whatever that one is called.
open_in_herdr() {
  local cwd="$1" label="$2" cmdline="$3" workspace="${4:-}" workspace_label="${5:-}"
  local project created pane tab out

  [ -d "$cwd" ] || die "no such directory: $cwd"
  project="${workspace_label:-$(basename "$cwd")}"

  # A caller that already knows the workspace (the one the user invoked from)
  # passes it in; without one — outside herdr, from a mirrored workspace, or
  # on the far end of open_remote's ssh hop — it is looked up by project name.
  #
  # No workspace yet, herdr not running, or a reply jq cannot read all land on
  # the same branch below: create rather than reuse. `|| true` because head
  # closing the pipe early would otherwise fail the pipeline under pipefail.
  if [ -z "$workspace" ]; then
    workspace=$({ herdr workspace list 2>/dev/null |
      jq -r --arg label "$project" \
        '.result.workspaces[]? | select(.label == $label) | .workspace_id' 2>/dev/null |
      head -1; } || true)
  fi

  # Every herdr call is checked by hand. Left bare, a non-zero exit inside a
  # command substitution trips errexit and kills the script before it reaches
  # any message of its own, which in a popup means the window simply vanishes.
  if [ -n "$workspace" ]; then
    created=$(herdr tab create --workspace "$workspace" --cwd "$cwd" --label "$label" --focus 2>&1) ||
      die "herdr tab create failed: $created"
  else
    # --label on workspace create names the workspace, and the tab it opens
    # inside keeps herdr's default numeric label, so that one is set after.
    created=$(herdr workspace create --cwd "$cwd" --label "$project" --focus 2>&1) ||
      die "herdr workspace create failed: $created"
  fi

  pane=$(jq -r '.result.root_pane.pane_id // empty' <<<"$created" 2>/dev/null) || pane=""
  tab=$(jq -r '.result.root_pane.tab_id // empty' <<<"$created" 2>/dev/null) || tab=""
  [ -n "$pane" ] || die "no pane id in herdr's reply: $created"

  if [ -n "$tab" ]; then
    herdr tab rename "$tab" "$label" >/dev/null 2>&1 || true
  fi

  # `pane run` types the string into the pane's shell rather than exec'ing it,
  # so it has to arrive as one argument or the quoting is flattened away.
  out=$(herdr pane run "$pane" "$cmdline" 2>&1) || die "herdr pane run failed: $out"
}

# A remote row's tab is created by that host's own herdr, which is the server
# herdr-mirror streams into this sidebar. Opening it locally would instead put
# the agent's process on this machine, pointed at a path that only exists over
# there. Nothing appears until the mirror for that host is running
# (prefix+shift+m) — the tab is real either way, just not on screen.
# workspace, when given, is a REMOTE workspace id (from mirror_lookup): the
# tab lands inside the existing mirrored workspace instead of --open's normal
# lookup-or-create-by-project-name, which is what makes open_new()'s mirror
# path indistinguishable from herdr-mirror's own remote-tab.
# label, when given, replaces the far end's own branch label for the tab.
open_remote() {
  local host="$1" cwd="$2" cmdline="$3" workspace="${4:-}" label="${5:-}" target out
  target=$(target_for "$host") || die "no target for host: $host"
  out=$(remote_run "$target" --open "$cwd" "$cmdline" "$workspace" "$label" 2>&1) ||
    die "opening on $host failed: $out"
}

# Opening a fresh session goes beside the pane that asked for it rather than
# into a workspace named after the directory: the point of the binding is "an
# agent, here, now". herdr's foreground_cwd follows `cd` inside the pane, so it
# beats the pane's starting cwd for guessing where "here" is.
# `--new` with no agent named. Three rows is not much of a list, but picking
# from it beats memorising a chord per agent, and the first row is one keypress
# away either way.
pick_agent() {
  printf '%s\n' "${NEW_AGENTS[@]}" |
    fzf --prompt='new > ' --header='start a new agent session here' --no-info
}

# herdr captures the pane a keybinding fired from in HERDR_ACTIVE_PANE_ID,
# which is the only one of these that is set for a `type = "shell"` command
# (scripts/herdr-paste.py leans on the same variable). HERDR_PANE_ID covers
# running this by hand from inside a pane; the snapshot covers neither being
# set, and is the same fallback herdr-paste.py uses.
invoking_pane_id() {
  local pane_id="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}"
  if [ -z "$pane_id" ]; then
    pane_id=$({ herdr api snapshot 2>/dev/null |
      jq -r '.result.snapshot.focused_pane_id // empty' 2>/dev/null; } || true)
  fi
  printf '%s' "$pane_id"
}

open_new() {
  local agent="$1" pane_id pane cwd workspace host_line host rws rpane target remote_cwd

  pane_id=$(invoking_pane_id)
  [ -n "$pane_id" ] || die "no pane to open beside — is this running inside herdr?"

  pane=$(herdr pane get "$pane_id" 2>&1) || die "herdr pane get failed: $pane"
  cwd=$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' <<<"$pane" 2>/dev/null) || cwd=""
  workspace=$(jq -r '.result.pane.workspace_id // empty' <<<"$pane" 2>/dev/null) || workspace=""

  # A mirrored pane's local cwd is herdr-mirror's own `.mirror-pane`
  # placeholder, not anywhere that exists on this machine — opening there
  # would put the new agent in a client-side directory instead of beside the
  # remote session being looked at. Route through the same host the mirror
  # comes from instead, the way herdr-mirror's own remote-tab does.
  if host_line=$(mirror_lookup "$workspace" "$pane_id") && [ -n "$host_line" ]; then
    IFS="$TAB" read -r host rws rpane <<<"$host_line"
    target=$(target_for "$host") || die "mirror host $host has no target in $MIRROR_HOSTS"
    remote_cwd=""
    if [ -n "$rpane" ]; then
      remote_cwd=$(remote_run_bin "$target" herdr pane get "$rpane" 2>/dev/null |
        jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' 2>/dev/null) || remote_cwd=""
    fi
    [ -n "$remote_cwd" ] ||
      die "focused pane is in $host's mirror, but its remote cwd could not be resolved — is the mirror daemon syncing?"
    open_remote "$host" "$remote_cwd" "$agent" "$rws"
    return
  fi

  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
  open_in_herdr "$cwd" "$(tab_label_for "$cwd")" "$agent" "$workspace"
}

# The workspace of the pane the picker was opened from, so a local resume lands
# beside it the way `--new` does rather than in a workspace named after the
# session's directory — every ~/agent-sessions session shares one, so that
# lookup would gather them all in a workspace of their own. Empty when there is
# no such pane (run outside herdr) or the pane is in a herdr-mirror workspace,
# whose tabs belong to the remote host; open_in_herdr then looks one up by
# project name instead.
invoking_workspace() {
  local pane_id="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}" workspace
  [ -n "$pane_id" ] || return 0
  workspace=$({ herdr pane get "$pane_id" 2>/dev/null |
    jq -r '.result.pane.workspace_id // empty' 2>/dev/null; } || true)
  [ -n "$workspace" ] || return 0
  mirror_lookup "$workspace" "$pane_id" >/dev/null && return 0
  printf '%s' "$workspace"
}

# The project's .envrc is already loaded: herdr's default_shell wraps every
# pane in `direnv exec` (see shared/programs/herdr.nix), so the shell this
# command lands in has the environment before it reads the first keystroke.
resume_command() {
  local agent="$1" id="$2" flags="$3"
  printf '%s --resume %s%s' "$agent" "$id" "$flags"
}

# ------------------------------------------------------------------ shelf ---

# The resume picker lists every recent session, which is too many to tell the
# unfinished ones apart and says nothing about where each one used to sit. The
# shelf is the short list kept on purpose: a session is put on it by hand
# (`--shelve`, bound in shared/programs/herdr.nix), kept current by the agent's
# turn-end hook (`--shelf-refresh`), and taken off when it is done.
#
# One JSON file per session, so the hooks of sessions running side by side
# never write to the same file:
#
#   agent            claude | vibe
#   id               resume argument for that agent: the full session id for
#                    claude, the 8-character prefix for vibe
#   cwd              directory the session runs in — where it is resumed
#   title            the closest thing to a description of the task: claude's
#                    own terminal title, vibe's session title
#   tab_label        herdr tab label, restored on resume
#   workspace_id     herdr workspace id; only valid while that server lives
#   workspace_label  herdr workspace label, the fallback once the id is stale
#   shelved_at       epoch seconds the entry was created
#   updated_at       epoch seconds of the last snapshot
SHELF_DIR="${AGENT_SHELF_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-shelf}"

# herdr holds the session behind a pane only for agents it accepts session
# reports from, which is Claude Code. Vibe's report is dropped (see
# scripts/herdr-agent-report.py), so its session is read from the $session
# token that script also sets: the first 8 characters of the id, which is
# exactly what `vibe --resume` takes (see source_vibe). The token is empty
# until the session's first hook fires.
#
# A jq function over one pane object, yielding [agent, id] or nothing; both
# the single-pane lookup and the live check in shelf_rows use it.
SHELF_SESSION_JQ='
  def shelf_session:
    if .agent == "claude" and (.agent_session.value // "") != "" then
      ["claude", .agent_session.value]
    elif .agent == "vibe" and (.tokens.session // "") != "" then
      ["vibe", .tokens.session]
    else empty end;
'

# Prints "agent\tid", empty for a pane with no session to resume.
shelf_session_of() {
  jq -r "$SHELF_SESSION_JQ"' .result.pane | shelf_session | @tsv' <<<"$1" 2>/dev/null || true
}

# Vibe names its session directories session_<YYYYMMDD>_<HHMMSS>_<id8>, under
# the shared VIBE_HOME or a session directory's own (see source_vibe).
vibe_session_dir() {
  # shellcheck disable=SC2012  # ls -t is the portable way to order by mtime
  { ls -dt "${VIBE_HOME:-$HOME/.vibe}"/logs/session/session_*_"$1" \
      "$HOME"/agent-sessions/*/.vibe/logs/session/session_*_"$1" 2>/dev/null || true; } | head -1
}

# Claude Code titles its terminal after the task. Vibe's terminal title is
# always "Vibe", so its own session title is read instead, and the first user
# message stands in while that is still unset.
shelf_title() {
  local agent="$1" id="$2" pane="$3" dir
  case "$agent" in
    claude)
      jq -r '.result.pane.terminal_title_stripped // empty' <<<"$pane" 2>/dev/null || true
      ;;
    vibe)
      dir=$(vibe_session_dir "$id")
      [ -n "$dir" ] || return 0
      { jq -r '.title // empty' "$dir/meta.json" 2>/dev/null || true; } | grep . ||
        { jq -r 'select(.role == "user" and .injected != true)
                  | .content | if type == "string" then . else tostring end' \
            "$dir/messages.jsonl" 2>/dev/null || true; } | head -1
      ;;
  esac
}

shelf_path() { printf '%s/%s-%s.json' "$SHELF_DIR" "$1" "$2"; }

# A `type = "shell"` binding has no terminal to print to, so the outcome of
# --shelve is reported where it can be seen.
shelf_notify() {
  herdr notification show "$1" --body "$2" --sound none >/dev/null 2>&1 || true
}

# Merges the pane's current labels into the entry for agent $2, session $3.
# cwd and shelved_at are kept from the first snapshot: the session is resumed
# where it started, and a label that reads empty (herdr unreachable mid-call)
# never wipes a known one.
shelf_write() {
  local pane="$1" agent="$2" id="$3" path tab ws tab_label ws_label title previous='{}' tmp
  path=$(shelf_path "$agent" "$id")
  title=$(shelf_title "$agent" "$id" "$pane")
  title=$(printf '%s' "$title" | tr '\n\t' '  ')
  tab=$(jq -r '.result.pane.tab_id // empty' <<<"$pane")
  ws=$(jq -r '.result.pane.workspace_id // empty' <<<"$pane")
  tab_label=$({ herdr tab get "$tab" 2>/dev/null |
    jq -r '.result.tab.label // empty' 2>/dev/null; } || true)
  ws_label=$({ herdr workspace get "$ws" 2>/dev/null |
    jq -r '.result.workspace.label // empty' 2>/dev/null; } || true)
  [ -f "$path" ] && previous=$(cat "$path")

  mkdir -p "$SHELF_DIR"
  tmp="$path.new"
  jq -n \
    --argjson prev "$previous" \
    --argjson pane "$pane" \
    --arg agent "$agent" \
    --arg id "$id" \
    --arg title "$title" \
    --arg tab_label "$tab_label" \
    --arg ws_label "$ws_label" \
    --argjson now "$(date +%s)" '
      def keep($new; $old): if ($new // "") != "" then $new else ($old // "") end;
      $pane.result.pane as $p
      | $prev + {
          agent: $agent,
          id: $id,
          cwd: ($prev.cwd // $p.cwd),
          title: keep($title; $prev.title),
          tab_label: keep($tab_label; $prev.tab_label),
          workspace_id: keep($p.workspace_id; $prev.workspace_id),
          workspace_label: keep($ws_label; $prev.workspace_label),
          shelved_at: ($prev.shelved_at // $now),
          updated_at: $now
        }
    ' >"$tmp" && mv "$tmp" "$path"
}

cmd_shelve() {
  local pane_id pane session agent id path title
  pane_id=$(invoking_pane_id)
  [ -n "$pane_id" ] || die "no pane to shelve — is this running inside herdr?"
  pane=$(herdr pane get "$pane_id" 2>&1) || die "herdr pane get failed: $pane"
  session=$(shelf_session_of "$pane")
  if [ -z "$session" ]; then
    shelf_notify "Not shelved" "No resumable Claude Code or Vibe session in this pane yet"
    return 0
  fi
  IFS="$TAB" read -r agent id <<<"$session"
  path=$(shelf_path "$agent" "$id")
  shelf_write "$pane" "$agent" "$id"
  title=$(jq -r '.title' "$path" 2>/dev/null || true)
  shelf_notify "Shelved" "${title:-$id}"
}

# Called from the agent's turn-end hook, named by $1, with the hook payload on
# stdin. Every session runs it on every turn, so anything not on the shelf
# leaves before the first herdr call. Both agents hand over the full session
# id; vibe's entry is keyed by its first 8 characters (see SHELF_SESSION_JQ).
cmd_shelf_refresh() {
  local agent="${1:-claude}" payload id pane
  payload=$(cat)
  id=$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)
  [ -n "$id" ] || return 0
  [ "$agent" = vibe ] && id="${id:0:8}"
  [ -f "$(shelf_path "$agent" "$id")" ] || return 0
  [ -n "${HERDR_PANE_ID:-}" ] || return 0
  pane=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null) || return 0
  [ "$(shelf_session_of "$pane")" = "$agent${TAB}$id" ] || return 0
  shelf_write "$pane" "$agent" "$id"
}

# One row per entry: paused ones (no pane holds the session any more) before
# live ones, newest first within each. The live check asks herdr which session
# every pane holds, so a session counts as live wherever it was reopened.
#
#   1 display  state, last snapshot, workspace/tab, title
#   2 path     the entry file
#   3 pane     pane holding the session, empty when paused
shelf_rows() {
  local live f key pane
  [ -d "$SHELF_DIR" ] || return 0
  live=$({ herdr pane list 2>/dev/null | jq -r "$SHELF_SESSION_JQ"'
    .result.panes[]?
    | .pane_id as $pane
    | shelf_session
    | [.[0] + "-" + .[1], $pane] | @tsv
  ' 2>/dev/null; } || true)

  for f in "$SHELF_DIR"/*.json; do
    [ -f "$f" ] || continue
    key=$(basename "$f" .json)
    pane=$(awk -F"$TAB" -v k="$key" '$1 == k { print $2; exit }' <<<"$live")
    jq -r --arg path "$f" --arg pane "$pane" '
      [ (if $pane == "" then 0 else 1 end),
        (.updated_at // 0),
        (if $pane == "" then "paused" else "live" end),
        ((.workspace_label // "?") + "/" + (.tab_label // "?")),
        (.title // "" | gsub("\\s+"; " ")),
        $path, $pane ] | @tsv
    ' "$f" 2>/dev/null || true
  done | sort -t"$TAB" -k1,1n -k2,2nr |
    while IFS= read -r line; do
      emit_shelf_row "$line"
    done
}

# cut rather than `IFS=$'\t' read`: the empty pane field on every paused row
# would otherwise merge into its neighbour (see field() below).
emit_shelf_row() {
  local line="$1" updated state place title path pane
  updated=$(cut -f2 <<<"$line")
  state=$(cut -f3 <<<"$line")
  place=$(cut -f4 <<<"$line")
  title=$(cut -f5 <<<"$line")
  path=$(cut -f6 <<<"$line")
  pane=$(cut -f7 <<<"$line")
  printf '%-6s  %-16s  %-24s  %s\t%s\t%s\n' \
    "$state" "$(format_epoch "$updated")" "${place:0:24}" "$(one_line "$title")" "$path" "$pane"
}

shelf_preview() {
  local path="$1" agent id cwd log
  [ -f "$path" ] || { printf '(entry removed)\n'; return 0; }
  agent=$(jq -r '.agent' "$path")
  id=$(jq -r '.id' "$path")
  cwd=$(jq -r '.cwd' "$path")
  case "$agent" in
    claude) log=$({ ls "$HOME"/.claude/projects/*/"$id".jsonl 2>/dev/null || true; } | head -1) ;;
    vibe)   log="$(vibe_session_dir "$id")/messages.jsonl" ;;
    *)      log="" ;;
  esac
  preview "$agent" "$id" "$cwd" "$log" ""
}

# A stored workspace id is reused only while it still carries the stored
# label: ids restart with every herdr server, and a reused id can belong to a
# different workspace altogether. Otherwise open_in_herdr looks the workspace
# up by label, and creates it under that label when it is gone.
shelf_resume() {
  local path="$1" agent id cwd tab_label ws_id ws_label current
  agent=$(jq -r '.agent' "$path")
  id=$(jq -r '.id' "$path")
  cwd=$(jq -r '.cwd' "$path")
  tab_label=$(jq -r '.tab_label // empty' "$path")
  ws_id=$(jq -r '.workspace_id // empty' "$path")
  ws_label=$(jq -r '.workspace_label // empty' "$path")

  if [ -n "$ws_id" ]; then
    current=$({ herdr workspace get "$ws_id" 2>/dev/null |
      jq -r '.result.workspace.label // empty' 2>/dev/null; } || true)
    [ -n "$current" ] && [ "$current" = "$ws_label" ] || ws_id=""
  fi

  open_in_herdr "$cwd" "${tab_label:-$(tab_label_for "$cwd")}" \
    "$(resume_command "$agent" "$id" "")" "$ws_id" "$ws_label"
}

cmd_shelf() {
  local selection path pane
  selection=$(
    shelf_rows | fzf \
      --delimiter="$TAB" \
      --with-nth=1 \
      --no-hscroll \
      --prompt='shelf > ' \
      --header=$'enter: resume (paused) / focus (live)  ctrl-x: done — take off the shelf' \
      --bind="ctrl-x:execute-silent(rm -f {2})+reload($reenter --shelf-rows)" \
      --preview="$reenter --shelf-preview {2}" \
      --preview-window=down,60%,wrap
  ) || return 0
  [ -n "$selection" ] || return 0
  path=$(cut -f2 <<<"$selection")
  pane=$(cut -f3 <<<"$selection")
  if [ -n "$pane" ]; then
    herdr agent focus "$pane" >/dev/null
    return 0
  fi
  [ -f "$path" ] || return 0
  shelf_resume "$path"
}

# ------------------------------------------------------------------- main ---

# fzf runs reload() and --preview through `sh -c`, so re-entry has to be a
# command line rather than an argv, and naming the interpreter is what keeps it
# working when the script is started as `bash path/to/agent-open.sh` out of a
# checkout: there the file carries neither a shebang nor the execute bit, both
# of which only the writeShellApplication build supplies.
reenter="bash $(printf '%q' "$0")"

case "${1:-}" in
  --new)
    agent="${2:-}"
    if [ -z "$agent" ]; then
      agent=$(pick_agent) || exit 0
      [ -n "$agent" ] || exit 0
    fi
    open_new "$agent"
    exit 0
    ;;
  --shelve)
    cmd_shelve
    exit 0
    ;;
  --shelf)
    cmd_shelf
    exit 0
    ;;
  --shelf-rows)
    shelf_rows
    exit 0
    ;;
  --shelf-resume)
    [ -f "${2:-}" ] || die "no shelf entry: ${2:-}"
    shelf_resume "$2"
    exit 0
    ;;
  --shelf-preview)
    shelf_preview "${2:-}"
    exit 0
    ;;
  --shelf-refresh)
    cmd_shelf_refresh "${2:-}"
    exit 0
    ;;
  --preview)
    preview "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
    exit 0
    ;;
  --open)
    cwd="${2:-}"
    [ -n "$cwd" ] || die "--open needs a directory"
    # $4, when set, is a REMOTE workspace id (open_remote's mirror path):
    # this runs on the far end of the ssh hop, so it is this host's own
    # workspace to create the tab in, not something to translate further.
    # $5, when set, is the tab label; without it the branch is read here,
    # where the directory actually exists.
    label="${5:-}"
    [ -n "$label" ] || label=$(tab_label_for "$cwd")
    open_in_herdr "$cwd" "$label" "${3:-}" "${4:-}"
    exit 0
    ;;
  --source)
    shift
    SOURCE="all"
    REMOTE="yes"
    while [ $# -gt 0 ]; do
      case "$1" in
        claude|vibe|all) SOURCE="$1"; shift ;;
        # Only ever set by the far end of an ssh from another host's picker,
        # to label the rows with the host they were read on.
        --host)          HOST_LABEL="${2:-}"; shift 2 ;;
        # Both the far end (so a host does not scan its own mirrors) and the
        # ctrl-s binding (so the picker can skip the network on request).
        --no-remote)     REMOTE="no"; shift ;;
        *) die "unknown argument: $1" ;;
      esac
    done
    source_rows "$SOURCE" "$REMOTE"
    exit 0
    ;;
esac

selection=$(
  source_rows all yes | fzf \
    --delimiter="$TAB" \
    --with-nth=1 \
    --no-hscroll \
    --prompt='resume > ' \
    --header=$'enter: resume  ctrl-a: auto-approve  ctrl-p: plan mode  ctrl-u: smart-approve (vibe)\nctrl-l: claude only  ctrl-v: vibe only  ctrl-o: both  ctrl-s: this host only' \
    --expect=ctrl-a,ctrl-p,ctrl-u \
    --bind="ctrl-l:reload($reenter --source claude)" \
    --bind="ctrl-v:reload($reenter --source vibe)" \
    --bind="ctrl-o:reload($reenter --source all)" \
    --bind="ctrl-s:reload($reenter --source all --no-remote)" \
    --preview="$reenter --preview {2} {3} {4} {5} {6}" \
    --preview-window=down,60%,wrap
) || exit 0

key=$(sed -n 1p <<<"$selection")
line=$(sed -n 2p <<<"$selection")
[ -n "$line" ] || exit 0

# Not `IFS=$'\t' read`: tab counts as IFS whitespace, so a run of them is one
# separator there and the empty host on every local row would swallow the field
# after it — reading the timestamp as a hostname and sending the resume to a
# machine by that name. cut counts delimiters instead of merging them.
field() { cut -f"$1" <<<"$line"; }
agent=$(field 2)
id=$(field 3)
cwd=$(field 4)
host=$(field 6)
label=$(title_label "$(field 7)")

# A status row has no agent to resume; picking one is a no-op, not an error.
[ -n "$agent" ] || exit 0

flags=""
case "$agent:$key" in
  claude:ctrl-a) flags=" --permission-mode auto" ;;
  claude:ctrl-p) flags=" --permission-mode plan" ;;
  vibe:ctrl-a)   flags=" --auto-approve" ;;
  # --smart-approve needs --experimental-harness (Unified Harness) or it is a
  # silent no-op and the session falls back to the default ask agent.
  vibe:ctrl-u)   flags=" --smart-approve --experimental-harness" ;;
  # Vibe has no plan mode, so ctrl-p there falls through to a plain resume.
  # claude has no smart-approve classifier, so ctrl-u there also falls through.
esac

cmdline=$(resume_command "$agent" "$id" "$flags")

if [ -n "$host" ]; then
  open_remote "$host" "$cwd" "$cmdline" "" "$label"
else
  [ -n "$label" ] || label=$(tab_label_for "$cwd")
  open_in_herdr "$cwd" "$label" "$cmdline" "$(invoking_workspace)"
fi
