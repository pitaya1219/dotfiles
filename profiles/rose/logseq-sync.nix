{ config, pkgs, ... }:

let
  home = config.home.homeDirectory;
  logFile = "${home}/.local/share/logseq-sync.log";
  logFileError = "${home}/.local/share/logseq-sync-error.log";

  # Logseq itself now lives inside the spaces-ryu Incus container and owns its own
  # bak/ files under its own uid — see homelab/spaces/template/configuration.nix's
  # dotfiles-sync-clone service, which keeps a sparse checkout of tasks/sync.yml +
  # tasks/sync/logseq* fresh inside the container. This host no longer touches the
  # Logseq directory's files directly (that's what caused the raw.idmap/ACL mess);
  # it only triggers the in-container sync and injects the pCloud secret per run.
  containerName = "spaces-ryu";
  containerUser = "ryu";
  syncDir = "/home/${containerUser}/.local/share/dotfiles-sync";

  triggerScript = pkgs.writeShellScript "logseq-sync-trigger" ''
    set -euo pipefail
    UID_IN_CONTAINER=$(${pkgs.incus}/bin/incus exec ${containerName} -- id -u ${containerUser})
    GID_IN_CONTAINER=$(${pkgs.incus}/bin/incus exec ${containerName} -- id -g ${containerUser})
    TOKEN=$(${pkgs.passage}/bin/passage show rclone/pcloud/${config.home.username}/token)
    ${pkgs.incus}/bin/incus exec ${containerName} \
      --user "$UID_IN_CONTAINER" --group "$GID_IN_CONTAINER" \
      --cwd "${syncDir}" \
      --env "HOME=/home/${containerUser}" \
      --env "RCLONE_PCLOUD_TOKEN=$TOKEN" \
      --env "LOGSEQ_LOCAL=/home/${containerUser}/Logseq" \
      --env "LOGSEQ_REMOTE=app/logseq" \
      -- task sync:logseq -- --resync
  '';
in
{
  systemd.user.services.logseq-sync = {
    Unit = {
      Description = "Trigger logseq sync inside the spaces-ryu container";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${triggerScript}";
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
