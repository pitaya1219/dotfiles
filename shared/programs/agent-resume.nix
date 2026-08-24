{ config, pkgs, lib, ... }:

let
  agent-resume = pkgs.writeShellApplication {
    name = "agent-resume";
    runtimeInputs = with pkgs; [ fzf jq herdr ];
    text = builtins.readFile ../../tools/agent-resume/agent-resume.sh;
  };
in
{
  home.packages = [ agent-resume ];
}
