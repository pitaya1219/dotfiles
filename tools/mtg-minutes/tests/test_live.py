#!/usr/bin/env python3
"""Regression tests for the live transcriber and its log - no audio device or model needed.

    python3 tools/mtg-minutes/tests/test_live.py

The VAD and the recognizer are replaced by fakes that follow sherpa-onnx's
interface (VoiceActivityDetector / OfflineRecognizer), so what is checked is
the plumbing around them: windowing, timestamps, and the flush on stop.
"""
import queue
import sys
import tempfile
import threading
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import mtgcommon  # noqa: E402


class FakeSegment:
    def __init__(self, start, samples):
        self.start = start
        self.samples = samples


class FakeVad:
    """Emits one segment per `every` windows; flush() emits whatever is pending."""

    def __init__(self, every=3):
        self.every = every
        self.sizes = []
        self.pos = 0
        self.seg_start = 0
        self.ready = []

    def accept_waveform(self, samples):
        self.sizes.append(len(samples))
        self.pos += len(samples)
        if len(self.sizes) % self.every == 0:
            self._cut()

    def _cut(self):
        if self.pos > self.seg_start:
            n = self.pos - self.seg_start
            self.ready.append(FakeSegment(self.seg_start, np.zeros(n, dtype=np.float32)))
            self.seg_start = self.pos

    def flush(self):
        self._cut()

    def empty(self):
        return not self.ready

    @property
    def front(self):
        return self.ready[0]

    def pop(self):
        self.ready.pop(0)


class FakeResult:
    def __init__(self, text):
        self.text = text


class FakeStream:
    def accept_waveform(self, sample_rate, samples):
        self.n = len(samples)


class FakeRecognizer:
    def __init__(self):
        self.calls = 0

    def create_stream(self):
        return FakeStream()

    def decode_stream(self, stream):
        self.calls += 1
        stream.result = FakeResult(f"発話{self.calls} ")


def check(cond, label):
    print(f"  {'ok  ' if cond else 'FAIL'} {label}")
    return cond


def run_fake(chunks, every=3, t_zero_offset=2.0):
    got = []
    tr = mtgcommon.LiveTranscriber(
        "other", "BlackHole 16ch", session_zero=100.0,
        on_utterance=lambda side, t, text: got.append((side, t, text)))
    tr._t_zero = 100.0 + t_zero_offset
    tr._queue = queue.Queue()
    for c in chunks:
        tr._queue.put(np.asarray(c, dtype=np.float32))
    tr._queue.put(None)
    vad = FakeVad(every)
    worker = threading.Thread(target=tr._run, args=(FakeRecognizer(), vad))
    worker.start()
    worker.join(timeout=5)
    return tr, vad, got


def main():
    ok = True
    W = mtgcommon.VAD_WINDOW
    print("検査:")

    # Blocks of odd sizes (as when CoreAudio resamples) reach the VAD as exact windows
    _, vad, _ = run_fake([np.zeros(300), np.zeros(1000), np.zeros(30)], every=99)
    ok &= check(vad.sizes and all(n == W for n in vad.sizes), "VAD には窓幅ちょうどで渡す")
    ok &= check(len(vad.sizes) == 2, "窓に満たない端数は次のブロックまで持ち越す")

    # Timestamps: session offset + segment start in samples
    _, _, got = run_fake([np.zeros(W)] * 7, every=3, t_zero_offset=2.0)
    starts = [t for _, t, _ in got]
    ok &= check(abs(starts[0] - 2.0) < 1e-9, "最初の発話は収音開始時刻(セッション起点)から始まる")
    ok &= check(abs(starts[1] - (2.0 + 3 * W / mtgcommon.SAMPLE_RATE)) < 1e-9,
                "発話の時刻はサンプル数から出す")
    ok &= check([s for s, _, _ in got] == ["other"] * len(got), "サイドを付けて通知する")
    ok &= check(all(text == text.strip() for _, _, text in got), "本文の前後の空白を落とす")

    # Stopping mid-utterance still delivers it (7 windows: 2 cut + the remaining 1 on flush)
    ok &= check(len(got) == 3, "停止時に途中の発話も確定させる")

    # A failure inside the worker is reported, not swallowed
    tr = mtgcommon.LiveTranscriber("self", "x", session_zero=0.0, on_utterance=lambda *a: None)
    tr._t_zero = 0.0
    tr._queue.put(np.zeros(W, dtype=np.float32))
    tr._queue.put(None)

    class BrokenVad(FakeVad):
        def accept_waveform(self, samples):
            raise RuntimeError("boom")

    tr._run(FakeRecognizer(), BrokenVad())
    ok &= check(tr.error and "boom" in tr.error, "認識スレッドの例外を error に残す")
    ok &= check(not tr.alive(), "開始していなければ alive() は False")

    # The device is resolved by name, case-insensitively, by substring
    devices = [(0, "MacBook Proのマイク"), (4, "BlackHole 16ch"), (5, "BlackHole 2ch")]
    ok &= check(mtgcommon.resolve_device(devices, "blackhole 2ch") == (5, "BlackHole 2ch"),
                "デバイスは名前の部分一致で引く")
    tr = mtgcommon.LiveTranscriber("self", "UAB-80", session_zero=0.0)
    ok &= check(not tr.start(devices) and "UAB-80" in tr.error,
                "見つからないデバイスは理由付きで失敗する")

    # LiveLog: no utterance, no file; late arrivals after close are dropped
    with tempfile.TemporaryDirectory() as d:
        log = mtgcommon.LiveLog(Path(d) / "live.txt")
        ok &= check(log.close() is None and not (Path(d) / "live.txt").exists(),
                    "発話が無ければ空ログを残さない")
        log2 = mtgcommon.LiveLog(Path(d) / "live2.txt")
        log2.add(3.0, "相手", "い")
        log2.add(1.0, "自分", "あ")
        log2.close()
        log2.add(2.0, "自分", "遅れて届いた")
        ok &= check((Path(d) / "live2.txt").read_text() == "[00:01] 自分: あ\n[00:03] 相手: い\n",
                    "close で発話順に並べ替え、close 後の遅延発話は捨てる")

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
