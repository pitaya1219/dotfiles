{ config, pkgs, lib, ... }:

let
  # mtg-rec / mtg-live / mtg-minutes が呼ぶ外部コマンドを固定する。
  #   ffmpeg     … ffmpeg + ffprobe (録音・音声変換・トラック数判定)
  #   whisper-cpp … whisper-cli (バッチ文字起こし) + whisper-stream (ライブ字幕)
  # claude CLI は別管理なので wrapProgram の --prefix で既存 PATH に委ねる。
  runtimeInputs = with pkgs; [ ffmpeg whisper-cpp ];

  # 既定モデル(large-v3-turbo)だけ nix で固定取得する。約1.6GB。
  # base / small が必要なときは手動DL(README §1 参照)。mtg-live は config を
  # 読まず ~/.cache の各 ggml-*.bin を直接見るため、ここでは turbo のみ置く。
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
    hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
  };

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

  # mtg-minutes / mtg-live 双方が見る既定パスに turbo モデルを symlink する。
  # 注意: 同パスに手動DL済みの実ファイルがあると switch が衝突する。先に削除すること。
  home.file.".cache/whisper-cpp/models/ggml-large-v3-turbo.bin".source = whisperModel;
}
