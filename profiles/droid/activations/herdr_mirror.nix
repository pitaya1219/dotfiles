{ config, pkgs, lib, ... }:

{
  home.activation.installHerdrMirror = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="${pkgs.herdr}/bin:$PATH"
    if [ ! -x "$HOME/.local/bin/herdr-mirror" ]; then
      echo "Installing herdr-mirror plugin..."
      ${pkgs.herdr}/bin/herdr plugin install nikok6/herdr-mirror -y || echo "herdr-mirror install failed, continuing"
      ${pkgs.herdr}/bin/herdr server reload-config || true
    else
      echo "herdr-mirror is already installed"
    fi
  '';
}
