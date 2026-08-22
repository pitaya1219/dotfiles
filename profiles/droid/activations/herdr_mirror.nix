{ config, pkgs, lib, ... }:

{
  home.activation.installHerdrMirror = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="${pkgs.herdr}/bin:${pkgs.jq}/bin:$PATH"
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
