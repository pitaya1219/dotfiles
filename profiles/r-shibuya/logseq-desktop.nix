{ config, pkgs, lib, ... }:

# Logseq DB: the Logseq 2.0 desktop patched to sign in against the homelab
# Zitadel and sync to the self-hosted server (pitaya1219/homelab,
# apps/knowledge/logseq). It runs beside the brew cask's Logseq 0.10.
#
# Homelab CI publishes every build as logseq-desktop/<version>-<store hash> and
# never replaces one; its desktop job prints the url and hash to put here.

let
  version = "2.0.2-b9yqa0nd";

  app = pkgs.stdenvNoCC.mkDerivation {
    pname = "logseq-db";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://git.pitaya.f5.si/api/packages/pitaya1219/generic/logseq-desktop/${version}/Logseq-DB-darwin-arm64.zip";
      hash = "sha256-8H5oHxrGXfcgjFAodX10PumzPFxhs7Ee7TfxDrOSGZw=";
    };

    nativeBuildInputs = [ pkgs.unzip ];

    # The zip is unsigned, since its asar was rewritten. Apple's codesign is the
    # one that drops upstream's hardened runtime while re-signing; under it,
    # library validation refuses an ad hoc process its Electron Framework.
    # /usr/bin is reachable because this machine builds without the Nix
    # sandbox; with it on, the build needs /usr/bin/codesign in the daemon's
    # allowed-impure-host-deps and __impureHostDeps here.

    unpackPhase = ''
      unzip -q $src
    '';

    installPhase = ''
      mkdir -p $out/Applications
      mv "Logseq DB.app" $out/Applications/
      /usr/bin/codesign --force --deep --sign - "$out/Applications/Logseq DB.app"
    '';

    # Anything fixup rewrites after signing breaks the signature.
    dontFixup = true;
  };

  # The keys of the web app's window.LOGSEQ_CONFIG (homelab
  # apps/knowledge/logseq/clients/docs/configuration.md). The client id is
  # added at activation from passage.
  selfHosting = {
    oidcIssuer = "https://auth.pitaya.f5.si";
    oidcDeviceAuthorizationUrl = "https://auth.pitaya.f5.si/oauth/v2/device_authorization";
    oidcTokenUrl = "https://auth.pitaya.f5.si/oauth/v2/token";
    syncUrl = "https://logseq-sync.pitaya.f5.si";
  };
  clientIdPassage = "homelab/zitadel/apps/logseq/client/id";
in
{
  home.packages = [ app ];

  # Read once at start-up: restart Logseq DB after a change.
  home.activation.logseqDbSelfHosting = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dir="$HOME/Library/Application Support/Logseq DB"
    if client_id=$(${pkgs.passage}/bin/passage show ${clientIdPassage}) && [ -n "$client_id" ]; then
      install -d "$dir"
      ${pkgs.jq}/bin/jq -n --arg id "$client_id" --argjson base ${lib.escapeShellArg (builtins.toJSON selfHosting)} \
        '$base + {oidcClientId: $id}' > "$dir/self-hosting.json.tmp"
      mv "$dir/self-hosting.json.tmp" "$dir/self-hosting.json"
    else
      echo "logseq-desktop: could not read ${clientIdPassage} from passage; left self-hosting.json as it was." >&2
    fi
  '';
}
