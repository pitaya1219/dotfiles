{ config, pkgs, lib, ... }:

{
  # nix-darwin version tracking
  system.stateVersion = 4;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "r-shibuya" ];
    # Trust Netskope's combined CA bundle (standard CAs + Netskope CA) for binary cache fetches.
    ssl-cert-file = "/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem";
  };

  # Match the actual nixbld group GID on this machine (default changed from 30000 to 350)
  ids.gids.nixbld = 350;

  # Allow unfree packages at the system level.
  # Required when home-manager.useGlobalPkgs = true — home-manager's nixpkgs.config is ignored.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
      "specs.nvim"
      "copilot.vim"
    ];

  # WORKAROUND: Skip neovim tests on macOS
  nixpkgs.config.packageOverrides = pkgs: {
    neovim-unwrapped = pkgs.neovim-unwrapped.overrideAttrs (_: {
      doCheck = false;
      doInstallCheck = false;
      checkPhase = "echo 'Tests skipped on macOS'";
    });
  };

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
