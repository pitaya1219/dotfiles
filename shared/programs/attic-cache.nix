# The Attic cache of this repository's own builds, for the profiles that can
# share one.
#
# Imported by rose, lepetitprince and aviateur -- every x86_64-linux profile
# here -- and by nothing else. r-shibuya and droid are each the only machine on
# their architecture, so this cache, filled by .gitea/workflows/warm-attic-cache.yml
# on the x86_64-linux act-runner, can never serve them; they keep a local one
# instead (lib/local-binary-cache.nix).

import ../../lib/attic-cache.nix {
  cache = "dotfiles";
  publicKey = "dotfiles:L3RnPt1e0iuxa/mSzKGepMXh13eRa03sXOYfNKOnvhM=";
}
