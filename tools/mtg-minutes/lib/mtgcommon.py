"""mtg-* コマンドの共通ライブラリ。

mtg / mtg-rec / mtg-live / mtg-self / mtg-minutes が共有する
  - ログ出力ヘルパ (info / warn / die)
  - 話者サイドの定義 (SIDES) と録音まわりの既定値
  - whisper モデルの解決 (未DLモデルのフォールバック込み)
  - キャプチャデバイスの名前解決
  - ライブ文字起こしプロセスの管理 (LiveTranscriber)
  - 話者ラベル付き字幕の表示 (print_utterance) とログ保存 (LiveLog)
をまとめる。bin/* は自分の ../lib を sys.path に足して import する
(子プロセスとして呼ぶ claude CLI 等に影響させないため PYTHONPATH は使わない)。
"""
import collections
import datetime as dt
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

CONFIG_FILE = Path.home() / ".config/mtg-minutes/config.json"

MODEL_DIR = Path.home() / ".cache/whisper-cpp/models"
MODELS = {
    "base":   MODEL_DIR / "ggml-base.bin",
    "small":  MODEL_DIR / "ggml-small.bin",
    "turbo":  MODEL_DIR / "ggml-large-v3-turbo.bin",
}
# 指定モデルが未配置だったときに代わりに使う順序。
# 「軽い順」ではなく「精度が高い順」なのは、代替は本来あるはずのモデルが
# 無いという異常時の保険であり、そこでは軽さより結果が出ることを優先するため。
# nix が turbo と small の両方を配置するので通常は到達しない。
MODEL_FALLBACK = ["turbo", "small", "base"]

WHISPER_STREAM = "whisper-stream"
LIVE_LOG_DIR = Path.home() / "Documents/mtg-minutes/live"

# 録音まわりの既定値。mtg と mtg-rec の両方が参照する。
OUT_DIR = Path.home() / "Movies"
MEETING_OUTPUT_DEVICE = "会議用"
LIVE_SILENCE_ALERT_SEC_DEFAULT = 120

# モデルロード完了(収音開始)を待つ上限と、子プロセスの生死を見る間隔。
# 間隔は会議のあいだ回り続けるので、細かくしても得がない。
READY_TIMEOUT_SEC = 120
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
# 「ライブ字幕(whisper-stream/SDL)」で同じ物理デバイスを指す。
# ただし両者はデバイス番号の体系が別なので、番号は各々で解決する。
#   self  … 物理マイク → OBS(RNNoise) → BlackHole 2ch
#   other … 通話アプリ → 複数出力装置 → BlackHole 16ch
# 既定モデルを非対称にしているのは、whisper-stream を2本同時に回すと
# GPU負荷が倍になるため。自分の発言は内容を知っているので精度要求が低く、
# 計算資源は相手側に寄せる。議事録本体は録音からのバッチ処理(turbo)なので
# ここのモデル選択は最終的な議事録の精度には影響しない。
SIDES = {
    "self":  dict(color="32", device="BlackHole 2ch",  model="small"),
    "other": dict(color="36", device="BlackHole 16ch", model="turbo"),
}
for _side, _label in _labels().items():
    SIDES[_side]["label"] = _label

# whisper-stream の出力パース用
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
TRANS_START_RE = re.compile(r"^###\s+Transcription\s+\d+\s+START\s*\|\s*t0\s*=\s*(\d+)\s*ms")
TRANS_END_RE = re.compile(r"^###\s+Transcription\s+\d+\s+END")
# [BLANK_AUDIO] / (音楽) / 【拍手】 のような非発話マーカーは字幕から落とす
NON_SPEECH_RE = re.compile(r"^[\[\(（【][^\]\)）】]*[\]\)）】]$")
# whisper-stream のキャプチャデバイス一覧行
CAPTURE_DEV_RE = re.compile(r"Capture device #(\d+): '([^']*)'")


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
# モデル / デバイス解決
# ---------------------------------------------------------------------------
def resolve_model(name, quiet=False):
    """モデル名 → (実際に使う名前, パス)。

    既定モデルが未配置でも即死しないよう turbo → small → base の順に代替する。
    nix が配置するのは turbo だけで、small / base は手動DL運用のため
    (mtg-self の既定 small がまさにこれに当たる)。
    """
    if MODELS[name].exists():
        return name, MODELS[name]
    for alt in MODEL_FALLBACK:
        if MODELS[alt].exists():
            if not quiet:
                warn(f"モデル '{name}' が未配置のため '{alt}' で代替します "
                     f"(欲しいなら {MODELS[name]} を手動DL)")
            return alt, MODELS[alt]
    die(f"whisperモデルが1つも見つかりません: {MODEL_DIR}")


ENUMERATE_TIMEOUT_SEC = 15


