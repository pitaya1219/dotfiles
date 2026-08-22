{ config, pkgs, lib, ... }:

let
  # Android's kernel lacks the tun module, so tailscaled here only runs in
  # userspace-networking mode with a local SOCKS5 proxy (see ../tailscale.nix).
  # ssh has to be routed through it explicitly instead of relying on OS routing.
  sshConfig = ''
    Host dragonfruit
      HostName 100.64.0.13
      Port 1771
      ProxyCommand ${pkgs.socat}/bin/socat - SOCKS5:localhost:%h:%p,socksport=1055
  '';
in
{
  home.file.".ssh/config.d/headscale".text = sshConfig;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.d/headscale" ];
  };
}
