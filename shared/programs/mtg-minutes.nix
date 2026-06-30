{ config, pkgs, lib, ... }:

let
  # mtg-rec / mtg-live / mtg-minutes が呼ぶ外部コマンドを固定する。
  #   ffmpeg     … ffmpeg + ffprobe (録音・音声変換・トラック数判定)
  #   whisper-cpp … whisper-cli (バッチ文字起こし) + whisper-stream (ライブ字幕)
  # claude CLI は別管理なので wrapProgram の --prefix で既存 PATH に委ねる。
  runtimeInputs = with pkgs; [ ffmpeg whisper-cpp ];

  mtg-minutes = pkgs.stdenvNoCC.mkDerivation {
    pname = "mtg-minutes";
    version = "0.1.0";

    src = ../../tools/mtg-minutes;

    nativeBuildInputs = [ pkgs.makeWrapper pkgs.python3 ];

    dontConfigure = true;
    dontBuild = true;

    # bin/* は Python3 スクリプト。$out/bin に同居させて互いの sibling 解決を維持し、
    # shebang を nix の python3 に向けたうえで runtimeInputs を PATH に前置する。
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      cp bin/mtg-live bin/mtg-minutes bin/mtg-rec $out/bin/
      patchShebangs $out/bin

      for prog in mtg-live mtg-minutes mtg-rec; do
        wrapProgram $out/bin/$prog \
          --prefix PATH : ${lib.makeBinPath runtimeInputs}
      done

      runHook postInstall
    '';

    meta = with lib; {
      description = "OBS 録音から2トラック議事録音声を生成し Logseq に議事録化するツール群";
      platforms = platforms.darwin;
      mainProgram = "mtg-minutes";
    };
  };
in
{
  home.packages = [ mtg-minutes ];
}
