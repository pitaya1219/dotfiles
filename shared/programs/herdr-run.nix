{ config, pkgs, lib, ... }:

let
  herdr-run = pkgs.writeShellApplication {
    name = "herdr-run";
    runtimeInputs = with pkgs; [ jq herdr ];
    text = builtins.readFile ../../tools/herdr-run/herdr-run.sh;
  };
in
{
  home.packages = [ herdr-run ];
}
