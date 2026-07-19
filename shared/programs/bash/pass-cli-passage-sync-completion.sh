# pass-cli-passage-sync.sh completion.
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

_pass_cli_passage_sync_completions() {
  local cur prev vault i store

  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "$prev" in
    --path)
      store="${PASSAGE_DIR:-$HOME/.passage/store}"
      COMPREPLY=($(compgen -W "$(find "$store" -type f -name '*.age' 2>/dev/null | sed "s|^$store/||; s|\.age\$||")" -- "$cur"))
      return
      ;;
    --prefix)
      vault="Passage"
      for ((i = 1; i < COMP_CWORD; i++)); do
        if [ "${COMP_WORDS[i]}" = "--vault" ]; then
          vault="${COMP_WORDS[i + 1]}"
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
  elif [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "pull push sync list" -- "$cur"))
  fi
}

complete -F _pass_cli_passage_sync_completions pass-cli-passage-sync.sh ./scripts/pass-cli-passage-sync.sh scripts/pass-cli-passage-sync.sh
