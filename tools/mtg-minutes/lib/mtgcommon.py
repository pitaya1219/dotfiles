"""mtg-* コマンドの共通ライブラリ。

mtg / mtg-rec / mtg-live / mtg-self / mtg-minutes が共有する
  - ログ出力ヘルパ (info / warn / die)
  - 話者サイドの定義 (SIDES) と録音まわりの既定値
  - キャプチャデバイスの名前解決
  - ライブ文字起こし (LiveTranscriber。sherpa-onnx をこのプロセス内で回す)
  - 話者ラベル付き字幕の表示 (print_utterance) とログ保存 (LiveLog)
をまとめる。bin/* は自分の ../lib を sys.path に足して import する
(子プロセスとして呼ぶ claude CLI 等に影響させないため PYTHONPATH は使わない)。
"""
import datetime as dt
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

CONFIG_FILE = Path.home() / ".config/mtg-minutes/config.json"

MODEL_DIR = Path.home() / ".cache/whisper-cpp/models"
MODELS = {
    "turbo":  MODEL_DIR / "ggml-large-v3-turbo.bin",
}

# バッチ文字起こし用の VAD モデル(silero)。whisper-cli --vad に渡す。
VAD_MODEL = MODEL_DIR / "ggml-silero-v5.1.2.bin"

# Live captions run ReazonSpeech (k2 Zipformer, int8) through sherpa-onnx, in
# this process. nix places the files; see shared/programs/mtg-minutes.nix.
LIVE_MODEL_DIR = Path.home() / ".cache/mtg-minutes/models"
LIVE_ASR_DIR = LIVE_MODEL_DIR / "reazonspeech"
LIVE_VAD_MODEL = LIVE_MODEL_DIR / "silero_vad.onnx"
SAMPLE_RATE = 16000
VAD_WINDOW = 512
# 0.35s endpointing and a 12s cap are hayamimi's tuned values for broadcast
# Japanese; a longer silence only delays the caption, a longer cap only delays
# monologues.
LIVE_MIN_SILENCE_SEC = 0.35
LIVE_MAX_SPEECH_SEC = 12.0
LIVE_VAD_THOLD = 0.5
LIVE_ASR_THREADS = 4

LIVE_LOG_DIR = Path.home() / "Documents/mtg-minutes/live"

# 録音まわりの既定値。mtg と mtg-rec の両方が参照する。
OUT_DIR = Path.home() / "Movies"
MEETING_OUTPUT_DEVICE = "会議用"
LIVE_SILENCE_ALERT_SEC_DEFAULT = 120

# 字幕や録音の生死を見る間隔。会議のあいだ回り続けるので、細かくしても得がない。
POLL_INTERVAL_SEC = 1.0


def _labels():
    """話者ラベルを mtg-minutes と同じ設定から引く。

    ラベルの持ち主は ~/.config/mtg-minutes/config.json の self_label /
    other_label(nix の programs.mtg-minutes.settings が書く)。ここで同じ値を
    読むことで、ライブ字幕のラベルとバッチ文字起こしのラベルが食い違わない。
    食い違うと、ライブ字幕ログを mtg-minutes --transcript に渡したときだけ
    話者名が変わる、という分かりにくい挙動になる。
    """
    labels = {"self": "自分", "other": "相手"}
    try:
        cfg = json.loads(CONFIG_FILE.read_text())
    except Exception:
        cfg = {}
    for side in labels:
        value = os.environ.get(f"MTG_{side.upper()}_LABEL") or cfg.get(f"{side}_label")
        if value:
            labels[side] = value
    return labels


# 話者サイドの定義。device は「録音(ffmpeg avfoundation)」と
# 「ライブ字幕(PortAudio)」で同じ物理デバイスを指す。
# ただし両者はデバイス番号の体系が別なので、番号は各々で解決する。
#   self  … 物理マイク → OBS(RNNoise) → BlackHole 2ch
#   other … 通話アプリ → 複数出力装置 → BlackHole 16ch
SIDES = {
    "self":  dict(color="32", device="BlackHole 2ch"),
    "other": dict(color="36", device="BlackHole 16ch"),
}
for _side, _label in _labels().items():
    SIDES[_side]["label"] = _label


# ---------------------------------------------------------------------------
# 出力ヘルパ
# ---------------------------------------------------------------------------
# 字幕は複数スレッドから、進捗メッセージはメインスレッドから出るので、
# 行が混ざらないよう単一のロックで直列化する。
_OUT_LOCK = threading.Lock()


