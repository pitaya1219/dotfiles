{ config, pkgs, lib, ... }:

{
  options.dotfiles.protonPass.caCertFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "CA bundle path for curl during proton-pass-cli install (e.g. corporate proxy cert).";
  };

  config.home.activation.installProtonPassCli = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="${pkgs.curl}/bin:${pkgs.gawk}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
    ${lib.optionalString (config.dotfiles.protonPass.caCertFile != null) ''
      export CURL_CA_BUNDLE="${config.dotfiles.protonPass.caCertFile}"
      export SSL_CERT_FILE="${config.dotfiles.protonPass.caCertFile}"
    ''}
    if ! command -v proton-pass &> /dev/null; then
      echo "Installing proton-pass-cli..."
      ${pkgs.curl}/bin/curl -fsSL https://proton.me/download/pass-cli/install.sh | ${pkgs.bash}/bin/bash
    else
      echo "proton-pass-cli is already installed"
    fi
  '';
}
