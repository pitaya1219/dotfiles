# agent-open — opens a coding agent as a herdr tab, either fresh in the current
# workspace (`--new <agent>`) or by resuming a past session picked out of fzf,
# in which case the tab starts in the directory that session ran in.
#
# Sessions on the hosts herdr-mirror folds into this sidebar are listed next to
# the local ones, and resuming one opens its tab on that host rather than here.
# See the remote section for why the host list is taken from the mirror's
# config and not one of its own.
#
# Both paths label the new tab with the target directory's git branch. That is
# a placeholder as much as a label: the agent is expected to replace it with a
# short task name through herdr-tab-name (see shared/programs/herdr.nix), and
# the branch is what stays visible until it does — or forever, if it does not.
#
# Every source prints the same six tab-separated fields, which is what lets a
# single launcher handle any row the picker returns:
#
#   1 display  the preformatted list line: agent, last activity, project, title
#   2 agent    claude | vibe — also the binary that gets resumed
#   3 id       resume argument for that agent
#   4 cwd      working directory the session ran in
#   5 log      transcript path, read by the preview
#   6 host     herdr-mirror host the session lives on, empty when it is local
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
# five fields behind them. Both callers below assemble arguments for it rather
# than carrying a copy of the format, so the shape has a single definition to
# change.
emit_row() {
  printf '%-6s  %-16s  %-24s  %s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

row() {
  local agent="$1" when="$2" project="$3" title="$4" id="$5" cwd="$6" log="$7"
  local place="$project"
  [ -z "$HOST_LABEL" ] || place="$HOST_LABEL:$project"
  emit_row "$agent" "$when" "${place:0:24}" "$(one_line "$title")" \
    "$agent" "$id" "$cwd" "$log" "$HOST_LABEL"
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
# lookup is spelled out here instead of left to the remote shell.
remote_run() {
  local target="$1" arg
  shift
  # shellcheck disable=SC2016  # $HOME and $bin are the remote shell's to expand
  local cmd='if command -v agent-open >/dev/null 2>&1; then bin=agent-open; else bin="$HOME/.nix-profile/bin/agent-open"; fi; "$bin"'
  for arg in "$@"; do
    cmd="$cmd $(shq "$arg")"
  done
  # shellcheck disable=SC2029  # the command line is assembled here deliberately,
  # and shq() has already quoted every part of it that has to survive the hop
  ssh "${SSH_OPTS[@]}" "$target" "$cmd"
}

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

# herdr keeps one workspace per project in normal use, so a workspace whose
# label already matches gets a new tab instead of a second workspace.
# `workspace create --cwd` falls back to the server's own directory when the
# path does not exist instead of failing, which is why cwd is checked first.
open_in_herdr() {
  local cwd="$1" label="$2" cmdline="$3" workspace="${4:-}" project created pane tab out

  [ -d "$cwd" ] || die "no such directory: $cwd"
  project=$(basename "$cwd")

  # A caller that already knows the workspace (opening a new session beside the
  # one asking for it) passes it in; the picker does not, and looks one up by
  # project name instead.
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
open_remote() {
  local host="$1" cwd="$2" cmdline="$3" target out
  target=$(target_for "$host") || die "no target for host: $host"
  out=$(remote_run "$target" --open "$cwd" "$cmdline" 2>&1) ||
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

open_new() {
  local agent="$1" pane_id pane cwd workspace

  # herdr captures the pane a keybinding fired from in HERDR_ACTIVE_PANE_ID,
  # which is the only one of these that is set for a `type = "shell"` command
  # (scripts/herdr-paste.py leans on the same variable). HERDR_PANE_ID covers
  # running this by hand from inside a pane; the snapshot covers neither being
  # set, and is the same fallback herdr-paste.py uses.
  pane_id="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}"
  if [ -z "$pane_id" ]; then
    pane_id=$({ herdr api snapshot 2>/dev/null |
      jq -r '.result.snapshot.focused_pane_id // empty' 2>/dev/null; } || true)
  fi
  [ -n "$pane_id" ] || die "no pane to open beside — is this running inside herdr?"

  pane=$(herdr pane get "$pane_id" 2>&1) || die "herdr pane get failed: $pane"
  cwd=$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' <<<"$pane" 2>/dev/null) || cwd=""
  workspace=$(jq -r '.result.pane.workspace_id // empty' <<<"$pane" 2>/dev/null) || workspace=""
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

  open_in_herdr "$cwd" "$(tab_label_for "$cwd")" "$agent" "$workspace"
}

# The project's .envrc is already loaded: herdr's default_shell wraps every
# pane in `direnv exec` (see shared/programs/herdr.nix), so the shell this
# command lands in has the environment before it reads the first keystroke.
resume_command() {
  local agent="$1" id="$2" flags="$3"
  printf '%s --resume %s%s' "$agent" "$id" "$flags"
}

# ------------------------------------------------------------------- main ---

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
  --preview)
    preview "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
    exit 0
    ;;
  --open)
    cwd="${2:-}"
    [ -n "$cwd" ] || die "--open needs a directory"
    open_in_herdr "$cwd" "$(tab_label_for "$cwd")" "${3:-}"
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

# fzf runs reload() and --preview through `sh -c`, so re-entry has to be a
# command line rather than an argv, and naming the interpreter is what keeps it
# working when the script is started as `bash path/to/agent-open.sh` out of a
# checkout: there the file carries neither a shebang nor the execute bit, both
# of which only the writeShellApplication build supplies.
reenter="bash $(printf '%q' "$0")"

selection=$(
  source_rows all yes | fzf \
    --delimiter="$TAB" \
    --with-nth=1 \
    --no-hscroll \
    --prompt='resume > ' \
    --header=$'enter: resume  ctrl-a: auto-approve  ctrl-p: plan mode\nctrl-l: claude only  ctrl-v: vibe only  ctrl-o: both  ctrl-s: this host only' \
    --expect=ctrl-a,ctrl-p \
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

# A status row has no agent to resume; picking one is a no-op, not an error.
[ -n "$agent" ] || exit 0

flags=""
case "$agent:$key" in
  claude:ctrl-a) flags=" --permission-mode auto" ;;
  claude:ctrl-p) flags=" --permission-mode plan" ;;
  vibe:ctrl-a)   flags=" --auto-approve" ;;
  # Vibe has no plan mode, so ctrl-p there falls through to a plain resume.
esac

cmdline=$(resume_command "$agent" "$id" "$flags")

if [ -n "$host" ]; then
  open_remote "$host" "$cwd" "$cmdline"
else
  open_in_herdr "$cwd" "$(tab_label_for "$cwd")" "$cmdline"
fi
