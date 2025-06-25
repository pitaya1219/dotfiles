''
# Auto-completion
if [ -f /etc/bash_completion ]; then
  . /etc/bash_completion
fi

# Homebrew completions (macOS)
if [ -d "/opt/homebrew/etc/bash_completion.d" ]; then
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

# Enable programmable completion features
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
''