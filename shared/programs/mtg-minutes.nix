{ config, pkgs, lib, ... }:

let
  cfg = config.programs.mtg-minutes;
  jsonFormat = pkgs.formats.json { };

  # mtg / mtg-rec / mtg-live / mtg-self / mtg-minutes が呼ぶ外部コマンドを固定する。
  #   ffmpeg     … ffmpeg + ffprobe (録音・音声変換・トラック数判定)
  #   whisper-cpp … whisper-cli (バッチ文字起こし) + whisper-stream (ライブ字幕)
  # claude CLI は別管理なので wrapProgram の --prefix で既存 PATH に委ねる。
  runtimeInputs = with pkgs; [ ffmpeg whisper-cpp switchaudio-osx ];

  # The python the scripts' shebangs point at. voice-in needs pyobjc because it
  # types finalized text through CGEvent (Quartz). One interpreter for all of
  # them beats having to remember which script has pyobjc and which does not.
  pythonForScripts = pkgs.python3.withPackages (ps: [ ps.pyobjc-framework-Quartz ]);

  programs = [
    "mtg" "mtg-live" "mtg-minutes" "mtg-rec" "mtg-self"
    "voice-in" "voice-in-indicator"
  ];

  # Under nix-darwin, home.packages land in /etc/profiles/per-user/<user>/bin.
  # That path survives rebuilds, so baking it into the Karabiner rule is safe.
  # A store path would not be: enabling the rule copies it into karabiner.json,
  # where the next switch leaves it pointing at something that no longer exists.
  voiceInBin = "/etc/profiles/per-user/${config.home.username}/bin/voice-in";

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

    nativeBuildInputs = [ pkgs.makeWrapper pythonForScripts ];

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
      cp lib/*.py $out/lib/

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

  # The Karabiner rule that drives voice-in from a chord.
  #
  # Bound to a combination of modifiers so no ordinary key is taken: it only
  # fires when both are down, and either one alone stays a plain modifier.
  #
  # detect_key_down_uninterruptedly aborts the chord as soon as another key is
  # pressed; without it everyday combinations like ctrl+A stall waiting on the
  # decision. The threshold is cut from the 1000ms default for the same reason:
  # left over, using one control shortly after the other misfires as a chord.
  #
  # shell_command runs with a minimal environment, hence the absolute path.
  # Every instruction returns without waiting - handed to the daemon if one is
  # up, otherwise started in the background with a cue when capture begins.
  #
  # Processes started from here do not inherit the accessibility grant given to
  # the terminal (TCC binds it to the responsible process, which here is
  # Karabiner). The instruction itself only writes to a socket and posts no
  # events, so this path needs no grant as long as a daemon is up. The one-shot
  # started when none is depends on Karabiner's own grant, so rather than rely
  # on that, keep a daemon running.
  karabinerKeys = cfg.voiceIn.karabiner.keys;
  karabinerHold = cfg.voiceIn.karabiner.mode == "hold";

  karabinerRule = {
    title = "voice-in (ローカル音声入力)";
    rules = [{
      description = "${lib.concatStringsSep " + " karabinerKeys} "
        + (if karabinerHold
           then "を押している間だけ voice-in で音声入力"
           else "同時押しで voice-in をトグル");
      manipulators = [
        ({
          type = "basic";
          from = {
            simultaneous = map (k: { key_code = k; }) karabinerKeys;
            simultaneous_options = {
              detect_key_down_uninterruptedly = true;
              key_down_order = "insensitive";
              key_up_order = "insensitive";
            };
            modifiers.optional = [ "any" ];
          };
          to = [{
            shell_command = "${voiceInBin} ${if karabinerHold then "--arm" else "--toggle"}";
          }];
          parameters."basic.simultaneous_threshold_milliseconds" =
            cfg.voiceIn.karabiner.simultaneousThresholdMs;
        } // lib.optionalAttrs karabinerHold {
          to_after_key_up = [{ shell_command = "${voiceInBin} --stop"; }];
        })
      ];
    }];
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

    # Settings for voice-in (local dictation). It is a separate command from
    # the meeting tools, so it is kept out of the toolkit-wide options above
    # (logseqTokenCommand / settings). The command itself always ships with the
    # package; what lives here is only "take over a hotkey" and "run from
    # login" - things that should not happen merely because the module is
    # enabled - so everything defaults to off.
    voiceIn = {
      daemon = {
        enable = lib.mkEnableOption ''
          voice-in をログイン時から常駐させる。ホットキーを押した瞬間に送出が
          始まる(常駐していないと、デバイス列挙とモデルロードで約3秒かかる)
        '';

        warmIdleSec = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 900;
          description = ''
            使われないままこの秒数が過ぎたら whisper-stream を落とす。0 で落とさない。
            null なら `--warm-idle` を渡さず voice-in 側の既定に任せる
            (既定値をここと Python の両方に書くと、片方だけ直して食い違う)。
          '';
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "--device" "UAB-80" ];
          description = "常駐プロセスに渡す追加の引数。";
        };
      };

      karabiner = {
        enable = lib.mkEnableOption ''
          voice-in をトグルする Karabiner ルールを配置する。置くだけでは効かず、
          Karabiner の GUI で一度だけ有効化する必要がある
        '';

        keys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "left_control" "right_control" ];
          example = [ "left_option" "right_option" ];
          description = ''
            voice-in をトグルするキーの組み合わせ。揃って押されたときだけ発火し、
            片方だけなら素の修飾キーとして働くので、修飾キーを並べるのが前提。
            キー名は Karabiner の `key_code`(left_control / right_option など)。

            単独のキーは指定できない。1つだけ書くとそのキーが押された時点で
            発火し、修飾キーとしては使えなくなるため。
          '';
        };

        mode = lib.mkOption {
          type = lib.types.enum [ "toggle" "hold" ];
          default = "toggle";
          description = ''
            toggle … 押すたびに開始/停止を切り替える。手が空き、常駐が無くても
                     成立する(押す → 音が鳴ってから喋る → もう一度押す)。
                     止め忘れると次に触ったアプリへ文字が入る(idle-timeout が保険)。
            hold   … 押している間だけ送出する。離せば必ず止まるが、喋っているあいだ
                     キーが塞がり、収音が間に合うよう常駐が必須になる。
          '';
        };

        simultaneousThresholdMs = lib.mkOption {
          type = lib.types.int;
          default = 250;
          description = ''
            同時押しとみなす間隔(ms)。Karabiner の既定は 1000 だが、それだと
            「片方で何かした直後にもう片方を使う」が誤爆する。両手で押すぶんには
            250 で足りる。押しても反応しないなら伸ばす。
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ mtg-minutes ];

    # A single key is not a chord: it would fire the moment that key goes down,
    # making the modifier unusable day to day. Nothing catches that before the
    # switch, so reject it here.
    assertions = [{
      assertion = !cfg.voiceIn.karabiner.enable || builtins.length karabinerKeys >= 2;
      message = "programs.mtg-minutes.voiceIn.karabiner.keys は2つ以上指定してください。";
    }];

    # 各スクリプトが見る既定パスにモデルを symlink する。
    # 注意: 同パスに手動DL済みの実ファイルがあると switch が衝突する。先に削除すること。
    home.file = lib.mapAttrs'
      (name: drv: lib.nameValuePair ".cache/whisper-cpp/models/${name}" { source = drv; })
      whisperModels
    # Karabiner's complex_modifications are files dropped in assets/ and then
    # enabled from the GUI. karabiner.json itself is rewritten by the app, so it
    # cannot be a symlink (read-only makes every GUI change fail).
    #
    # Only the template belongs here; enabling happens in the GUI under
    # Complex Modifications > Add predefined rule. That copies the contents into
    # karabiner.json, so changing keys and switching leaves the enabled copy
    # stale - after changing the rule it has to be re-added in the GUI. This
    # declaration alone does not take effect.
    // lib.optionalAttrs cfg.voiceIn.karabiner.enable {
      ".config/karabiner/assets/complex_modifications/voice-in.json".source =
        jsonFormat.generate "karabiner-voice-in.json" karabinerRule;
    };

    # config.json を宣言管理(read-only symlink)。token はコマンド経由なので秘密は含まない。
    xdg.configFile."mtg-minutes/config.json".source =
      jsonFormat.generate "mtg-minutes-config.json" settings;

    # The voice-in daemon. KeepAlive brings it back so the hotkey always has
    # something to talk to. It does not exit when the grant is missing (exiting
    # would fight KeepAlive), so this cannot become a respawn loop.
    #
    # Note: a launchd-started process is its own responsible process, so the
    # accessibility grant given to a terminal does not apply. Making it type
    # means adding voiceInBin to the Accessibility list by hand. To avoid that,
    # leave daemon.enable off and start `voice-in --daemon` from a terminal.
    # launchd owns the log rather than appending, so look here when it sticks.
    launchd.agents.voice-in = lib.mkIf cfg.voiceIn.daemon.enable {
      enable = true;
      config = {
        ProgramArguments = [ voiceInBin "--daemon" ]
          ++ lib.optionals (cfg.voiceIn.daemon.warmIdleSec != null)
            [ "--warm-idle" (toString cfg.voiceIn.daemon.warmIdleSec) ]
          ++ cfg.voiceIn.daemon.extraArgs;
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${config.home.homeDirectory}/.cache/voice-in/daemon.log";
        StandardErrorPath = "${config.home.homeDirectory}/.cache/voice-in/daemon.log";
      };
    };
  };
}
