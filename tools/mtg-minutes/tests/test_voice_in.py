#!/usr/bin/env python3
"""Regression tests for voice-in - the parts needing no audio device or grant.

    python3 tools/mtg-minutes/tests/test_voice_in.py

What is covered:
  1. Splitting by UTF-16 units. CGEventKeyboardSetUnicodeString wants a length
     in UTF-16 code units, not code points, so len(str) is wrong; splitting a
     surrogate pair puts mangled characters into the app.
  2. Which utterances are sent, and how they are joined. Nothing before the
     press, nothing after the release, and no separator before the first.
  3. Device id caching and the check on what was actually opened.
  4. Dropping whisper's set phrases for silence.
  5. Pid file cleanup: a pid left by an unclean exit would read as "running"
     and stop --toggle from starting anything.
Anything needing hardware (capture, posting events) is out of scope here, as
in test_parse.py.
"""
import importlib.machinery
import importlib.util
import os
import sys
import tempfile
import time
from pathlib import Path

_TOOL = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_TOOL / "lib"))


def _load_voice_in():
    """bin/voice-in has no extension, so it is loaded by path."""
    spec = importlib.util.spec_from_loader(
        "voice_in",
        importlib.machinery.SourceFileLoader("voice_in", str(_TOOL / "bin" / "voice-in")),
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


vi = _load_voice_in()
import mtgcommon  # noqa: E402
from textinject import _split_utf16  # noqa: E402


class FakeStderrProc:
    """Minimal fake process carrying only the stderr LiveTranscriber reads."""

    def __init__(self, lines):
        self.stderr = iter(line + "\n" for line in lines)


class FakeStdoutProc:
    """Minimal fake process carrying only the stdout LiveTranscriber reads."""

    def __init__(self, lines):
        self.stdout = iter(line + "\n" for line in lines)


class FakeInjector:
    """A destination that just collects whatever was sent."""

    def __init__(self, ok=True):
        self.sent = []
        self.ok = ok

    def send(self, text):
        self.sent.append(text)
        return self.ok


def check(cond, label):
    print(f"  {'ok  ' if cond else 'FAIL'} {label}")
    return cond


def utf16_len(s):
    return len(s.encode("utf-16-le")) // 2


def main():
    ok = True
    print("UTF-16 分割:")

    parts = list(_split_utf16("あいうえおかきくけこさしすせそたちつてと", 16))
    ok &= check("".join(p for p, _ in parts) == "あいうえおかきくけこさしすせそたちつてと",
                "分割して連結すると元に戻る")
    ok &= check(all(utf16_len(p) <= 16 for p, _ in parts),
                "どの断片も UTF-16 で上限を超えない")
    # The length comes back with the chunk so the sender need not re-encode to
    # recount it. Get this wrong and CGEventKeyboardSetUnicodeString is misled.
    ok &= check(all(n == utf16_len(p) for p, n in parts),
                "返す長さが断片の UTF-16 長と一致する")

    # Emoji are surrogate pairs, two UTF-16 units each. Counted as code points
    # (len) the length handed over would exceed the limit.
    emoji = "🎙" * 10
    eparts = list(_split_utf16(emoji, 16))
    ok &= check("".join(p for p, _ in eparts) == emoji, "サロゲートペアを含んでも元に戻る")
    ok &= check(all(n == utf16_len(p) <= 16 for p, n in eparts),
                "サロゲートペアを UTF-16 で2と数える(len では数えない)")
    ok &= check(max(len(p) for p, _ in eparts) == 8,
                "上限16に絵文字は8個まで(符号位置なら16個入ってしまう)")

    ok &= check(list(_split_utf16("", 16)) == [], "空文字は何も送らない")

    def dictation(injector, separator="", session_zero=0.0):
        return vi.Dictation(injector, separator=separator, log_text=False,
                            sound=False, session_zero=session_zero)

    def armed(injector, separator=""):
        d = dictation(injector, separator)
        d.arm()
        # arm() reads the real clock, but t here is seconds from session_zero
        # (0.0). Without lining them up everything counts as pre-arm and is dropped.
        d.armed_at = d.session_zero
        return d

    print("発話のつなぎ方:")
    inj = FakeInjector()
    d = armed(inj)
    d.on_utterance("self", 0.0, "今日の会議の件だけど")
    d.on_utterance("self", 3.0, "資料を先に送っておいて")
    ok &= check(inj.sent == ["今日の会議の件だけど", "資料を先に送っておいて"],
                "日本語は区切り文字を挟まない")

    inj2 = FakeInjector()
    d2 = armed(inj2, separator=" ")
    d2.on_utterance("self", 0.0, "hello")
    d2.on_utterance("self", 1.0, "world")
    ok &= check(inj2.sent == ["hello", " world"],
                "英語は2つ目以降にだけ空白を足す(先頭には付けない)")

    inj3 = FakeInjector()
    d3 = armed(inj3)
    d3.on_utterance("self", 0.0, "   ")
    ok &= check(inj3.sent == [] and d3.count == 0, "空白だけの発話は送らない")

    # A failed send must not raise, and must warn once - per utterance would flood.
    inj4 = FakeInjector(ok=False)
    d4 = armed(inj4)
    d4.on_utterance("self", 0.0, "あ")
    d4.on_utterance("self", 1.0, "い")
    ok &= check(d4._failed and d4.count == 2, "送出失敗でも例外を出さず数え続ける")

    print("送出のゲート(常駐時):")
    # whisper-stream keeps running while the daemon is stopped. Nothing spoken
    # in that time may leak into the app.
    inj5 = FakeInjector()
    d5 = dictation(inj5)
    d5.on_utterance("self", 0.0, "押す前の独り言")
    ok &= check(inj5.sent == [], "開始前の発話は送らない")

    # VAD mode re-reads the trailing --length on every detection, so the first
    # finalization after the press carries what was said before it. Utterances
    # that began before the arm are dropped.
    inj6 = FakeInjector()
    session_zero = 1000.0
    d6 = dictation(inj6, session_zero=session_zero)
    d6.arm()
    d6.armed_at = session_zero + 50.0        # armed 50s after session_zero
    d6.on_utterance("self", 45.0, "押す前に喋っていた内容")
    ok &= check(inj6.sent == [], "開始時刻より前に始まった発話は遡って拾わない")
    d6.on_utterance("self", 52.0, "押した後の発話")
    ok &= check(inj6.sent == ["押した後の発話"], "開始後に始まった発話は送る")

    # Stopping only closes the window. VAD finalizes after speech breaks, so
    # releasing right after the last word means it arrives late; anything that
    # began inside the window still goes through.
    # The window is staged as t 0-10s: on the real clock it would be momentary
    # and the "arrived after the release" path would never be exercised.
    inj7 = FakeInjector()
    session_zero7 = time.monotonic()
    d7 = dictation(inj7, session_zero=session_zero7)
    d7.arm()
    d7.armed_at = session_zero7
    d7.on_utterance("self", 2.0, "あ")
    d7.disarm()
    d7.disarmed_at = session_zero7 + 10.0
    ok &= check(not d7.armed and d7.settling, "停止直後は armed ではなく待ち状態")
    d7.on_utterance("self", 9.5, "離す直前に喋った最後の一息")
    ok &= check(inj7.sent == ["あ", "離す直前に喋った最後の一息"],
                "離した後に届いても、押していた区間の発話なら送る")
    d7.on_utterance("self", 10.5, "離した後に喋った内容")
    ok &= check(len(inj7.sent) == 2, "離した後に始まった発話は送らない")
    ok &= check(not d7.idle_expired(0.0001), "停止中は無発話タイムアウトが働かない")
    ok &= check(d7.settle_deadline() == d7.disarmed_at + vi.TAIL_GRACE_SEC,
                "待ちの締め切りは停止時刻 + 猶予")

    # Once the grace expires the window shuts; nothing gets through afterwards.
    d7.close()
    ok &= check(not d7.settling and d7.settle_deadline() is None, "close で待ちが終わる")
    d7.on_utterance("self", 9.5, "閉じた後に遅れて届いた")
    ok &= check(len(inj7.sent) == 2, "窓を閉じたら何も通さない")

    print("無音に対する幻聴の除去:")
    # Given silence or a very quiet signal, whisper returns set phrases learned
    # from YouTube subtitles. whisper-stream has neither whisper-cli's -sns nor
    # silero VAD, so they are dropped on read - whole utterance only, since a
    # substring match would also eat ordinary speech.
    for text in ("ご視聴ありがとうございました", "ご視聴ありがとうございました。",
                 "ご 視聴 ありがとうございました", "チャンネル登録お願いします"):
        ok &= check(mtgcommon.is_hallucination(text), f"落とす: {text}")
    for text in ("ありがとうございました", "本日はありがとうございました",
                 "ありがとうございました。助かります",
                 "資料をご視聴ありがとうございましたと書いておいて",
                 "ご清聴ありがとうございました"):
        ok &= check(not mtgcommon.is_hallucination(text), f"残す: {text}")

    # And they must not surface when mixed into real whisper-stream output
    tr_h = mtgcommon.LiveTranscriber("self", 0, "/dev/null")
    got_h = []
    tr_h.on_utterance = lambda side, t, text: got_h.append(text)
    tr_h.proc = FakeStdoutProc([
        "[Start speaking]",
        "",
        "### Transcription 1 START | t0 = 0 ms | t1 = 10000 ms",
        "",
        "[00:00:00.000 --> 00:00:04.000]  ご視聴ありがとうございました",
        "### Transcription 1 END",
        "",
        "### Transcription 2 START | t0 = 10000 ms | t1 = 20000 ms",
        "",
        "[00:00:00.000 --> 00:00:03.000]  資料を先に送っておいて",
        "### Transcription 2 END",
    ])
    tr_h._read_stdout()
    ok &= check(got_h == ["資料を先に送っておいて"],
                "幻聴だけのチャンクは発話として通知しない")

    print("デバイス番号のキャッシュ:")
    with tempfile.TemporaryDirectory() as tmp:
        vi.STATE_DIR = Path(tmp)
        vi.DEVICE_CACHE = Path(tmp) / "device.json"

        ok &= check(vi.load_device_cache("BlackHole 2ch") is None,
                    "キャッシュが無ければ None")
        vi.save_device_cache("BlackHole 2ch", 3)
        ok &= check(vi.load_device_cache("BlackHole 2ch") == 3, "保存した番号を引ける")
        vi.save_device_cache("UAB-80", 1)
        ok &= check(vi.load_device_cache("BlackHole 2ch") == 3
                    and vi.load_device_cache("UAB-80") == 1,
                    "別デバイスを足しても既存を消さない")
        vi.DEVICE_CACHE.write_text("壊れたJSON{")
        ok &= check(vi.load_device_cache("BlackHole 2ch") is None,
                    "壊れたキャッシュで落ちない")
        vi.save_device_cache("BlackHole 2ch", 2)
        ok &= check(vi.load_device_cache("BlackHole 2ch") == 2,
                    "壊れたキャッシュは書き直せる")

    print("開いたデバイスの答え合わせ:")
    # SDL ids shift as hardware comes and goes. Trusting the id alone opens a
    # different device silently, so the name whisper-stream reports is checked.
    # On the real thing stderr reads:
    #   init: attempt to open capture device 3 : 'MacBook Proのマイク' ...
    def transcriber_seeing(*stderr_lines):
        tr = mtgcommon.LiveTranscriber("self", 0, "/dev/null")
        tr.proc = FakeStderrProc(stderr_lines)
        tr._read_stderr()
        return tr

    tr_ok = transcriber_seeing(
        "init: found 4 capture devices:",
        "init: attempt to open capture device 2 : 'BlackHole 2ch' ...")
    ok &= check(tr_ok.opened_mismatch("BlackHole 2ch", timeout=0.1) is None,
                "希望どおりのデバイスなら通す")

    tr_ng = transcriber_seeing(
        "init: attempt to open capture device 3 : 'MacBook Proのマイク' ...")
    ok &= check(tr_ng.opened_mismatch("BlackHole 2ch", timeout=0.1) == "MacBook Proのマイク",
                "違うデバイスが開いたら気付く")

    # The listing line (Capture device #N: 'NAME') is not the opened report
    tr_list = transcriber_seeing("init:    - Capture device #0: 'UAB-80'")
    ok &= check(tr_list.opened_device is None, "一覧行は開いた報告として拾わない")

    tr_quiet = transcriber_seeing("init: nothing interesting")
    ok &= check(tr_quiet.opened_mismatch("BlackHole 2ch", timeout=0.1) is None,
                "報告行を確認できなければ止めずに進む")

    print("pid ファイル:")
    with tempfile.TemporaryDirectory() as tmp:
        vi.PID_FILE = Path(tmp) / "session.pid"

        ok &= check(vi.running_pid() is None, "pid ファイルが無ければ停止中")

        # A pid that does not exist (left behind by an unclean exit)
        dead = 999999
        vi.PID_FILE.write_text(str(dead))
        ok &= check(vi.running_pid() is None and not vi.PID_FILE.exists(),
                    "死んだ pid の残骸は掃除して停止中とみなす")

        vi.PID_FILE.write_text("これは数字ではない")
        ok &= check(vi.running_pid() is None, "壊れた pid ファイルで落ちない")

        vi.PID_FILE.write_text(str(os.getpid()))
        ok &= check(vi.running_pid() == os.getpid(), "生きている pid は動作中と判定する")

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
