{ config, pkgs, lib, ... }:

let
  # Same incus-exec-from-host pattern as ./logseq-sync.nix, reused for the
  # same reason: touching the container's files directly from the host runs
  # into the raw.idmap/ACL mismatch that file's comment describes. The host
  # only triggers the sync and injects pCloud secrets; the actual staging
  # and upload run inside the container as its own user, via `task
  # sync:hermes` from the same sparse dotfiles checkout logseq-sync already
  # relies on (homelab's spaces/template/configuration.nix dotfiles-sync-clone
  # service keeps tasks/sync.yml + tasks/sync/* fresh there).
  logDir = "${config.home.homeDirectory}/homelab/core/monitoring/logs/spaces";

  mkHermesBackup = { containerUser, onCalendar }:
    let
      containerName = "spaces-${containerUser}";
      syncDir = "/home/${containerUser}/.local/share/dotfiles-sync";
      containerLogDir = "${logDir}/${containerUser}";
      logFile = "${containerLogDir}/hermes-backup.log";
      logFileError = "${containerLogDir}/hermes-backup-error.log";

      triggerScript = pkgs.writeShellScript "hermes-backup-trigger-${containerUser}" ''
        set -euo pipefail
        UID_IN_CONTAINER=$(${pkgs.incus}/bin/incus exec ${containerName} -- id -u ${containerUser})
        GID_IN_CONTAINER=$(${pkgs.incus}/bin/incus exec ${containerName} -- id -g ${containerUser})
        TOKEN=$(${pkgs.passage}/bin/passage show rclone/pcloud/${config.home.username}/token)
        CRYPT_PW=$(${pkgs.rclone}/bin/rclone obscure "$(${pkgs.passage}/bin/passage show rclone/crypt/${config.home.username}/password)")
        CRYPT_PW2=$(${pkgs.rclone}/bin/rclone obscure "$(${pkgs.passage}/bin/passage show rclone/crypt/${config.home.username}/password2)")
        ${pkgs.incus}/bin/incus exec ${containerName} \
          --user "$UID_IN_CONTAINER" --group "$GID_IN_CONTAINER" \
          --cwd "${syncDir}" \
          --env "HOME=/home/${containerUser}" \
          --env "RCLONE_PCLOUD_TOKEN=$TOKEN" \
          --env "RCLONE_CRYPT_PASSWORD=$CRYPT_PW" \
          --env "RCLONE_CRYPT_PASSWORD2=$CRYPT_PW2" \
          --env "HERMES_REMOTE=app/hermes/${containerUser}" \
          -- task sync:hermes
      '';
    in {
      systemd.user.services."hermes-backup-${containerUser}" = {
        Unit = {
          Description = "Trigger hermes state backup inside the ${containerName} container";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${containerLogDir}";
          ExecStart = "${triggerScript}";
          StandardOutput = "append:${logFile}";
          StandardError = "append:${logFileError}";
        };
      };

      systemd.user.timers."hermes-backup-${containerUser}" = {
        Unit.Description = "Hermes Backup Timer (${containerUser})";
        Timer = {
          OnCalendar = onCalendar;
          AccuracySec = "5min";
          # Safe here unlike logseq-sync's timer, which deliberately leaves
          # this unset: this is a single-writer, one-way push (the container
          # is the only source), so a catch-up run after downtime can't
          # collide with a peer the way a missed Logseq bisync slot could.
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
in
  lib.mkMerge [
    (mkHermesBackup { containerUser = "ryu"; onCalendar = "03:15"; })
    (mkHermesBackup { containerUser = "family"; onCalendar = "03:45"; })
  ]
