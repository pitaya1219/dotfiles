{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ];  # Agent directories are managed in agent.nix

  # Symlink .opencode/command -> .agent/commands
  home.file.".opencode/command".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/commands";
}
