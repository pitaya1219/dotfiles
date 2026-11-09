{ pkgs, ... }:

# The Logseq CLI, which droid cannot build: the build takes the Linux Terminal
# VM down. homelab's nix runner builds it for aarch64-linux and pushes it to the
# logseq cache (homelab apps/knowledge/logseq/clients/docs/cli.md), so this
# machine only substitutes it.

{
  imports = [
    ../../shared/programs/logseq-db.nix
    (import ../../lib/attic-cache.nix {
      cache = "logseq";
      publicKey = "logseq:TB8aPckNArEe7t8Kn8DC0ix/ulP/FEUuZdyDbzDUfzs=";
    })
  ];

  # Evaluating the CLI imports from x86_64-linux derivations (opam-nix's
  # project resolution), which droid can only substitute. Some are
  # runCommandLocal, whose allowSubstitutes = false would otherwise make Nix
  # try to build them here and fail on the platform.
  nix.settings.always-allow-substitutes = true;

  programs.logseq-db = {
    enable = true;
    cliPackage = pkgs.logseq-cli;
  };
}
