{ config, pkgs, lib, ... }:

# OBS Studio ノイズキャンセリング構成マネージャー
#
# 構成: 物理マイク → OBS(RNNoise) → BlackHole 2ch → Zoom/Teams/Meet
#
# 注意: OBS は起動するたびに設定ファイルに状態を書き戻すため、home.file での
# symlink 管理は使えない。activation スクリプトで「ファイルがなければコピー」する
# シード方式を採用し、OBS の runtime 書き込みと共存する。
#
# 既存の設定を上書きしたい場合は --extra-darwin-args "obsForceUpdate=true" 相当の
# 操作は不要 — 手動で対象ファイルを削除してから switch すること。

let
  cfg = config.programs.obs-noise-cancel;
in
{
  options.programs.obs-noise-cancel = {
    enable = lib.mkEnableOption "OBS + RNNoise + BlackHole ノイズキャンセリング設定のシード";

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "characters_only";
      description = "OBS プロファイルディレクトリ名 (~/Library/Application Support/obs-studio/basic/profiles/ 以下)";
    };

    sceneCollectionFile = lib.mkOption {
      type = lib.types.str;
      default = "characters_only.json";
      description = "OBS シーンコレクションのファイル名";
    };

    configSourceDir = lib.mkOption {
      type = lib.types.path;
      description = "OBS 設定ファイルのソースディレクトリ (basic.ini / <sceneCollectionFile> / user.ini を含む)";
    };

    monitoringDeviceId = lib.mkOption {
      type = lib.types.str;
      default = "BlackHole2ch_UID";
      description = "OBS モニタリングデバイスの ID (BlackHole 2ch の固定 UID)";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.seedObsConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      export PATH="${pkgs.coreutils}/bin:${pkgs.diffutils}/bin:${pkgs.python3}/bin:$PATH"

      OBS_BASE="$HOME/Library/Application Support/obs-studio"
      PROFILE_DIR="$OBS_BASE/basic/profiles/${cfg.profileName}"
      SCENES_DIR="$OBS_BASE/basic/scenes"
      DIFF_FILE="$HOME/.cache/obs-noise-cancel/last.diff"

      mkdir -p "$PROFILE_DIR" "$SCENES_DIR" "$(dirname "$DIFF_FILE")"
      > "$DIFF_FILE"
      HAVE_DIFF=0

      # INI: seed or diff-to-file
      obs_check_ini() {
        local label=$1 src=$2 dst=$3 note=''${4:-}
        if [ ! -f "$dst" ]; then
          echo "obs-noise-cancel: seeding $label"
          cp "$src" "$dst"
          chmod 644 "$dst"
        elif diff -q "$src" "$dst" > /dev/null 2>&1; then
          echo "obs-noise-cancel: $label up to date"
        else
          echo "obs-noise-cancel: $label differs''${note:+ ($note)}"
          { echo "=== $label''${note:+ ($note)} ==="; diff -u "$src" "$dst"; echo; } >> "$DIFF_FILE" || true
          HAVE_DIFF=1
        fi
      }

      # JSON: キー順を無視して正規化比較し、差分をファイルへ
      obs_check_json() {
        local label=$1 src=$2 dst=$3
        if [ ! -f "$dst" ]; then
          echo "obs-noise-cancel: seeding $label"
          cp "$src" "$dst"
          chmod 644 "$dst"
        else
          src_norm=$(python3 -c \
            "import json,sys; print(json.dumps(json.load(open(sys.argv[1])), ensure_ascii=False, indent=2, sort_keys=True))" \
            "$src")
          dst_norm=$(python3 -c \
            "import json,sys; print(json.dumps(json.load(open(sys.argv[1])), ensure_ascii=False, indent=2, sort_keys=True))" \
            "$dst")
          if [ "$src_norm" = "$dst_norm" ]; then
            echo "obs-noise-cancel: $label up to date"
          else
            echo "obs-noise-cancel: $label differs"
            { echo "=== $label ==="; diff -u <(echo "$src_norm") <(echo "$dst_norm"); echo; } >> "$DIFF_FILE" || true
            HAVE_DIFF=1
          fi
        fi
      }

      obs_check_ini "basic.ini" \
        "${cfg.configSourceDir}/basic.ini" \
        "$PROFILE_DIR/basic.ini"

      obs_check_json "${cfg.sceneCollectionFile}" \
        "${cfg.configSourceDir}/${cfg.sceneCollectionFile}" \
        "$SCENES_DIR/${cfg.sceneCollectionFile}"

      # user.ini はウィンドウ geometry 等の runtime 状態も含むため差分が出やすい
      obs_check_ini "user.ini" \
        "${cfg.configSourceDir}/user.ini" \
        "$OBS_BASE/user.ini" \
        "window geometry changes are normal"

      if [ "$HAVE_DIFF" = "1" ]; then
        echo "obs-noise-cancel: diff saved → $DIFF_FILE"
      fi
    '';
  };
}
