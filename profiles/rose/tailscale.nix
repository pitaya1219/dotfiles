{ config, pkgs, lib, ... }:

let
  tailscale-up-script = pkgs.writeShellScript "tailscale-up" ''
    SOCKET="''${XDG_RUNTIME_DIR}/tailscale/tailscaled.sock"

    # Wait up to 30s for tailscaled socket
    ELAPSED=0
    while ! [ -S "$SOCKET" ] && [ "$ELAPSED" -lt 30 ]; do
      sleep 1
      ELAPSED=$((ELAPSED + 1))
    done
    if ! [ -S "$SOCKET" ]; then
      echo "tailscaled socket not available after 30s" >&2
      exit 1
    fi

    AUTH_KEY_FILE="''${HOME}/.config/tailscale/authkey"
    if [ -f "''${AUTH_KEY_FILE}" ]; then
      exec ${pkgs.tailscale}/bin/tailscale --socket="$SOCKET" up \
        --login-server=https://dragonfruit.f5.si \
        --advertise-routes=10.19.151.0/24,192.168.10.1/32,192.168.10.2/32 \
        --accept-routes \
        --hostname=gateway-incus \
        --auth-key="$(cat "''${AUTH_KEY_FILE}")"
    else
      exec ${pkgs.tailscale}/bin/tailscale --socket="$SOCKET" up \
        --login-server=https://dragonfruit.f5.si \
        --advertise-routes=10.19.151.0/24,192.168.10.1/32,192.168.10.2/32 \
        --accept-routes \
        --hostname=gateway-incus
    fi
  '';
in
{
  home.packages = [ pkgs.tailscale ];

  home.activation.tailscaleAuthkeyCheck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! [ -f "$HOME/.config/tailscale/authkey" ]; then
      echo "Warning: ~/.config/tailscale/authkey not found." >&2
      echo "  tailscale-up.service will not start until the key is present." >&2
      echo "  Generate with: task headscale:preauthkey:create -- server" >&2
      echo "  Then save to:  echo '<key>' > ~/.config/tailscale/authkey" >&2
    fi
  '';

  systemd.user.services.tailscaled = {
    Unit = {
      Description = "Tailscale node agent";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.local/share/tailscale %t/tailscale";
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --state=%h/.local/share/tailscale/tailscaled.state --socket=%t/tailscale/tailscaled.sock";
      Restart = "on-failure";
      RestartSec = "3s";
      AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW CAP_SYS_MODULE";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.tailscale-up = {
    Unit = {
      Description = "Tailscale client - connect to Headscale";
      After = [ "tailscaled.service" ];
      Requires = [ "tailscaled.service" ];
      ConditionPathExists = "%h/.config/tailscale/authkey";
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tailscale-up-script}";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
