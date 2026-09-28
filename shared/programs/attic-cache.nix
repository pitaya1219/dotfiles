{ pkgs, lib, ... }:

# The self-hosted Attic binary cache (pitaya1219/homelab, apps/develop/attic)
# for the profiles that can actually share one.
#
# Imported by rose, lepetitprince and aviateur -- every x86_64-linux profile
# here -- and by nothing else. r-shibuya and droid are each the only machine on
# their architecture, so no shared cache can ever serve them; they keep a local
# one instead (lib/local-binary-cache.nix).
#
# Deliberately not the flake's `nixConfig`, which is where Attic's own
# onboarding guide puts extra-substituters: that applies to everyone who
# evaluates this flake, r-shibuya and droid included, and there is no way to
# narrow it to three of five profiles. nix.settings at the import site is.
#
# Pull only. The cache is public-pull, so reading it needs no token, and what
# fills it is .gitea/workflows/warm-attic-cache.yml -- CI on the act-runner,
# x86_64-linux like these three, holding the push token as an Actions secret.
# So none of the three machines carries a credential for this.

let
  cache = "dotfiles";
  endpoint = "https://attic.pitaya.f5.si";

  # Generated server-side when the cache was created, and served at
  # https://attic.pitaya.f5.si/_api/v1/cache-config/dotfiles as .public_key --
  # which is where the check below reads it back from. Recreating the cache
  # mints a new one.
  publicKey = "${cache}:L3RnPt1e0iuxa/mSzKGepMXh13eRa03sXOYfNKOnvhM=";
in
{
  nix.settings = {
    # The external route only. The internal http://attic:8080 that Attic's
    # README lists next to it resolves on the gitea_gitea Docker network, which
    # is CI job containers and nothing else -- the container publishes no host
    # port, so even rose, which is the machine running Attic, has to go round
    # by the tunnel like the other two.
    extra-substituters = [ "${endpoint}/${cache}" ];
    extra-trusted-public-keys = [ publicKey ];
  };

  # Nix treats a substituter whose key it does not hold as nothing worse than a
  # miss: it fetches the narinfo, fails to verify it, and moves on. So a key
  # that is wrong, stale, or -- until the cache exists -- a placeholder looks
  # exactly like a cache that is simply never warm. Ask the server which key it
  # signs with, and refuse to switch when it is not the one above.
  #
  # Unreachable is a warning rather than a failure: this route runs through a
  # Cloudflare Tunnel, and being off the network is no reason to be unable to
  # switch.
  home.activation.atticCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
        echo "record the key it prints in shared/programs/attic-cache.nix." >&2
        exit 1
      fi
    else
      echo "attic: could not reach ${endpoint}; left the ${cache} cache's key unchecked." >&2
    fi
  '';
}
