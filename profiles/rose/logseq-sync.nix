{ config, pkgs, ... }:

let
  home = config.home.homeDirectory;
  dotfilesDir = "${home}/dotfiles";
  logseqLocal = "${home}/homelab/spaces/data/ryu/logseq";
  logseqRemote = "app/logseq";
  logFile = "${home}/.local/share/logseq-sync.log";
  logFileError = "${home}/.local/share/logseq-sync-error.log";
in
{
  home.packages = [ pkgs.go-task ];

  systemd.user.services.logseq-sync = {
    Unit = {
      Description = "Logseq Sync Service";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.go-task}/bin/task sync:logseq";
      Environment = [
        "PATH=${home}/.nix-profile/bin:/usr/bin:/bin"
        "LOGSEQ_LOCAL=${logseqLocal}"
        "LOGSEQ_REMOTE=${logseqRemote}"
        "DOTFILES_DIR=${dotfilesDir}"
        "LOG_FILE=${logFile}"
      ];
      WorkingDirectory = dotfilesDir;
      StandardOutput = "append:${logFile}";
      StandardError = "append:${logFileError}";
    };
  };

  systemd.user.timers.logseq-sync = {
    Unit = {
      Description = "Logseq Sync Timer";
    };
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      AccuracySec = "1min";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
