{ pkgs, ... }:

# Nix's own configuration for the profiles home-manager owns outright.
#
# This takes over ~/.config/nix/nix.conf, which `task setup:nix:flake` used to
# append to line by line. That task still writes the file on a machine that has
# never switched -- flakes have to be enabled before home-manager can run at
# all -- and steps aside once this module has claimed it.
#
# nix-darwin profiles are not covered: there the same settings belong in
# /etc/nix/nix.conf, where the daemon reads them (see
# profiles/r-shibuya/darwin.nix).
{
  # Required before home-manager will generate nix.conf at all, and used only
  # for that: to run the generated file through `nix config check`. It is not
  # added to home.packages, so the Nix already installed on the machine stays
  # the one on PATH.
  nix.package = pkgs.nix;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # `extra-` rather than a plain list: cache.nixos.org and its key are
    # already Nix's built-in defaults, so naming them again only invites the
    # two copies to disagree later.
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBs="
    ];
  };
}
