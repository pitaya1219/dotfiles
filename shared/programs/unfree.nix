{ additionalPackages ? [] }:

{ config, pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg:
    let
      basePackages = [ "claude-code" "specs.nvim" ];
      allPackages = basePackages ++ additionalPackages;
    in
    builtins.elem (lib.getName pkg) allPackages;
}
