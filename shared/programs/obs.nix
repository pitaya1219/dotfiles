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
      export PATH="${pkgs.coreutils}/bin:$PATH"

      OBS_BASE="$HOME/Library/Application Support/obs-studio"
      PROFILE_DIR="$OBS_BASE/basic/profiles/${cfg.profileName}"
      SCENES_DIR="$OBS_BASE/basic/scenes"

      # プロファイルディレクトリを作成
      mkdir -p "$PROFILE_DIR" "$SCENES_DIR"

      # basic.ini (プロファイル設定): 存在しない場合のみコピー
      if [ ! -f "$PROFILE_DIR/basic.ini" ]; then
        echo "obs-noise-cancel: seeding $PROFILE_DIR/basic.ini"
        cp "${cfg.configSourceDir}/basic.ini" "$PROFILE_DIR/basic.ini"
        chmod 644 "$PROFILE_DIR/basic.ini"
      else
        echo "obs-noise-cancel: skip basic.ini (already exists)"
      fi

      # シーンコレクション JSON: 存在しない場合のみコピー
      SCENE_FILE="$SCENES_DIR/${cfg.sceneCollectionFile}"
      if [ ! -f "$SCENE_FILE" ]; then
        echo "obs-noise-cancel: seeding $SCENE_FILE"
        cp "${cfg.configSourceDir}/${cfg.sceneCollectionFile}" "$SCENE_FILE"
        chmod 644 "$SCENE_FILE"
      else
        echo "obs-noise-cancel: skip ${cfg.sceneCollectionFile} (already exists)"
      fi

      # user.ini (プロファイル/シーン選択): 存在しない場合のみコピー
      if [ ! -f "$OBS_BASE/user.ini" ]; then
        echo "obs-noise-cancel: seeding $OBS_BASE/user.ini"
        cp "${cfg.configSourceDir}/user.ini" "$OBS_BASE/user.ini"
        chmod 644 "$OBS_BASE/user.ini"
      else
        echo "obs-noise-cancel: skip user.ini (already exists)"
      fi
    '';
  };
}
