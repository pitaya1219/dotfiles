{ config, pkgs, ... }:

{
  imports = [
    # ../shared/activations/ollama.nix
  ];

  home.packages = with pkgs; [
    jq
    ollama
  ];
}