def enumerate_capture_devices(model):
    """whisper-stream を一瞬だけ起動してキャプチャデバイス一覧を得る [(idx, name), ...]

    SDL のデバイス列挙はモデルロードより前に走るので、'attempt to open' /
    'obtained spec' が出た時点で打ち切れば 1.6GB のモデル読み込みは発生しない。

    打ち切りの目印は whisper-stream の出力文言に依存している。whisper.cpp 側で
    文言が変わると for ループが EOF まで返らず(このプロセスは自分から終わらない)、
    裏でモデルが丸ごとロードされたまま無限に待つことになる。それを避けるため
    タイマで打ち切る。
    """
    try:
        proc = subprocess.Popen(
            [WHISPER_STREAM, "-m", str(model), "-l", "ja", "-c", "-1"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        )
    except FileNotFoundError:
        die(f"{WHISPER_STREAM} が見つかりません(whisper-cpp が PATH にありますか?)")
    devices = []
    timed_out = threading.Event()

    def give_up():
        timed_out.set()
        proc.send_signal(signal.SIGINT)     # stderr を閉じて読み側のループを抜けさせる

    timer = threading.Timer(ENUMERATE_TIMEOUT_SEC, give_up)
    timer.start()
    try:
        for line in proc.stderr:
            m = CAPTURE_DEV_RE.search(line)
            if m:
                devices.append((int(m.group(1)), m.group(2)))
            if "attempt to open" in line or "obtained spec" in line:
                break
    finally:
        timer.cancel()
        stop_process(proc)
    if timed_out.is_set():
        warn(f"デバイス列挙が {ENUMERATE_TIMEOUT_SEC} 秒で終わりませんでした"
             f"({WHISPER_STREAM} の出力形式変更?)。--capture-id で番号を直接指定できます。")
    return devices


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


def resolve_or_report(devices, name, label):
    """デバイスを解決し、見つからなければ理由を warn して (None, None) を返す。"""
    idx, dname = resolve_device(devices, name)
    if idx is None:
        warn(f"{label}側のデバイス '{name}' が見つかりません。"
             f"--list で確認するか --capture-id で指定してください。")
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
class LiveTranscriber:
    """whisper-stream を1本起動し、VADモードの出力を発話単位で切り出して通知する。

    VADモード(--step 0)の stdout は

        ### Transcription 3 START | t0 = 1234 ms | t1 = 5678 ms

        本文…
        ### Transcription 3 END

    という形なので、START 行の t0 を「発話の開始時刻」として拾い、END 行で
    本文を確定する(本文が複数行に割れることがあるので連結する)。

    t0 は whisper-stream 内部のメインループ開始からの相対msなので、そのままでは
    2サイドの時刻を突き合わせられない。stderr に '[Start speaking]' が出た時刻を
    原点として記録し、セッション開始からの絶対秒に直す。

    こうして発話開始時刻で揃えるのが重要なのは、表示が「文字起こしが終わった順」
    になるため。自分側(small=速い)と相手側(turbo=遅い)ではチャンク処理の遅延が
    違うので、到着順に並べると実際の会話順とずれる。
    """

    def __init__(self, side, capture_id, model_path, language="ja", step=0,
                 length=10000, vad_thold=0.6, translate=False,
                 on_utterance=None, session_zero=None):
        self.side = side
        self.meta = SIDES[side]
        self.on_utterance = on_utterance
        self.session_zero = time.monotonic() if session_zero is None else session_zero
        self.t_zero = None      # '[Start speaking]' を観測した時刻(t0 の原点)
        self.ready = False
        self.proc = None
        self._threads = []
        # 起動に失敗したときに理由を出せるよう、stderr の末尾だけ手元に残す
        self.stderr_tail = collections.deque(maxlen=40)
        self.cmd = [
            WHISPER_STREAM, "-m", str(model_path),
            "-l", language,
            "-c", str(capture_id),
            "--step", str(step),
            "--length", str(length),
            "--vad-thold", str(vad_thold),
            "-kc",                      # keep context(文脈保持で精度向上)
        ]
        if translate:
            self.cmd.append("--translate")

    def start(self):
        try:
            self.proc = subprocess.Popen(
                self.cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, bufsize=1,
            )
        except FileNotFoundError:
            warn(f"{WHISPER_STREAM} が見つかりません({self.meta['label']}側の字幕を無効化)")
            return
        self._threads = [
            threading.Thread(target=self._read_stdout, daemon=True),
            threading.Thread(target=self._read_stderr, daemon=True),
        ]
        for t in self._threads:
            t.start()

    def wait_ready(self, deadline):
        """モデルロードが終わって収音が始まるまで待つ。準備できたら True。

        deadline は絶対時刻(time.monotonic 基準)。複数サイドを起動するときに
        同じ deadline を渡せば、待ち時間がサイド数だけ積み上がらない。
        """
        while time.monotonic() < deadline:
            if self.ready:
                return True
            if self.proc is None or self.proc.poll() is not None:
                return False
            time.sleep(0.1)
        return self.ready

    def _read_stdout(self):
        t0_ms, buf = None, []
        for raw in self.proc.stdout:
            line = ANSI_RE.sub("", raw).strip()
            m = TRANS_START_RE.match(line)
            if m:
                # 前チャンクが END を出さずに終わっていた場合の取りこぼしを防ぐ
                self._flush(t0_ms, buf)
                t0_ms, buf = int(m.group(1)), []
                continue
            if TRANS_END_RE.match(line):
                self._flush(t0_ms, buf)
                t0_ms, buf = None, []
                continue
            if not line or line.startswith("###") or NON_SPEECH_RE.match(line):
                continue
            buf.append(line)
        self._flush(t0_ms, buf)

    def _read_stderr(self):
        for raw in self.proc.stderr:
            if self.t_zero is None and "[Start speaking]" in raw:
                # whisper-stream 側のメインループ開始 = t0 の原点
                self.t_zero = time.monotonic()
                self.ready = True
            self.stderr_tail.append(raw.rstrip())

    def _flush(self, t0_ms, buf):
        text = " ".join(buf).strip()
        if not text or self.on_utterance is None:
            return
        if t0_ms is not None and self.t_zero is not None:
            t = (self.t_zero - self.session_zero) + t0_ms / 1000.0
        else:
            # 原点が取れなかった場合は到着時刻で代用(順序はずれるが落とさない)
            t = time.monotonic() - self.session_zero
        self.on_utterance(self.side, t, text)

    def signal_stop(self):
        """停止を指示するだけで待たない(複数サイドを同時に止めるため)。"""
        if self.proc is not None and self.proc.poll() is None:
            # stream.cpp は SIGINT でループを抜けて正常終了する
            self.proc.send_signal(signal.SIGINT)

    def stop(self):
        if self.proc is None:
            return
        stop_process(self.proc)
        for t in self._threads:
            t.join(timeout=2)


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
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = open(self.path, "w")

    def add(self, t, label, text):
        with self._lock:
            self.rows.append((t, label, text))
            self._fh.write(f"[{format_ts(t)}] {label}: {text}\n")
            self._fh.flush()

    def close(self):
        with self._lock:
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
def add_tuning_args(ap):
    """ライブ字幕のチューニング系オプション。mtg と片側コマンドで共通。"""
    ap.add_argument("--language", default="ja")
    ap.add_argument("--step", type=int, default=0,
                    help="0=VAD(発話区切りで確定) / >0=スライディング(ms)")
    ap.add_argument("--length", type=int, default=10000, help="1チャンクの最大長(ms)")
    ap.add_argument("--vad-thold", type=float, default=0.6, help="VAD感度(0=厳しい〜1=緩い)")
    ap.add_argument("--no-save", action="store_true",
                    help="字幕ログのファイル保存をしない(既定は保存する)")


def _add_live_args(ap, side):
    """片側ライブ字幕コマンド (mtg-live / mtg-self) のオプション"""
    meta = SIDES[side]
    ap.add_argument("--list", action="store_true", help="キャプチャデバイス一覧を表示して終了")
    ap.add_argument("--device", default=meta["device"],
                    help=f"キャプチャデバイス名 (既定: {meta['device']})")
    ap.add_argument("--capture-id", type=int, default=None,
                    help="デバイス番号を直接指定(--device より優先)")
    ap.add_argument("--model", choices=list(MODELS), default=meta["model"],
                    help=f"turbo=高精度 / small=軽量 / base=最軽量 (既定: {meta['model']})")
    ap.add_argument("--translate", action="store_true", help="英語にライブ翻訳")
    add_tuning_args(ap)


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
    _add_live_args(ap, side)
    args = ap.parse_args()

    model_name, model_path = resolve_model(args.model)

    if args.list:
        info("キャプチャデバイスを列挙中…")
        print_capture_devices(enumerate_capture_devices(model_path), args.device)
        return

    if args.capture_id is not None:
        # 列挙は whisper-stream を一瞬起動するので、番号直指定のときは省く
        cap_id, cap_name = args.capture_id, "(手動指定)"
    else:
        info("キャプチャデバイスを列挙中…")
        cap_id, cap_name = resolve_or_report(
            enumerate_capture_devices(model_path), args.device, meta["label"])
        if cap_id is None:
            die("中止しました。")

    session_zero = time.monotonic()
    log, on_utterance = open_live_log(args.no_save)

    tr = LiveTranscriber(
        side, cap_id, model_path,
        language=args.language, step=args.step, length=args.length,
        vad_thold=args.vad_thold, translate=args.translate,
        on_utterance=on_utterance, session_zero=session_zero,
    )

    info(f"{meta['label']}: デバイス #{cap_id} ({cap_name}) / モデル {model_name}")
    if log:
        info(f"ログ保存先: {log.path}")
    info("Ctrl-C で終了")
    hr()

    tr.start()
    try:
        if not tr.wait_ready(time.monotonic() + READY_TIMEOUT_SEC):
            for line in list(tr.stderr_tail)[-5:]:
                warn(f"  {line}")
            die(f"{meta['label']}側の whisper-stream を開始できませんでした。")
        while tr.proc.poll() is None:
            time.sleep(POLL_INTERVAL_SEC)
    except KeyboardInterrupt:
        pass
    finally:
        tr.stop()
        if log:
            path = log.close()
            print()
            info(f"字幕ログ: {path}")
