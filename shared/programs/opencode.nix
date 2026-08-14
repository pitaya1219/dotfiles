{ config, pkgs, lib, ... }:

{
  imports = [ ./agent.nix ];  # Agent directories are managed in agent.nix

  # Symlink .opencode/command -> .agent/commands
  home.file.".opencode/command".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agent/commands";

  # Global config (`opencode debug paths` reports ~/.config/opencode as the
  # config dir). instructions takes a list, so the shared conventions are
  # referenced by path and further instruction files can just be appended.
  home.file.".config/opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    instructions = [ "${config.home.homeDirectory}/.agent/conventions.md" ];
  };
}
