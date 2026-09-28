{ config, pkgs, lib, ... }:

# droid is the only aarch64-linux machine here, so like r-shibuya it has no
# shared cache that could serve it; see profiles/r-shibuya/nix-cache.nix.
#
# Unlike r-shibuya there is no daemon -- this is a single-user install, so the
# user's own nix.conf is what Nix reads, and the key and cache can live under
# $HOME rather than needing root.

let
  cache = import ../../lib/local-binary-cache.nix { inherit lib; } {
    inherit pkgs;
    nixPackage = config.nix.package;
    cacheDir = "${config.home.homeDirectory}/.cache/nix-binary-cache";
    keyFile = "${config.home.homeDirectory}/.local/share/nix/cache-priv.pem";
    publicKey = "droid-1:Yxe6Fazr+okQ6jOSX02zLIR7+Vt5+yCIjwtp+k5g2OM=";
  };
in
{
  nix.settings = cache.settings;

  home.packages = [ cache.prune ];

  # A user unit, matching who owns the cache here. r-shibuya needs a root
  # launchd daemon for the same job; see profiles/r-shibuya/nix-cache.nix.
  systemd.user.services.prune-local-binary-cache = {
    Unit.Description = "Prune the local Nix binary cache to its size budget";
    Service = {
      Type = "oneshot";
      ExecStart = "${cache.prune}/bin/prune-local-binary-cache";
    };
  };

  systemd.user.timers.prune-local-binary-cache = {
    Unit.Description = "Local Nix binary cache prune timer";
    Timer = {
      OnCalendar = "*-*-* 04:15:00";
      Persistent = true;
      AccuracySec = "10min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  home.activation.localBinaryCache =
    lib.hm.dag.entryAfter [ "writeBoundary" ] cache.checkScript;
}
