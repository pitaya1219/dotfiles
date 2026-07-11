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
    # The pcloud token alone only authenticates the underlying pcloud backend — the
    # logseq data is also wrapped in an rclone crypt layer on top of that, which needs
    # its own (obscured) password pair. Pre-obscure here so the container-side fallback
    # in tasks/sync.yml can use it as-is without needing rclone/passage to do it itself.
    CRYPT_PW=$(${pkgs.rclone}/bin/rclone obscure "$(${pkgs.passage}/bin/passage show rclone/crypt/${config.home.username}/password)")
    CRYPT_PW2=$(${pkgs.rclone}/bin/rclone obscure "$(${pkgs.passage}/bin/passage show rclone/crypt/${config.home.username}/password2)")
    ${pkgs.incus}/bin/incus exec ${containerName} \
      --user "$UID_IN_CONTAINER" --group "$GID_IN_CONTAINER" \
      --cwd "${syncDir}" \
      --env "HOME=/home/${containerUser}" \
      --env "RCLONE_PCLOUD_TOKEN=$TOKEN" \
      --env "RCLONE_CRYPT_PASSWORD=$CRYPT_PW" \
      --env "RCLONE_CRYPT_PASSWORD2=$CRYPT_PW2" \
      --env "LOGSEQ_LOCAL=/home/${containerUser}/Logseq" \
      --env "LOGSEQ_REMOTE=app/logseq" \
      -- task sync:logseq
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
