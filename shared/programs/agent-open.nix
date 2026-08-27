{ config, pkgs, lib, ... }:

let
  agent-open = pkgs.writeShellApplication {
    name = "agent-open";
    # openssh is what the remote half of the picker rides on; the rest of the
    # host list comes from herdr-mirror's own config, so nothing here has to
    # know which hosts exist.
    runtimeInputs = with pkgs; [ fzf jq herdr git openssh ];
    text = builtins.readFile ../../tools/agent-open/agent-open.sh;
  };
in
{
  home.packages = [ agent-open ];
}
