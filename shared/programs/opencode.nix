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
    # Dedicated, passphrase-less herdr-mirror keys (see profiles/*/ssh/) let
    # an agent session ssh to dragonfruit/rose/aviateur with no human in the
    # loop. Hard deny, not "ask" — last matching rule wins, so this can't be
    # shadowed by a broader allow rule added later.
    permission.bash."ssh *" = "deny";
    # See the matching note in claude-code.nix: renaming a tab is what
    # ~/.agent/conventions.md asks for, and it changes nothing but a label.
    permission.bash."herdr-tab-name *" = "allow";
  };
}
