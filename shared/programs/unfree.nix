{ additionalPackages ? [] }:

{ config, pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg:
    let
      basePackages = [ "claude-code" ];
      allPackages = basePackages ++ additionalPackages;
    in
    builtins.elem (lib.getName pkg) allPackages;
}
