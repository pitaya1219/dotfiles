{ config, pkgs, ... }:

let
  home = config.home.homeDirectory;

  # Logseq itself now lives inside the spaces-ryu Incus container and owns its own
  # bak/ files under its own uid — see homelab/spaces/template/configuration.nix's
  # dotfiles-sync-clone service, which keeps a sparse checkout of tasks/sync.yml +
  # tasks/sync/logseq* fresh inside the container. This host no longer touches the
  # Logseq directory's files directly (that's what caused the raw.idmap/ACL mess);
  # it only triggers the in-container sync and injects the pCloud secret per run.
  containerName = "spaces-ryu";
  containerUser = "ryu";
  syncDir = "/home/${containerUser}/.local/share/dotfiles-sync";

  # Written under homelab's monitoring tree (rather than ~/.local/share) so
  # fluent-bit's /logs/spaces/*/*.log tail input picks it up and Grafana can
  # alert on sync failures — see homelab/core/monitoring/fluent-bit.conf and
  # grafana-provisioning/alerting/logseq-sync.yaml.
  logDir = "${home}/homelab/core/monitoring/logs/spaces/${containerUser}";
  logFile = "${logDir}/logseq-sync.log";
  logFileError = "${logDir}/logseq-sync-error.log";

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
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${logDir}";
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
      # Fixed-time schedule at :20 and :50 each hour, maintaining a 15-min stagger
      # from the Mac timer (profiles/r-shibuya/logseq-sync.nix, :05/:35). This prevents
      # concurrent rclone bisync runs across Mac, rose, and Android — each run takes up
      # to 6 min, and overlapping syncs can silently lose data. Persistent and
      # RandomizedDelaySec are both left unset (systemd defaults to off for each):
      # Persistent would replay slots missed while the host was down, landing a catch-up
      # run at an arbitrary time, and RandomizedDelaySec would smear the start time —
      # either one reintroduces the overlap this stagger exists to prevent. OnBootSec is
      # gone for the same reason, at the cost of waiting up to 30 min after a boot.
      # If this timing changes, coordinate with the Mac timer in parallel.
      OnCalendar = "*:20,50";
      AccuracySec = "1min";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
