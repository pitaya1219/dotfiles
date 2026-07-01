{ config, pkgs, lib, ... }:

let
  netskopeCA = "/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem";
in
{
  # Set NODE_EXTRA_CA_CERTS at login so Node.js processes trust the Netskope CA.
  # launchctl setenv propagates the env var to all processes spawned by this
  # user's launchd session after this agent runs.
  launchd.agents.node-extra-ca-certs = {
    enable = true;
    config = {
      Label = "com.local.node-extra-ca-certs";
      ProgramArguments = [
        "/bin/launchctl" "setenv"
        "NODE_EXTRA_CA_CERTS"
        netskopeCA
      ];
      RunAtLoad = true;
    };
  };

  # Add Netskope root CAs to the login keychain with explicit SSL trust.
  # NODE_EXTRA_CA_CERTS covers Node.js's own TLS stack, but Electron apps
  # (e.g. Logseq) use Chromium's network stack for some requests, which reads
  # from the macOS keychain instead. Without this, the mermaid plugin's GitHub
  # release check fails with "self signed certificate in certificate chain".
  home.activation.trustNetskopeCerts = lib.hm.dag.entryAfter ["writeBoundary"] ''
    _cert_bundle="${netskopeCA}"
    _keychain="$HOME/Library/Keychains/login.keychain-db"

    if [ -f "$_cert_bundle" ] && [ -f "$_keychain" ]; then
      ${pkgs.gawk}/bin/awk '
        /-----BEGIN CERTIFICATE-----/ { c++; f = sprintf("/tmp/.nscert-%d.pem", c) }
        c { print > f }
        /-----END CERTIFICATE-----/  { close(f) }
      ' "$_cert_bundle"

      for _cert in /tmp/.nscert-*.pem; do
        [ -f "$_cert" ] || continue
        _subj=$(/usr/bin/openssl x509 -in "$_cert" -noout -subject 2>/dev/null) || { rm -f "$_cert"; continue; }
        if echo "$_subj" | /usr/bin/grep -qi "netskope\|goskope"; then
          /usr/bin/security add-trusted-cert \
            -r trustRoot \
            -k "$_keychain" \
            "$_cert" 2>/dev/null || true
        fi
        rm -f "$_cert"
      done
    fi
  '';
}
