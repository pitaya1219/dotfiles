{ config, pkgs, lib, ... }:
{
  options.local.shellm.extraBuildAttrs = lib.mkOption {
    type = lib.types.attrs;
    default = {};
  };

  config.home.packages =
    let
      shellm = pkgs.rustPlatform.buildRustPackage (rec {
        pname = "shellm";
        version = "0.1.0";

        src = pkgs.fetchurl {
          url = "https://git.pitaya.f5.si/pitaya1219/shellm/archive/a81b4c9.tar.gz";
          sha256 = "sha256-sIQEvnq5PkTyNYofjaYkF8mFq96WgrYNhssOgKPSkjY=";
        };

        sourceRoot = "shellm";

        cargoHash = "sha256-xy0uOm2QMEQUSoposzsF6/Ar51XiaaP+oPO4QvjxRJQ=";

        # WORKAROUND: coreutils 9.x cp uses fchmodat(AT_FDCWD,"",AT_EMPTY_PATH) which
        # proot does not support. Override cargoSetupPostUnpackHook to use tar instead.
        postUnpack = ''
          cargoSetupPostUnpackHook() {
            echo "Executing cargoSetupPostUnpackHook (proot-compat)"
            eval "''${cargoDepsHook-}"
            if [ -z "''${cargoVendorDir-}" ]; then
              local dest
              dest=$(stripHash "$cargoDeps")
              mkdir -p "$dest"
              tar cf - -C "$cargoDeps" . | tar xf - -C "$dest"
              chmod -R +644 "$dest"
              export cargoDepsCopy
              cargoDepsCopy="$(realpath "$dest")"
            else
              cargoDepsCopy="$(realpath "$(pwd)/$sourceRoot/''${cargoRoot:+$cargoRoot/}''${cargoVendorDir}")"
            fi
            mkdir -p .cargo
            local config="$cargoDepsCopy/.cargo/config.toml"
            local tmp_config
            tmp_config=$(mktemp)
            sed "s|@vendor@|$cargoDepsCopy|g" "$config" > "$tmp_config"
            cat "$tmp_config" >> .cargo/config.toml
            rm "$tmp_config"
            echo "Finished cargoSetupPostUnpackHook"
          }
        '';

        meta = with lib; {
          description = "LLM-powered shell completion tool";
          homepage = "https://git.pitaya.f5.si/pitaya1219/shellm";
          license = licenses.mit;
        };
      } // config.local.shellm.extraBuildAttrs);
    in
    with pkgs; [
      shellm
      gnused
      tree
      curl
      expect        # for using unbuffer
      zstd
      nodejs
      sqlite
      duckdb
      ripgrep
      fzf
      age
      passage
      direnv
      pipx          # for installing python made tool into global
      poetry
      claude-code
      opencode
      ollama
      openssh
      nerd-fonts.daddy-time-mono
      nerd-fonts.shure-tech-mono
    ];
}
