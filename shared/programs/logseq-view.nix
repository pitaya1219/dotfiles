{ config, pkgs, lib, ... }:

let
  logseq-view = pkgs.rustPlatform.buildRustPackage {
    pname = "logseq-view";
    version = "0.1.0";

    src = ../../tools/logseq-view;

    cargoLock = {
      lockFile = ../../tools/logseq-view/Cargo.lock;
    };

    meta = with lib; {
      description = "TUI viewer for Logseq markdown graphs";
      mainProgram = "lqview";
      license = licenses.mit;
    };
  };
in
{
  home.packages = [ logseq-view ];
}