def _emit(stream, text):
    with _OUT_LOCK:
        stream.write(text + "\n")
        stream.flush()


def info(msg):
    _emit(sys.stderr, f"\033[36m▶\033[0m {msg}")


def warn(msg):
    _emit(sys.stderr, f"\033[33m⚠\033[0m {msg}")


def die(msg, code=1):
    _emit(sys.stderr, f"\033[31m✖\033[0m {msg}")
    sys.exit(code)


def hr():
    """区切り線。字幕スレッドと混ざらないよう _emit 経由で出す。"""
    _emit(sys.stderr, "\033[2m" + "─" * 60 + "\033[0m")


def stamp():
    return dt.datetime.now().strftime("%Y%m%d_%H%M%S")


def sibling(name):
    """PATH に頼らず、自分の隣にある mtg-* を絶対パスで解決する。

    nix パッケージは bin/* を $out/bin に同居させる前提なので、
    wrapProgram 経由(__file__ が .mtg-xxx-wrapped)でも隣が引ける。
    """
    p = Path(__file__).resolve().parent.parent / "bin" / name
    if p.exists():
        return str(p)
    p = Path(sys.argv[0]).resolve().parent / name
    return str(p) if p.exists() else name


def print_minutes_hint(recording=None, transcript=None):
    """議事録化コマンドの案内。トップレベルのコマンドだけが出す。"""
    if recording:
        print("\n次のコマンドで議事録化できます:")
        print(f"  mtg-minutes {recording} --title \"会議名\"")
    elif transcript:
        print("\nライブ字幕から議事録化するなら:")
        print(f"  mtg-minutes --transcript {transcript} --title \"会議名\"")


def format_ts(sec):
    """経過秒 → MM:SS(1時間を超えたら H:MM:SS)"""
    sec = max(0, int(sec))
    h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def print_utterance(t, meta, text):
    _emit(sys.stdout,
          f"\033[2m[{format_ts(t)}]\033[0m \033[{meta['color']}m{meta['label']}\033[0m: {text}")


# ---------------------------------------------------------------------------
# デバイス解決
# ---------------------------------------------------------------------------
def list_capture_devices(refresh=False):
    """PortAudio から入力デバイス一覧を得る [(idx, name), ...]

    PortAudio はデバイス一覧を初期化時に1度だけ取るので、後から挿した機器は
    refresh=True で作り直さないと見えない。作り直すと開いているストリームが
    壊れるので、ストリームを1本も開いていないときだけ使うこと。
    """
    import sounddevice as sd

    if refresh:
        sd._terminate()
        sd._initialize()
    return [(i, d["name"]) for i, d in enumerate(sd.query_devices())
            if d["max_input_channels"] > 0]


def get_audio_output():
    """現在のシステム出力デバイス名を返す。SwitchAudioSource が無ければ None。"""
    try:
        res = subprocess.run(["SwitchAudioSource", "-c"], capture_output=True, text=True)
        return res.stdout.strip() or None
    except FileNotFoundError:
        return None


def switch_audio_output(device_name):
    """SwitchAudioSource でシステム出力デバイスを切り替える。失敗は warn のみ。"""
    try:
        subprocess.run(["SwitchAudioSource", "-s", device_name], check=True, capture_output=True)
    except FileNotFoundError:
        warn("SwitchAudioSource が見つかりません。出力デバイスの自動切り替えをスキップ")
    except subprocess.CalledProcessError:
        warn(f"出力デバイスの切り替えに失敗: {device_name!r}")


class MeetingOutput:
    """会議中だけシステム出力デバイスを切り替え、終了時に元へ戻す。

    相手の声は「システム出力 → 複数出力装置 → BlackHole 16ch」で流れてくるので、
    出力が会議用に向いていないと録音もライブ字幕も無音になる。つまり録音の
    有無に関わらず必要な設定であり、録音サブプロセス任せにはできない。
    """

    def __init__(self, device, enabled=True):
        self.device = device
        self.enabled = enabled
        self.prev = None

    def __enter__(self):
        if not self.enabled:
            return self
        prev = get_audio_output()
        if prev != self.device:
            info(f"出力デバイス切り替え: {prev!r} → {self.device!r}")
            switch_audio_output(self.device)
            self.prev = prev        # 既に会議用なら戻す必要がない
        return self

    def __exit__(self, *exc):
        if self.prev:
            switch_audio_output(self.prev)
            info(f"出力デバイスを戻しました: {self.prev!r}")
        self.prev = None
        return False


