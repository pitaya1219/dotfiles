{ config, pkgs, lib, ... }:

let
  purpose = "droid-herdr-mirror";
  dragonfruitMirrorKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519_${purpose}";

  roseMirrorKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519_droid-herdr-mirror-rose";
  aviateurMirrorKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519_droid-herdr-mirror-aviateur";

  # rose/aviateur are reached as "localhost" from dragonfruit's end of the
  # ProxyJump, which is a host identity droid has never seen before — but
  # it's the exact same sshd/host key as "dragonfruit"/"dragonfruit-herdr-mirror"
  # (100.64.0.2:1771), just under a different apparent name. Pin that known
  # key explicitly (scoped to just these two aliases) instead of either
  # trusting on first use or leaving BatchMode to reject it outright.
  dragonfruitLoopbackKnownHosts = "${config.home.homeDirectory}/.ssh/known_hosts.d/dragonfruit-loopback";

  # Android's kernel lacks the tun module, so tailscaled here only runs in
  # userspace-networking mode with a local SOCKS5 proxy (see ../tailscale.nix).
  # ssh has to be routed through it explicitly instead of relying on OS routing.
  sshConfig = ''
    Host dragonfruit
      HostName 100.64.0.2
      Port 1771
      ProxyCommand ${pkgs.socat}/bin/socat - SOCKS5:localhost:%h:%p,socksport=1055

    # herdr-mirror only (see profiles/lepetitprince.nix for the matching
    # authorized_keys entry). Kept as its own alias, not folded into
    # "dragonfruit" above, so this dedicated key is never what an
    # interactive "ssh dragonfruit" picks up.
    Host dragonfruit-herdr-mirror
      HostName 100.64.0.2
      Port 1771
      ProxyCommand ${pkgs.socat}/bin/socat - SOCKS5:localhost:%h:%p,socksport=1055
      User lepetitprince
      IdentityFile ${dragonfruitMirrorKeyPath}
      IdentitiesOnly yes

    # rose and aviateur are local accounts on dragonfruit, not separately
    # network-reachable, and sshd there only accepts them from its own
    # loopback (see profiles/rose.nix / profiles/aviateur.nix and
    # sshd_config's Match User rose,aviateur rule). ProxyJump through
    # dragonfruit so the final hop originates from its loopback; each still
    # authenticates with its own dedicated key, not lepetitprince's — a
    # compromised droid then only ever exposes droid's own keys, never
    # lepetitprince's.
    Host rose-herdr-mirror
      HostName localhost
      Port 1771
      User rose
      ProxyJump lepetitprince@dragonfruit-herdr-mirror
      IdentityFile ${roseMirrorKeyPath}
      IdentitiesOnly yes
      UserKnownHostsFile ${dragonfruitLoopbackKnownHosts}

    Host aviateur-herdr-mirror
      HostName localhost
      Port 1771
      User aviateur
      ProxyJump lepetitprince@dragonfruit-herdr-mirror
      IdentityFile ${aviateurMirrorKeyPath}
      IdentitiesOnly yes
      UserKnownHostsFile ${dragonfruitLoopbackKnownHosts}
  '';
in
{
  imports = [ ../../../lib/passage-secrets.nix ];

  home.file.".ssh/config.d/headscale".text = sshConfig;

  # Not actually secret (it's the server's public host key, the whole point
  # of known_hosts is that this is meant to be known) — sourced from passage
  # anyway for consistency with the rest of this file: one mechanism for all
  # key material, regardless of which half is sensitive. Adding a second
  # host here later is a one-line addition to this list, no further edits.
  dotfiles.passageKnownHosts."dragonfruit-loopback" = [
    {
      purpose = "dragonfruit-loopback";
      passagePath = "ssh/dragonfruit-loopback/known_hosts";
    }
  ];

  # Dedicated, passphrase-less key scoped to this one connection (herdr-mirror
  # runs as an unattended daemon, so it can't wait on an agent). Not reused
  # for interactive login — see profiles/lepetitprince.nix for the matching
  # authorized_keys entry.
  dotfiles.passageSecrets.droidHerdrMirror = {
    passagePath = "ssh/${purpose}/private_key";
    path = dragonfruitMirrorKeyPath;
    mode = "0600";
  };

  dotfiles.passageSecrets.droidHerdrMirrorRose = {
    passagePath = "ssh/droid-herdr-mirror-rose/private_key";
    path = roseMirrorKeyPath;
    mode = "0600";
  };

  dotfiles.passageSecrets.droidHerdrMirrorAviateur = {
    passagePath = "ssh/droid-herdr-mirror-aviateur/private_key";
    path = aviateurMirrorKeyPath;
    mode = "0600";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.d/headscale" ];
  };
}
