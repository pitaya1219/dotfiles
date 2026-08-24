{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.passageSecrets;
  authorizedKeysCfg = config.dotfiles.passageAuthorizedKeys;
  knownHostsCfg = config.dotfiles.passageKnownHosts;
in
{
  options.dotfiles.passageSecrets = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        passagePath = mkOption {
          type = types.str;
          description = "Path within the passage store.";
        };
        path = mkOption {
          type = types.str;
          description = "Destination file the secret is materialized to.";
        };
        mode = mkOption {
          type = types.str;
          default = "0600";
        };
      };
    });
    default = { };
    description = ''
      Secrets sourced from passage and written out as plain files at
      home-manager activation. The value never touches the Nix store or
      git — only the passage path and destination path (both non-secret)
      end up in the built activation script.
    '';
  };

  options.dotfiles.passageAuthorizedKeys = mkOption {
    type = types.listOf (types.submodule {
      options = {
        purpose = mkOption {
          type = types.str;
          description = "Label for what this key is for, e.g. \"droid-herdr-mirror\". Written as a comment above the key.";
        };
        passagePath = mkOption {
          type = types.str;
          description = "Passage path holding this one public key line.";
        };
      };
    });
    default = [ ];
    description = ''
      Public keys to authorize, one passage entry per purpose, concatenated
      into ~/.ssh/authorized_keys at activation. Adding or dropping a device
      is a one-line change here plus one passage entry — no shared blob to
      hand-edit. ~/.ssh/authorized_keys is fully owned by this option: any
      key present on disk but not listed here is removed on activation.
    '';
  };

  options.dotfiles.passageKnownHosts = mkOption {
    type = types.attrsOf (types.listOf (types.submodule {
      options = {
        purpose = mkOption {
          type = types.str;
          description = "Label for what this key is for, e.g. \"dragonfruit-loopback\". Written as a comment above the entry.";
        };
        passagePath = mkOption {
          type = types.str;
          description = "Passage path holding this one \"host key\" known_hosts line.";
        };
      };
    }));
    default = { };
    description = ''
      known_hosts entries sourced from passage. Not secret — it's the
      server's own public host key — but kept in passage anyway for the
      same one-mechanism-for-all-key-material reason as passageSecrets.
      Each attrset key names a destination file under
      ~/.ssh/known_hosts.d/<name>, concatenated from its list of entries;
      point a Host's UserKnownHostsFile at ~/.ssh/known_hosts.d/<name> to
      use it. Adding an entry to an existing file is a one-line change
      here — no separate UserKnownHostsFile edit needed.
    '';
  };

  config.home.activation = mkMerge [
    (mapAttrs'
      (name: secret:
        nameValuePair "passageSecret-${name}" (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            install -d -m 700 "$(dirname ${escapeShellArg secret.path})"
            ${pkgs.passage}/bin/passage show ${escapeShellArg secret.passagePath} > ${escapeShellArg secret.path}
            chmod ${secret.mode} ${escapeShellArg secret.path}
          ''
        ))
      cfg)
    (mkIf (authorizedKeysCfg != [ ]) {
      passageAuthorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        install -d -m 700 "$HOME/.ssh"
        : > "$HOME/.ssh/authorized_keys"
        ${concatMapStrings (k: ''
          echo "# ${k.purpose}" >> "$HOME/.ssh/authorized_keys"
          ${pkgs.passage}/bin/passage show ${escapeShellArg k.passagePath} >> "$HOME/.ssh/authorized_keys"
        '') authorizedKeysCfg}
        chmod 0600 "$HOME/.ssh/authorized_keys"
      '';
    })
    (mapAttrs'
      (name: entries:
        nameValuePair "passageKnownHosts-${name}" (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            install -d -m 700 "$HOME/.ssh/known_hosts.d"
            dest="$HOME/.ssh/known_hosts.d/${name}"
            : > "$dest"
            ${concatMapStrings (e: ''
              echo "# ${e.purpose}" >> "$dest"
              ${pkgs.passage}/bin/passage show ${escapeShellArg e.passagePath} >> "$dest"
            '') entries}
            chmod 0644 "$dest"
          ''
        ))
      knownHostsCfg)
  ];
}
