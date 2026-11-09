# A cache on the self-hosted Attic (pitaya1219/homelab, apps/develop/attic), as
# a home-manager module:
#
#   (import ../lib/attic-cache.nix { cache = "<name>"; publicKey = "<name>:<base64>"; })
#
# Deliberately not the flake's `nixConfig`, which is where Attic's own
# onboarding guide puts extra-substituters: that applies to everyone who
# evaluates this flake, and there is no way to narrow it to the profiles a
# cache can serve. nix.settings at the import site is.
#
# Pull only. Every cache here is public-pull, so reading one needs no token, and
# what fills it is CI holding the push token. So no machine carries a
# credential for this.

{
  cache,
  # Generated server-side when the cache was created, and served at
  # https://attic.pitaya.f5.si/_api/v1/cache-config/<cache> as .public_key --
  # which is where the check below reads it back from. Recreating the cache
  # mints a new one.
  publicKey,
}:

{ pkgs, lib, ... }:

let
  endpoint = "https://attic.pitaya.f5.si";
in
{
  nix.settings = {
    # The external route only. The internal http://attic:8080 that Attic's
    # README lists next to it resolves on the gitea_gitea Docker network, which
    # is CI job containers and nothing else -- the container publishes no host
    # port, so even rose, which is the machine running Attic, has to go round
    # by the tunnel like the others.
    extra-substituters = [ "${endpoint}/${cache}" ];
    extra-trusted-public-keys = [ publicKey ];
  };

  # Nix treats a substituter whose key it does not hold as nothing worse than a
  # miss: it fetches the narinfo, fails to verify it, and moves on. So a key
  # that is wrong, stale, or -- until the cache exists -- a placeholder looks
  # exactly like a cache that is simply never warm. Ask the server which key it
  # signs with, and refuse to switch when it is not the one configured.
  #
  # Unreachable is a warning rather than a failure: this route runs through a
  # Cloudflare Tunnel, and being off the network is no reason to be unable to
  # switch.
  home.activation."atticCache-${cache}" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if config=$(${pkgs.curl}/bin/curl -sS --max-time 10 \
      "${endpoint}/_api/v1/cache-config/${cache}"); then
      # An absent cache answers 401 with a JSON error rather than a key, which
      # is the same "not the key we trust" as any other mismatch.
      served=$(${pkgs.jq}/bin/jq -r '.public_key // empty' <<< "$config") || served=""
      if [ "$served" != "${publicKey}" ]; then
        echo "attic: the ${cache} cache does not sign with the key this configuration" >&2
        echo "trusts, so nothing it serves would verify and the cache would sit unused." >&2
        echo "  configured: ${publicKey}" >&2
        echo "  served:     ''${served:-<none: no such cache, or it is not public-pull>}" >&2
        echo "Create it with \`task attic:cache:new -- ${cache}\` on the homelab host and" >&2
        echo "record the key it prints where this module is imported." >&2
        exit 1
      fi
    else
      echo "attic: could not reach ${endpoint}; left the ${cache} cache's key unchecked." >&2
    fi
  '';
}
