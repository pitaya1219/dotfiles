{ config, pkgs, lib, ... }:

{
  home.activation.installProtonPassCli = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="${pkgs.curl}/bin:${pkgs.gawk}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
    if ! command -v proton-pass &> /dev/null; then
      echo "Installing proton-pass-cli..."
      ${pkgs.curl}/bin/curl -fsSL https://proton.me/download/pass-cli/install.sh | ${pkgs.bash}/bin/bash
    else
      echo "proton-pass-cli is already installed"
    fi
  '';
}
