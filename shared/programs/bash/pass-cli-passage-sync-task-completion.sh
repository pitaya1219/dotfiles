# Extends go-task's own completion (defined just above) so args typed after
# `--` for the secrets:* sync tasks get real completion instead of nothing.
# go-task's generated _task function returns empty as soon as the cursor is
# past a literal `--`, since it has no idea what CLI_ARGS means to the
# underlying task; this wrapper takes over only in that specific case, for
# only the tasks that actually forward CLI_ARGS to pass-cli-passage-sync.sh,
# and falls back to go-task's own _task for everything else.

if ! declare -F _task &> /dev/null || ! declare -F _pass_cli_passage_sync_reply &> /dev/null; then
  return
fi

_pass_cli_passage_sync_task_completions() {
  # Task names contain ':', which is a default COMP_WORDBREAKS character —
  # without reassembly, COMP_WORDS would see "secrets", ":", "push" as three
  # separate words instead of "secrets:push" as one, and the case match
  # below would never fire. _init_completion -n : (the same flag go-task's
  # own _task uses) reassembles across ':' into $words/$cword.
  local cur prev words cword dashdash i
  _init_completion -n : || return

  dashdash=-1
  for ((i = 1; i < cword; i++)); do
    if [ "${words[i]}" = "--" ]; then
      dashdash=$i
      break
    fi
  done

  if [ "$dashdash" -ge 0 ] && [ "$cword" -gt "$dashdash" ]; then
    case "${words[1]}" in
      secrets:pull | secrets:push | secrets:sync | secrets:sync:test | secrets:list)
        _pass_cli_passage_sync_reply "$cur" "$prev" "${words[@]:dashdash+1:cword-dashdash-1}"
        return
        ;;
    esac
  fi

  _task
}

complete -F _pass_cli_passage_sync_task_completions "${TASK_EXE:-task}"
