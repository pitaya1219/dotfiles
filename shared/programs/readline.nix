{ config, pkgs, lib, ... }:

{
  programs.readline = {
    enable = true;
    extraConfig = ''
      # vim key-bind for bash
      set show-mode-in-prompt on
      # same as `set -o vi` in bashrc 
      set editing-mode vi

      $if term=linux
        set vi-ins-mode-string "\1\e[?0c\2"
        set vi-cmd-mode-string "\1\e[?8c\2"
      $else
        set vi-ins-mode-string "\1\e[34;1m\2ins \1\e[0m\e[4 q\2"
        set vi-cmd-mode-string "\1\e[31;5;1m\2cmd \1\e[0m\e[1 q\2"
      $endif

      $if mode=vi
      set keymap vi-command
      # these are for vi-command mode
      "\e[A": history-search-backward
      "\e[B": history-search-forward
      j:history-search-forward
      k:history-search-backward
      set keymap vi-insert
      # these are for vi-insert mode
      "\e[A": history-search-backward
      "\e[B": history-search-forward
      "jj": vi-movement-mode
      $endif
    '';
  };
}
