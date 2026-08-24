{ config, pkgs, lib, ... }:

{
  home.activation.installHerdrMirror = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # herdr plugin install shells out to git (clone) and bash (scripts/install.sh);
    # activation's PATH is minimal and doesn't carry these, so without them it
    # fails with a Rust "Os { code: 2, kind: NotFound }" — the executable itself
    # can't be found, not a plugin-side error. Confirmed live.
    export PATH="${pkgs.herdr}/bin:${pkgs.jq}/bin:${pkgs.git}/bin:${pkgs.bash}/bin:${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:$PATH"
    # `herdr plugin uninstall` leaves ~/.local/bin/herdr-mirror and its
    # managed_path behind, so a file-existence check would wrongly read
    # "already installed" — query the plugin registry itself instead.
    if herdr plugin list --json 2>/dev/null | jq -e '.result.plugins[]? | select(.plugin_id == "mirror")' >/dev/null 2>&1; then
      echo "herdr-mirror is already installed"
    else
      echo "Installing herdr-mirror plugin..."
      herdr plugin install nikok6/herdr-mirror -y || echo "herdr-mirror install failed, continuing"
      herdr server reload-config || true
    fi
  '';
}
