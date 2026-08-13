{ config, pkgs, lib, ... }:

{
  launchd.agents.logseq-sync = {
    enable = true;
    config = {
      Label = "com.logseq.sync";
      ProgramArguments = [
        "${pkgs.go-task}/bin/task"
        "-d"
        "${config.home.homeDirectory}/dotfiles"
        "sync:logseq"
      ];
      EnvironmentVariables = {
        PATH = lib.concatStringsSep ":" [
          "${config.home.homeDirectory}/.nix-profile/bin"
          "/etc/profiles/per-user/${config.home.username}/bin"
          "/run/current-system/sw/bin"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
        LOGSEQ_LOCAL = "${config.home.homeDirectory}/personal/app/logseq";
        LOGSEQ_REMOTE = "app/logseq";
        DOTFILES_DIR = "${config.home.homeDirectory}/dotfiles";
        HOME = config.home.homeDirectory;
      };
      # Fixed-time schedule at :05 and :35 each hour (every 30 min on staggered offset).
      # Coordinates with rose (profiles/rose/logseq-sync.nix, :20/:50) to prevent concurrent
      # rclone bisync runs across Mac, rose, and Android. Each sync takes up to 6 min; the
      # 15-min stagger keeps execution windows from overlapping and causing lost updates.
      # IMPORTANT: If this timing changes, update profiles/rose/logseq-sync.nix in parallel.
      StartCalendarInterval = [ { Minute = 5; } { Minute = 35; } ];
      # RunAtLoad is deliberately off: it would fire a sync at login and on every
      # home-manager switch, i.e. outside the staggered slots and possibly on top
      # of rose's run — the one hole the fixed schedule above is meant to close.
      # Cost is waiting until the next :05/:35 after login, the same trade rose
      # makes by dropping OnBootSec.
      RunAtLoad = false;
      StandardOutPath = "${config.home.homeDirectory}/.local/share/logseq-sync.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/share/logseq-sync-error.log";
    };
  };
}
