{ config, pkgs, lib, ... }:

let
  cfg = config.programs.mtg-minutes;
  jsonFormat = pkgs.formats.json { };

  # mtg / mtg-rec / mtg-live / mtg-self / mtg-minutes が呼ぶ外部コマンドを固定する。
  #   ffmpeg     … ffmpeg + ffprobe (録音・音声変換・トラック数判定)
  #   whisper-cpp … whisper-cli (バッチ文字起こし) + whisper-stream (ライブ字幕)
  # claude CLI は別管理なので wrapProgram の --prefix で既存 PATH に委ねる。
  runtimeInputs = with pkgs; [ ffmpeg whisper-cpp switchaudio-osx ];

  programs = [ "mtg" "mtg-live" "mtg-minutes" "mtg-rec" "mtg-self" ];

  # スクリプトが既定で使うモデルを nix で固定取得する。
  #   turbo … バッチ文字起こし(mtg-minutes)と相手側ライブ字幕の既定。約1.6GB
  #   small … バッテリー優先で軽くしたいとき用(--self-model small など)。約0.5GB
  # small は既定ではないが、代替モデル(MODEL_FALLBACK)と軽量化の選択肢として
  # 使うので置いておく。
  # base は引き続き手動DL(README §1 参照)。スクリプトは config ではなく
  # ~/.cache の各 ggml-*.bin を直接見る。
  whisperModels = {
    "ggml-large-v3-turbo.bin" = pkgs.fetchurl {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
      hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
    };
    "ggml-small.bin" = pkgs.fetchurl {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
      hash = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
    };
    # whisper-cli --vad 用の silero VAD モデル(約0.9MB)。長い無音を含む録音を
    # そのまま渡すと whisper が幻聴を返すため、発話区間だけを切り出すのに使う。
    "ggml-silero-v5.1.2.bin" = pkgs.fetchurl {
      url = "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin";
      hash = "sha256-KZQNmNQrkfvQXOSJ8+z3xy8KQvAn5IdZGaKPtMBOos8=";
    };
  };

  mtg-minutes = pkgs.stdenvNoCC.mkDerivation {
    pname = "mtg-minutes";
    version = "0.1.0";

    # ソースツリーから直接スクリプトを動かすと bin/ lib/ に __pycache__ ができる。
    # それが src に入ると derivation の入力ハッシュが変わって無駄に再ビルドされるので、
    # 生成物は除いてから store に入れる。
    src = lib.cleanSourceWith {
      src = ../../tools/mtg-minutes;
      filter = path: type:
        !(type == "directory" && baseNameOf path == "__pycache__")
        && !(lib.hasSuffix ".pyc" path);
    };

    nativeBuildInputs = [ pkgs.makeWrapper pkgs.python3 ];

    dontConfigure = true;
    dontBuild = true;

    # bin/* は Python3 スクリプト。$out/bin に同居させて互いの sibling 解決
    # (mtg → mtg-rec → mtg-minutes の呼び出し)を維持し、shebang を nix の
    # python3 に向けたうえで runtimeInputs を PATH に前置する。
    # 共有モジュールは $out/lib に置く。各スクリプトが自身の
    # ../lib を sys.path に足して読むので、PYTHONPATH は汚さない
    # (子プロセスとして呼ぶ claude CLI 等に影響させないため)。
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib
      cp lib/mtgcommon.py $out/lib/

      for prog in ${lib.concatStringsSep " " programs}; do
        cp bin/$prog $out/bin/
        patchShebangs $out/bin/$prog
        wrapProgram $out/bin/$prog \
          --prefix PATH : ${lib.makeBinPath runtimeInputs}
      done

      runHook postInstall
    '';

    meta = with lib; {
      description = "会議を録音しながら自分/相手をライブ文字起こしし、Logseq に議事録化するツール群";
      platforms = platforms.darwin;
      mainProgram = "mtg";
    };
  };

  # logseq_token_cmd を設定に注入(コマンド文字列のみ。トークン実体は store に焼かない)。
  settings = cfg.settings
    // lib.optionalAttrs (cfg.logseqTokenCommand != null) {
      logseq_token_cmd = cfg.logseqTokenCommand;
    };
in
{
  options.programs.mtg-minutes = {
    enable = lib.mkEnableOption "mtg-minutes meeting transcription & minutes toolkit (macOS)";

    logseqTokenCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "passage show logseq/http-api/claude-code/token";
      description = ''
        Logseq HTTP API トークンを取得するコマンド。config.json の `logseq_token_cmd`
        に書き込まれ、mtg-minutes 実行時に評価される。トークン実体は nix store にも
        config ファイルにも残らない。null なら書き込まない(configs.edn から自動取得)。
      '';
    };

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      example = lib.literalExpression ''{ output_dir = "~/Documents/mtg"; self_label = "自分"; }'';
      description = ''
        `~/.config/mtg-minutes/config.json` に書き込む設定。スクリプト側 DEFAULTS を
        上書きする。`logseq_token` はここに書かず `logseqTokenCommand` を使うこと。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ mtg-minutes ];

    # 各スクリプトが見る既定パスにモデルを symlink する。
    # 注意: 同パスに手動DL済みの実ファイルがあると switch が衝突する。先に削除すること。
    home.file = lib.mapAttrs'
      (name: drv: lib.nameValuePair ".cache/whisper-cpp/models/${name}" { source = drv; })
      whisperModels;

    # config.json を宣言管理(read-only symlink)。token はコマンド経由なので秘密は含まない。
    xdg.configFile."mtg-minutes/config.json".source =
      jsonFormat.generate "mtg-minutes-config.json" settings;
  };
}
