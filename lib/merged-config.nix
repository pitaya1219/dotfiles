{ config, lib, pkgs }:

let
  merge = pkgs.writeShellApplication {
    name = "config-merge";
    runtimeInputs = [ pkgs.yq-go pkgs.jq pkgs.coreutils ];
    text = builtins.readFile ../tools/config-merge/config-merge.sh;
  };
in
{
  inherit merge;

  # Home Manager activation entry for a config file that is Nix-generated but
  # also written by the application itself (a settings UI, a theme picker),
  # which a read-only store symlink would break. `generated` is the store file
  # to merge in, in `format` (toml, json or yaml); see
  # tools/config-merge/config-merge.sh for the merge rules. `threeWay = false`
  # keeps no state, so keys dropped from Nix are never cleaned up.
  activation = { format, target, generated, threeWay ? true }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${merge}/bin/config-merge ${format} ${generated} ${target}${
        lib.optionalString threeWay " \\\n        ${config.xdg.stateHome}/config-merge/${builtins.replaceStrings [ "/" ] [ "%" ] target}"
      }
    '';
}
