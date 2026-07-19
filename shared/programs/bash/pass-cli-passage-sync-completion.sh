# pass-cli-passage-sync.sh completion, for both direct invocation
# (./scripts/pass-cli-passage-sync.sh) and `task secrets:pull/push/sync/list --
# ...` (go-task's own completion gives up entirely once it sees `--`, so
# task's wrapper below takes over from there for the secrets:* sync tasks).
#
# --path completes from local passage paths (--path registers an existing
# passage path as a new pass-cli item). --prefix completes from the pass-cli
# vault's existing paths (all of pull/push/sync filter against the vault's
# item set, not passage). Remote lookups are timeout-bounded so a stale
# pass-cli login doesn't hang completion.

if ! command -v pass-cli &> /dev/null || ! command -v passage &> /dev/null || ! command -v jq &> /dev/null; then
  return
fi

# Portable stand-in for coreutils `timeout` (not guaranteed to be on PATH in
# every profile) — runs "$@" in the background and kills it after $1
# seconds if it hasn't finished, using only bash job control.
_pass_cli_passage_sync_timeout() {
  local secs="$1"
  shift
  "$@" &
  local pid=$!
  (sleep "$secs" 2> /dev/null; kill -TERM "$pid" 2> /dev/null) &
  local watcher=$!
  wait "$pid" 2> /dev/null
  local rc=$?
  kill "$watcher" 2> /dev/null
  wait "$watcher" 2> /dev/null
  return "$rc"
}

# Fills COMPREPLY for a --path/--prefix/other flag at $cur, given $prev and
# the preceding words on the line (used to find an already-typed --vault).
_pass_cli_passage_sync_reply() {
  local cur="$1" prev="$2"
  shift 2
  local words=("$@") vault i store

  case "$prev" in
    --path)
      store="${PASSAGE_DIR:-$HOME/.passage/store}"
      COMPREPLY=($(compgen -W "$(find "$store" -type f -name '*.age' 2>/dev/null | sed "s|^$store/||; s|\.age\$||")" -- "$cur"))
      return
      ;;
    --prefix)
      vault="Passage"
      for ((i = 0; i + 1 < ${#words[@]}; i++)); do
        if [ "${words[i]}" = "--vault" ]; then
          vault="${words[i + 1]}"
        fi
      done
      COMPREPLY=($(compgen -W "$(_pass_cli_passage_sync_timeout 3 pass-cli item list --vault-name "$vault" --filter-state active --output json 2>/dev/null | jq -r '.items[].title' 2>/dev/null)" -- "$cur"))
      return
      ;;
    --vault | --prefer)
      return
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "--vault --path --prefer --prefix --dry-run -h --help" -- "$cur"))
  fi
}

_pass_cli_passage_sync_completions() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "pull push sync list" -- "$cur"))
    return
  fi

  _pass_cli_passage_sync_reply "$cur" "$prev" "${COMP_WORDS[@]:1:COMP_CWORD-1}"
}

complete -F _pass_cli_passage_sync_completions pass-cli-passage-sync.sh ./scripts/pass-cli-passage-sync.sh scripts/pass-cli-passage-sync.sh
