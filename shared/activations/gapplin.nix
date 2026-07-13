{ config, pkgs, lib, ... }:

{
  # mas is installed as a homebrew brew (see profiles/r-shibuya/darwin.nix); it's not a nix package.
  home.activation.installGapplin = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/opt/homebrew/bin:$PATH"
    if ! command -v mas &> /dev/null; then
      echo "mas-cli not found, skipping Gapplin install (run 'darwin-rebuild switch' first)"
    elif mas list 2>/dev/null | grep -q '^768053424 '; then
      echo "Gapplin is already installed"
    else
      echo "Installing Gapplin via mas..."
      mas get 768053424 || echo "mas get failed — sign in to the App Store and retry manually: mas get 768053424"
    fi
  '';
}
