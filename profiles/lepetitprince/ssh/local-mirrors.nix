{ config, pkgs, lib, ... }:

let
  rosePurpose = "lepetitprince-herdr-mirror-rose";
  aviateurPurpose = "lepetitprince-herdr-mirror-aviateur";

  roseKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519_${rosePurpose}";
  aviateurKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519_${aviateurPurpose}";

  # rose and aviateur are local accounts on this same machine (dragonfruit),
  # not separate hosts — reached over localhost, no ProxyCommand needed.
  sshConfig = ''
    # herdr-mirror only (see profiles/rose.nix and profiles/aviateur.nix for
    # the matching authorized_keys entries). Dedicated per-target keys, not
    # used for interactive login.
    Host rose-herdr-mirror
      HostName localhost
      Port 1771
      User rose
      IdentityFile ${roseKeyPath}
      IdentitiesOnly yes

    Host aviateur-herdr-mirror
      HostName localhost
      Port 1771
      User aviateur
      IdentityFile ${aviateurKeyPath}
      IdentitiesOnly yes
  '';
in
{
  imports = [ ../../../lib/passage-secrets.nix ];

  home.file.".ssh/config.d/local-mirrors".text = sshConfig;

  dotfiles.passageSecrets.lepetitprinceHerdrMirrorRose = {
    passagePath = "ssh/${rosePurpose}/private_key";
    path = roseKeyPath;
    mode = "0600";
  };

  dotfiles.passageSecrets.lepetitprinceHerdrMirrorAviateur = {
    passagePath = "ssh/${aviateurPurpose}/private_key";
    path = aviateurKeyPath;
    mode = "0600";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.d/local-mirrors" ];
  };
}
