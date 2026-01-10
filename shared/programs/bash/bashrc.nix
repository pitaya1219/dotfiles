''
# LLM Completion
${builtins.readFile ./llm-complete.sh}

# LLM keybindings (vi-command mode with : prefix, like vim's command mode)
bind -m vi-command -x '"::": _llm_complete_wrapper'  # Command completion / pipe completion
bind -m vi-command -x '":e": _llm_error_fix'         # Fix last failed command
bind -m vi-command -x '":x": _llm_explain'           # Explain command
bind -m vi-command -x '":c": _llm_cheatsheet'        # Cheatsheet
bind -m vi-command -x '":p": _llm_preview'           # Preview execution
bind -m vi-command -x '":h": _llm_history_search'    # History search (natural language)
bind -m vi-command -x '":?": _llm_status'            # Status/help

# Save exit status - supports both starship and vanilla bash
_llm_capture_exit() { _LLM_LAST_EXIT=''${1:-$?}; }
# Starship hook (starship passes exit code as $1)
starship_precmd_user_func="_llm_capture_exit"
# Fallback for non-starship environments
PROMPT_COMMAND='_llm_capture_exit;'"''${PROMPT_COMMAND:-}"

# Source Nix daemon if available
if [ -e ~/.nix-profile/etc/profile.d/nix-daemon.sh ]; then
  . ~/.nix-profile/etc/profile.d/nix-daemon.sh
fi

# Enable programmable completion features
if ! shopt -oq posix; then
  # Load main bash completion framework first (bash-completion@2)
  if [ -f /opt/homebrew/share/bash-completion/bash_completion ]; then
    . /opt/homebrew/share/bash-completion/bash_completion
  # Fallback to system locations
  elif [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Homebrew individual completions (macOS) - loaded after main framework
if [ -d "/opt/homebrew/etc/bash_completion.d" ] && [ -n "''${BASH_COMPLETION_VERSINFO-}" ]; then
  for completion in /opt/homebrew/etc/bash_completion.d/*; do
    [ -r "$completion" ] && . "$completion"
  done
fi

# Color support for ls
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
''