def stop_process(proc, sig=signal.SIGINT, timeout=5):
    """子プロセスを sig で止め、駄目なら terminate → kill と段階的に強くする。"""
    if proc is None or proc.poll() is not None:
        return
    proc.send_signal(sig)
    try:
        proc.wait(timeout=timeout)
        return
    except subprocess.TimeoutExpired:
        proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def resolve_device(devices, name):
    """名前(部分一致・大文字小文字無視)でデバイス番号を解決。

    avfoundation(録音)と SDL(ライブ字幕)で番号の体系は違うが、
    「一覧から名前で引く」規則自体は共通なのでここに一本化する。
    """
    nl = name.lower()
    for idx, dname in devices:
        if nl in dname.lower():
            return idx, dname
    return None, None


def resolve_or_report(devices, name, label, hint="--list で確認してください。"):
    """デバイスを解決し、見つからなければ理由を warn して (None, None) を返す。

    hint を呼び出し側から渡すのは、--capture-id を持つのが mtg-live / mtg-self
    だけで、mtg には無いため。存在しないオプションを案内しないようにする。
    """
    idx, dname = resolve_device(devices, name)
    if idx is None:
        warn(f"{label}側のデバイス '{name}' が見つかりません。{hint}")
        if devices:
            warn("検出されたデバイス: " + ", ".join(f"#{i}:{n}" for i, n in devices))
    return idx, dname


def print_capture_devices(devices, wanted):
    print("利用可能なキャプチャデバイス:")
    for idx, name in devices:
        mark = "  ← これを使う" if wanted.lower() in name.lower() else ""
        print(f"  #{idx}: {name}{mark}")
    if not any(wanted.lower() in n.lower() for _, n in devices):
        print(f"\n※ '{wanted}' が見つかりません。")
        print("  brew install --cask blackhole-16ch でインストールし、")
        print("  Audio MIDI設定で複数出力装置(ヘッドホン + BlackHole 16ch)を作成してください。")


# ---------------------------------------------------------------------------
# ライブ文字起こし
# ---------------------------------------------------------------------------
# One recognizer serves every side in the process: the weights are loaded once
# and decodes take turns under _decode_lock (100-300ms each on an M3, so two
# sides never queue long enough to matter).
_recognizer = None
_recognizer_lock = threading.Lock()
_decode_lock = threading.Lock()


def load_recognizer():
    global _recognizer
    with _recognizer_lock:
        if _recognizer is None:
            import sherpa_onnx

            _recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
                encoder=str(LIVE_ASR_DIR / "encoder.int8.onnx"),
                decoder=str(LIVE_ASR_DIR / "decoder.int8.onnx"),
                joiner=str(LIVE_ASR_DIR / "joiner.int8.onnx"),
                tokens=str(LIVE_ASR_DIR / "tokens.txt"),
                num_threads=LIVE_ASR_THREADS,
            )
        return _recognizer


def release_recognizer():
    """Drop the weights. The next start() loads them again (under a second)."""
    global _recognizer
    with _recognizer_lock:
        _recognizer = None


def _build_vad(threshold):
    import sherpa_onnx

    cfg = sherpa_onnx.VadModelConfig(sample_rate=SAMPLE_RATE, num_threads=1)
    cfg.silero_vad.model = str(LIVE_VAD_MODEL)
    cfg.silero_vad.threshold = threshold
    cfg.silero_vad.min_silence_duration = LIVE_MIN_SILENCE_SEC
    cfg.silero_vad.min_speech_duration = 0.25
    cfg.silero_vad.max_speech_duration = LIVE_MAX_SPEECH_SEC
    cfg.silero_vad.window_size = VAD_WINDOW
    return sherpa_onnx.VoiceActivityDetector(cfg, buffer_size_in_seconds=30)


