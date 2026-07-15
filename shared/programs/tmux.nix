{ config, pkgs, lib, ... }:

{
  programs.tmux = {
    enable = true;
    escapeTime = 10;
    focusEvents = true;
    historyLimit = 10000;
    mouse = true;
    terminal = "tmux-256color";
    keyMode = "vi";
    plugins = with pkgs.tmuxPlugins; [
      resurrect
      continuum
    ];
    extraConfig = ''
      set -ag terminal-overrides ",xterm-256color:RGB"

      # auto restore tmux
      set -g @continuum-restore 'on'

      set -g status-style 'bg=#5f0000,fg=#949494'

      # Load profile-specific configuration if it exists
      if-shell 'test -f ~/.config/tmux/override.conf' 'source ~/.config/tmux/override.conf'
    '';
  };
}
