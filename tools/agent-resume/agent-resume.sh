# agent-resume — one fzf picker over past Claude Code and Vibe sessions that
# opens the chosen one as a herdr tab, already `cd`'d into the directory the
# session ran in.
#
# Every source prints the same five tab-separated fields, which is what lets a
# single launcher handle any row the picker returns:
#
#   1 display  the preformatted list line: agent, last activity, project, title
#   2 agent    claude | vibe — also the binary that gets resumed
#   3 id       resume argument for that agent
#   4 cwd      working directory the session ran in
#   5 log      transcript path, read by the preview
#
# Only field 1 is shown (--with-nth); the rest stay addressable as {2}..{5} in
# --preview, which sees the untransformed line.
#
# Sources are switched inside fzf via reload(), which re-enters this script
# with `--source <name>`; that subcommand is also usable on its own.

LIMIT="${AGENT_RESUME_LIMIT:-80}"
TAB=$'\t'

# A popup closes the moment its command exits, so an error written on the way
# out is never seen. Hold the window open until a key is pressed whenever there
# is a terminal to hold.
die() {
  printf 'agent-resume: %s\n' "$1" >&2
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
row() {
  local agent="$1" when="$2" project="$3" title="$4" id="$5" cwd="$6" log="$7"
  printf '%-6s  %-16s  %-22s  %s\t%s\t%s\t%s\t%s\n' \
    "$agent" "$when" "${project:0:22}" "$(one_line "$title")" \
    "$agent" "$id" "$cwd" "$log"
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

source_all() { source_claude; source_vibe; }

# ---------------------------------------------------------------- preview ---

preview() {
  local agent="$1" id="$2" cwd="$3" log="$4"
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

# herdr keeps one workspace per project in normal use, so a workspace whose
# label already matches gets a new tab instead of a second workspace.
# `workspace create --cwd` falls back to the server's own directory when the
# path does not exist instead of failing, which is why cwd is checked first.
open_in_herdr() {
  local cwd="$1" label="$2" cmdline="$3" project workspace created pane tab out

  [ -d "$cwd" ] || die "no such directory: $cwd"
  project=$(basename "$cwd")

  # No workspace yet, herdr not running, or a reply jq cannot read all land on
  # the same branch below: create rather than reuse. `|| true` because head
  # closing the pipe early would otherwise fail the pipeline under pipefail.
  workspace=$({ herdr workspace list 2>/dev/null |
    jq -r --arg label "$project" \
      '.result.workspaces[]? | select(.label == $label) | .workspace_id' 2>/dev/null |
    head -1; } || true)

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

# The project's .envrc is already loaded: herdr's default_shell wraps every
# pane in `direnv exec` (see shared/programs/herdr.nix), so the shell this
# command lands in has the environment before it reads the first keystroke.
resume_command() {
  local agent="$1" id="$2" flags="$3"
  printf '%s --resume %s%s' "$agent" "$id" "$flags"
}

# ------------------------------------------------------------------- main ---

case "${1:-}" in
  --source)
    case "${2:-all}" in
      claude) source_claude ;;
      vibe)   source_vibe ;;
      *)      source_all ;;
    esac
    exit 0
    ;;
  --preview)
    preview "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    exit 0
    ;;
esac

# fzf runs reload() and --preview through `sh -c`, so re-entry has to be a
# command line rather than an argv, and naming the interpreter is what keeps it
# working when the script is started as `bash path/to/agent-resume.sh` out of a
# checkout: there the file carries neither a shebang nor the execute bit, both
# of which only the writeShellApplication build supplies.
reenter="bash $(printf '%q' "$0")"

selection=$(
  source_all | fzf \
    --delimiter="$TAB" \
    --with-nth=1 \
    --no-hscroll \
    --prompt='resume > ' \
    --header=$'enter: resume  ctrl-a: auto-approve  ctrl-p: plan mode\nctrl-l: claude only  ctrl-v: vibe only  ctrl-o: both' \
    --expect=ctrl-a,ctrl-p \
    --bind="ctrl-l:reload($reenter --source claude)" \
    --bind="ctrl-v:reload($reenter --source vibe)" \
    --bind="ctrl-o:reload($reenter --source all)" \
    --preview="$reenter --preview {2} {3} {4} {5}" \
    --preview-window=down,60%,wrap
) || exit 0

key=$(sed -n 1p <<<"$selection")
line=$(sed -n 2p <<<"$selection")
[ -n "$line" ] || exit 0

IFS="$TAB" read -r _display agent id cwd _log <<<"$line"

flags=""
case "$agent:$key" in
  claude:ctrl-a) flags=" --permission-mode auto" ;;
  claude:ctrl-p) flags=" --permission-mode plan" ;;
  vibe:ctrl-a)   flags=" --auto-approve" ;;
  # Vibe has no plan mode, so ctrl-p there falls through to a plain resume.
esac

open_in_herdr "$cwd" "$agent-${id:0:8}" "$(resume_command "$agent" "$id" "$flags")"