class LiveTranscriber:
    """1デバイスを開き、発話が切れるたびに認識して on_utterance(side, t, text) を呼ぶ。

    t はセッション開始(session_zero)からの秒で、発話の**開始**時刻。表示は
    認識が終わった順になるが、ログは t で並べ直すので会話順に揃う。
    時刻はストリームに流れたサンプル数から出すので、サイド間でずれない。

    全チャンネルを開いて等倍で足す(mtg-rec と同じ扱い)。複数出力装置が
    BlackHole 16ch のどのチャンネルに書くかは Audio MIDI 設定次第で、実機では
    ch3 に乗っていた。平均すると 16 で割られて小声が VAD の閾値を割る。
    """

    def __init__(self, side, device, vad_thold=LIVE_VAD_THOLD,
                 on_utterance=None, session_zero=None):
        self.side = side
        self.meta = SIDES[side]
        self.device = device
        self.vad_thold = vad_thold
        self.on_utterance = on_utterance
        self.session_zero = time.monotonic() if session_zero is None else session_zero
        self.opened_device = None
        self.error = None
        self._queue = queue.Queue()
        self._stream = None
        self._worker = None
        self._t_zero = None

    def start(self, devices=None):
        """モデルを載せてデバイスを開く。失敗したら self.error に理由を入れて False。

        devices を渡すと一覧を引き直さない(複数サイドで1回の列挙を使い回す)。
        """
        try:
            import sounddevice as sd

            if devices is None:
                devices = list_capture_devices()
            idx, name = resolve_device(devices, self.device)
            if idx is None:
                self.error = f"デバイス '{self.device}' が見つかりません"
                return False
            recognizer = load_recognizer()
            vad = _build_vad(self.vad_thold)
            channels = sd.query_devices(idx)["max_input_channels"]
            self._stream = sd.InputStream(
                device=idx, samplerate=SAMPLE_RATE, channels=channels,
                dtype="float32", blocksize=VAD_WINDOW, callback=self._on_audio)
            self._worker = threading.Thread(
                target=self._run, args=(recognizer, vad), daemon=True)
            self._worker.start()
            self._t_zero = time.monotonic()
            self._stream.start()
        except Exception as e:
            self.error = f"{type(e).__name__}: {e}"
            self.stop()
            return False
        self.opened_device = name
        return True

    def alive(self):
        return (self._worker is not None and self._worker.is_alive()
                and self._stream is not None and self._stream.active)

    def _on_audio(self, indata, frames, time_info, status):
        self._queue.put(indata.sum(axis=1))

    def _run(self, recognizer, vad):
        import numpy as np

        pending = np.zeros(0, dtype=np.float32)
        try:
            while True:
                chunk = self._queue.get()
                if chunk is None:
                    break
                # The VAD takes exactly one window per call; the device may hand
                # over blocks of another size when it resamples.
                pending = np.concatenate([pending, chunk])
                while len(pending) >= VAD_WINDOW:
                    vad.accept_waveform(pending[:VAD_WINDOW])
                    pending = pending[VAD_WINDOW:]
                    self._drain(recognizer, vad)
            # Stopping mid-sentence still yields that sentence. voice-in relies
            # on it for the words said just before the key came up.
            vad.flush()
            self._drain(recognizer, vad)
        except Exception as e:
            self.error = f"{type(e).__name__}: {e}"

    def _drain(self, recognizer, vad):
        while not vad.empty():
            seg = vad.front
            samples, start = seg.samples, seg.start
            vad.pop()
            with _decode_lock:
                stream = recognizer.create_stream()
                stream.accept_waveform(SAMPLE_RATE, samples)
                recognizer.decode_stream(stream)
                text = stream.result.text.strip()
            if text and self.on_utterance is not None:
                t = (self._t_zero - self.session_zero) + start / SAMPLE_RATE
                self.on_utterance(self.side, t, text)

    def signal_stop(self):
        """停止を指示するだけで待たない(複数サイドを同時に止めるため)。"""
        if self._stream is not None:
            try:
                self._stream.stop()
            except Exception:
                pass
        if self._worker is not None:
            self._queue.put(None)

    def stop(self):
        self.signal_stop()
        if self._worker is not None:
            self._worker.join(timeout=5)
            self._worker = None
        if self._stream is not None:
            try:
                self._stream.close()
            except Exception:
                pass
            self._stream = None


def stop_all(transcribers):
    """全サイドに先に停止を指示してから回収する。

    順に stop() すると1本あたり最大5秒の待ちが積み上がる。停止指示だけ
    先に全部投げておけば、待ち時間は重なって実質1本分で済む。
    """
    for tr in transcribers:
        tr.signal_stop()
    for tr in transcribers:
        tr.stop()


