''
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