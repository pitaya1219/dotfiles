{ config, pkgs, lib, ... }:

let
  agent-open = pkgs.writeShellApplication {
    name = "agent-open";
    runtimeInputs = with pkgs; [ fzf jq herdr git ];
    text = builtins.readFile ../../tools/agent-open/agent-open.sh;
  };
in
{
  home.packages = [ agent-open ];
}