class LiveLog:
    """字幕を「[時刻] ラベル: 本文」の形で保存する。

    到着した順にその場で append し(途中でクラッシュしても記録が残るように)、
    close() で発話開始時刻に並べ替えて書き直す。表示は到着順・保存は発話順、
    という使い分け。録音が失敗していた場合はこのファイルがそのまま
    mtg-minutes --transcript に渡せる救済材料になる。
    """

    def __init__(self, path):
        self.path = Path(path)
        self.rows = []
        self._lock = threading.Lock()
        self._fh = None         # 最初の発話まで開かない(空ファイルを作らない)
        self._closed = False

    def add(self, t, label, text):
        with self._lock:
            if self._closed:
                # 停止時、読み取りスレッドの join がタイムアウトした後に
                # 遅れて届いた発話。閉じた handle に書くと例外になるので捨てる。
                return
            if self._fh is None:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                self._fh = open(self.path, "w")
            self.rows.append((t, label, text))
            self._fh.write(f"[{format_ts(t)}] {label}: {text}\n")
            self._fh.flush()

    def close(self):
        """発話順に並べ替えて確定する。1度も発話が無ければ何も作らない。"""
        with self._lock:
            if self._closed:
                return self.path if self.rows else None
            self._closed = True
            if self._fh is None:
                return None
            self._fh.close()
            self.rows.sort(key=lambda r: r[0])
            self.path.write_text(
                "".join(f"[{format_ts(t)}] {label}: {text}\n" for t, label, text in self.rows)
            )
        return self.path


def open_live_log(no_save):
    """字幕ログを開き、(log, on_utterance) を返す。

    「表示して、保存する」という字幕の出口はここだけに置く。mtg と
    mtg-live/mtg-self で別々に組み立てると、ログのファイル名や行の形式を
    変えたときに片方だけに効いてしまう。
    """
    log = None if no_save else LiveLog(LIVE_LOG_DIR / f"live_{stamp()}.txt")

    def on_utterance(side, t, text):
        meta = SIDES[side]
        print_utterance(t, meta, text)
        if log:
            log.add(t, meta["label"], text)

    return log, on_utterance


# ---------------------------------------------------------------------------
# mtg-live / mtg-self が共有する単一サイド実行
# ---------------------------------------------------------------------------
def add_tuning_args(ap, save=True):
    """Live-transcription tuning options, shared by mtg, the per-side commands and voice-in.

    save exists for voice-in, which keeps no subtitle log. The point is to hold
    the defaults and help text in one place, so unwanted options are dropped by
    argument rather than by copying the rest.
    """
    ap.add_argument("--vad-thold", type=float, default=LIVE_VAD_THOLD,
                    help=f"発話とみなす確率の閾値。下げるほど小声を拾う (既定: {LIVE_VAD_THOLD})")
    if save:
        ap.add_argument("--no-save", action="store_true",
                        help="字幕ログのファイル保存をしない(既定は保存する)")


def add_device_args(ap, side):
    """Capture device selection, shared by the live commands and voice-in."""
    meta = SIDES[side]
    ap.add_argument("--list", action="store_true", help="キャプチャデバイス一覧を表示して終了")
    ap.add_argument("--device", default=meta["device"],
                    help=f"キャプチャデバイス名(部分一致) (既定: {meta['device']})")


def live_main(prog, side, description=None):
    """mtg-live / mtg-self の本体。1サイドだけライブ字幕を流す。

    2つのコマンドの違いは prog と side だけなので、引数定義から実行まで
    ここにまとめる(呼ぶ順番を間違えようがないように)。
    """
    import argparse

    meta = SIDES[side]
    ap = argparse.ArgumentParser(
        # prog を明示するのは、nix の wrapProgram 経由だと argv[0] が
        # '.mtg-live-wrapped' になり usage 行がその名前で出てしまうため。
        prog=prog, description=description or f"{meta['label']}の声をリアルタイム文字起こし")
    add_device_args(ap, side)
    add_tuning_args(ap)
    args = ap.parse_args()

    if args.list:
        print_capture_devices(list_capture_devices(), args.device)
        return

    session_zero = time.monotonic()
    log, on_utterance = open_live_log(args.no_save)

    tr = LiveTranscriber(side, args.device, vad_thold=args.vad_thold,
                         on_utterance=on_utterance, session_zero=session_zero)
    if not tr.start():
        die(f"{meta['label']}側の字幕を開始できませんでした: {tr.error}")

    info(f"{meta['label']}: {tr.opened_device}")
    if log:
        info(f"ログ保存先: {log.path}")
    info("Ctrl-C で終了")
    hr()

    try:
        while tr.alive():
            time.sleep(POLL_INTERVAL_SEC)
        warn(f"{meta['label']}側の字幕が止まりました: {tr.error or 'デバイスが閉じられました'}")
    except KeyboardInterrupt:
        pass
    finally:
        tr.stop()
        path = log.close() if log else None
        if path:
            print()
            info(f"字幕ログ: {path}")
