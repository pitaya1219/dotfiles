{ config, pkgs, lib, nixpkgsConfig, netskopeCA, ... }:

{
  # nix-darwin version tracking
  system.stateVersion = 4;

  # Expose NIX_SSL_CERT_FILE in the nix-daemon's LaunchDaemon environment.
  # impureEnvVars in fixed-output derivations (e.g. fetchCargoVendor) reads
  # NIX_SSL_CERT_FILE from the *daemon* process, not from the calling user.
  # Without this, Netskope's CA cert is unknown to those builds and SSL fails.
  launchd.daemons.nix-daemon.serviceConfig.EnvironmentVariables = {
    NIX_SSL_CERT_FILE = netskopeCA;
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "r-shibuya" ];
    # Trust Netskope's combined CA bundle (standard CAs + Netskope CA) for binary cache fetches.
    ssl-cert-file = "/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem";
  };

  # Match the actual nixbld group GID on this machine (default changed from 30000 to 350)
  ids.gids.nixbld = 350;

  # Shared with mkHomeConfiguration via specialArgs — single source of truth.
  # Required at system level because home-manager.useGlobalPkgs = true makes
  # home-manager ignore its own nixpkgs.config options.
  nixpkgs.config = nixpkgsConfig;

  # Required by recent nix-darwin for primary-user options (e.g. homebrew)
  system.primaryUser = "r-shibuya";

  # User configuration
  users.users.r-shibuya.home = "/Users/r-shibuya";

  # Declarative Homebrew cask management
  homebrew = {
    enable = true;

    # Set to "uninstall" to remove casks not listed here (keeps user data),
    # or "zap" to fully remove including data. Use "none" while migrating.
    onActivation.cleanup = "none";

    # mas-cli: needed to install Mac App Store-only apps (e.g. Gapplin) declaratively.
    brews = [
      "mas"
    ];

    casks = [
      "android-studio"
      "blackhole-2ch"
      "blackhole-16ch"
      "font-hack-nerd-font"
      "google-chrome"
      "inkscape"
      "iterm2"
      "joplin"
      "karabiner-elements"
      "logseq"
      "macfuse"
      "ngrok"
      "obs"
      "rancher"
      "rnnoise"
      "visual-studio-code"
    ];
  };
}
