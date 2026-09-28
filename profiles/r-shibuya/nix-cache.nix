{ config, pkgs, lib, ... }:

# r-shibuya is the only aarch64-darwin machine here, so nothing else ever
# produces its builds and no shared cache can help it. What a local one buys is
# that `task nix:clean` and a reinstall stop meaning "build it all again" --
# mistral-vibe alone is a v8 link away from 40 minutes.
#
# Everything sits at the nix-darwin layer because substitution and the
# post-build hook both run in the daemon, which reads /etc/nix/nix.conf and not
# the user's.

let
  cache = import ../../lib/local-binary-cache.nix { inherit lib; } {
    inherit pkgs;
    nixPackage = config.nix.package;
    cacheDir = "/nix/var/cache/binary-cache";
    keyFile = "/etc/nix/cache-priv.pem";
    publicKey = "r-shibuya-1:bi5KAw53auY1SGqbT8vKUjrw+/PincT8K19uCIeKRxU=";
  };
in
{
  nix.settings = cache.settings;

  environment.systemPackages = [ cache.prune ];

  # A daemon rather than an agent: the cache is under /nix/var and the nix
  # daemon writes it as root, so a job running as r-shibuya could read the
  # directory and delete nothing in it.
  launchd.daemons.prune-local-binary-cache = {
    serviceConfig = {
      ProgramArguments = [ "${cache.prune}/bin/prune-local-binary-cache" ];
      StartCalendarInterval = [ { Hour = 4; Minute = 15; } ];
      StandardOutPath = "/var/log/prune-local-binary-cache.log";
      StandardErrorPath = "/var/log/prune-local-binary-cache.log";
    };
  };

  # postActivation rather than an earlier phase: nix.settings has to be written
  # before a failure here is worth reporting, since the message tells you what
  # the configuration expects.
  system.activationScripts.postActivation.text = lib.mkAfter cache.checkScript;
}
