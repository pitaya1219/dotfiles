{ config, pkgs, lib, ... }:

let
  purpose = "droid-herdr-mirror";
  dragonfruitMirrorKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519_${purpose}";

  # Android's kernel lacks the tun module, so tailscaled here only runs in
  # userspace-networking mode with a local SOCKS5 proxy (see ../tailscale.nix).
  # ssh has to be routed through it explicitly instead of relying on OS routing.
  sshConfig = ''
    Host dragonfruit
      HostName 100.64.0.13
      Port 1771
      ProxyCommand ${pkgs.socat}/bin/socat - SOCKS5:localhost:%h:%p,socksport=1055
      IdentityFile ${dragonfruitMirrorKeyPath}
      IdentitiesOnly yes
  '';
in
{
  imports = [ ../../../lib/passage-secrets.nix ];

  home.file.".ssh/config.d/headscale".text = sshConfig;

  # Dedicated, passphrase-less key scoped to this one connection (herdr-mirror
  # runs as an unattended daemon, so it can't wait on an agent). Not reused
  # for interactive login — see profiles/lepetitprince.nix for the matching
  # authorized_keys entry.
  dotfiles.passageSecrets.droidHerdrMirror = {
    passagePath = "ssh/${purpose}/private_key";
    path = dragonfruitMirrorKeyPath;
    mode = "0600";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.d/headscale" ];
  };
}
