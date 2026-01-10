# shellm - LLM-powered shell completion
# Keybindings for vi-command mode with : prefix

# Check if shellm is available
if ! command -v shellm &> /dev/null; then
    return
fi

# Command completion (::)
_shellm_complete() {
    local result
    result=$(shellm complete "$READLINE_LINE" 2>/dev/null) && {
        READLINE_LINE="$result"
        READLINE_POINT=${#READLINE_LINE}
    }
}

# Fix last failed command (:e)
_shellm_fix() {
    local result
    result=$(shellm fix "$_SHELLM_LAST_CMD" -e "${_SHELLM_LAST_EXIT:-0}" 2>/dev/null) && {
        READLINE_LINE="$result"
        READLINE_POINT=${#READLINE_LINE}
    }
}

# Explain command (:x)
_shellm_explain() {
    [[ -z "$READLINE_LINE" ]] && return
    echo ""
    shellm explain "$READLINE_LINE"
}

# Cheatsheet (:c)
_shellm_cheatsheet() {
    local tool="${READLINE_LINE%% *}"
    [[ -z "$tool" ]] && tool="bash"
    echo ""
    shellm cheatsheet "$tool"
}

# Preview execution (:p)
_shellm_preview() {
    [[ -z "$READLINE_LINE" ]] && return
    echo ""
    shellm preview "$READLINE_LINE"
}

# History search with natural language (:h)
_shellm_history() {
    local entries
    entries=$(history 100 | tail -100 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
    local result
    result=$(shellm history "$READLINE_LINE" --entries "$entries" 2>/dev/null) && {
        READLINE_LINE="$result"
        READLINE_POINT=${#READLINE_LINE}
    }
}

# Status display (:?)
_shellm_status() {
    echo ""
    shellm status
}

# Keybindings (vi-command mode with : prefix)
bind -m vi-command -x '"::": _shellm_complete'
bind -m vi-command -x '":e": _shellm_fix'
bind -m vi-command -x '":x": _shellm_explain'
bind -m vi-command -x '":c": _shellm_cheatsheet'
bind -m vi-command -x '":p": _shellm_preview'
bind -m vi-command -x '":h": _shellm_history'
bind -m vi-command -x '":?": _shellm_status'

# Capture last command and exit status
_shellm_capture() {
    _SHELLM_LAST_EXIT=$?
    _SHELLM_LAST_CMD=$(history 1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
}

# Integrate with PROMPT_COMMAND (compatible with starship)
if [[ -n "$STARSHIP_SHELL" ]]; then
    # Starship uses precmd functions
    starship_precmd_user_func="_shellm_capture"
else
    PROMPT_COMMAND="_shellm_capture;${PROMPT_COMMAND:-}"
fi
