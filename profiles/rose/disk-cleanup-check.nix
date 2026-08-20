{ config, pkgs, ... }:

let
  rocketchatNotify = "${config.home.homeDirectory}/dotfiles/scripts/rocketchat-notify.sh";
  dockerBin = "${config.home.homeDirectory}/.local/bin/docker";

  # Root FS and Docker's data root can be different physical disks (they
  # were on this host -- Docker's data lived on a separate mount from
  # /nix/store). Both matter independently, so both are checked and
  # resolved dynamically rather than hardcoded, in case that changes.
  checkScript = pkgs.writeShellScript "disk-cleanup-check" ''
    set -uo pipefail

    ROOT_FS_THRESHOLD=85
    STALE_VOLUME_THRESHOLD=100

    alerts=()

    root_mount=$(${pkgs.coreutils}/bin/df --output=target /nix/store | ${pkgs.coreutils}/bin/tail -1)
    root_pct=$(${pkgs.coreutils}/bin/df --output=pcent "$root_mount" | ${pkgs.coreutils}/bin/tail -1 | ${pkgs.coreutils}/bin/tr -d ' %')
    if [ "$root_pct" -ge "$ROOT_FS_THRESHOLD" ]; then
      alerts+=("Root FS ($root_mount) at ''${root_pct}% -- run: task nix:clean (in ~/dotfiles)")
    fi

    if [ -x "${dockerBin}" ] && "${dockerBin}" info >/dev/null 2>&1; then
      docker_root=$("${dockerBin}" info --format '{{.DockerRootDir}}')
      docker_mount=$(${pkgs.coreutils}/bin/df --output=target "$docker_root" | ${pkgs.coreutils}/bin/tail -1)
      docker_pct=$(${pkgs.coreutils}/bin/df --output=pcent "$docker_mount" | ${pkgs.coreutils}/bin/tail -1 | ${pkgs.coreutils}/bin/tr -d ' %')
      if [ "$docker_pct" -ge "$ROOT_FS_THRESHOLD" ]; then
        alerts+=("Docker data root ($docker_mount) at ''${docker_pct}% -- run: docker container prune && docker volume prune -a")
      fi

      stale_volumes=$("${dockerBin}" volume ls -f name=GITEA-ACTIONS-TASK -q | ${pkgs.coreutils}/bin/wc -l)
      if [ "$stale_volumes" -ge "$STALE_VOLUME_THRESHOLD" ]; then
        alerts+=("''${stale_volumes} leaked gitea-runner job volumes -- run: docker volume ls -f name=GITEA-ACTIONS-TASK -q | xargs -r docker volume rm")
      fi
    fi

    if [ "''${#alerts[@]}" -gt 0 ]; then
      IFS=' | '
      message="''${alerts[*]}"
      unset IFS
      "${rocketchatNotify}" --agent-type disk-cleanup --type warning --priority medium --confirmation "$message"
    fi
  '';
in
{
  systemd.user.services.disk-cleanup-check = {
    Unit = {
      Description = "Check disk/docker/nix reclaim thresholds and notify if any are crossed";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${checkScript}";
    };
  };

  systemd.user.timers.disk-cleanup-check = {
    Unit = {
      Description = "Disk Cleanup Check Timer";
    };
    Timer = {
      OnCalendar = "*-*-* 08:00:00";
      Persistent = true;
      AccuracySec = "10min";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
