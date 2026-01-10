{ config, pkgs, lib, ... }:

let
  shellm = pkgs.rustPlatform.buildRustPackage rec {
    pname = "shellm";
    version = "0.1.0";

    src = pkgs.fetchurl {
      url = "https://git.pitaya.f5.si/pitaya1219/shellm/archive/a81b4c9.tar.gz";
      sha256 = "sha256-sIQEvnq5PkTyNYofjaYkF8mFq96WgrYNhssOgKPSkjY=";
    };

    sourceRoot = "shellm";

    cargoHash = "sha256-xy0uOm2QMEQUSoposzsF6/Ar51XiaaP+oPO4QvjxRJQ=";

    meta = with lib; {
      description = "LLM-powered shell completion tool";
      homepage = "https://git.pitaya.f5.si/pitaya1219/shellm";
      license = licenses.mit;
      maintainers = [];
    };
  };
in
{
  home.packages = [ shellm ];
}
