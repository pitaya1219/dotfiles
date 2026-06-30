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
      StartInterval = 1800;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.local/share/logseq-sync.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/share/logseq-sync-error.log";
    };
  };
}
