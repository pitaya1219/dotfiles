#!/usr/bin/env python3
"""whisper-stream の出力パースの回帰テスト。

    python3 tools/mtg-minutes/tests/test_parse.py

このテストがある理由: 当初 whisper-stream の出力形式を推測で実装し、
スタブもその推測で書いたため、スタブは通るのに実機で壊れる状態になった。
ここでは実機から取った生の出力をそのまま固定データとして流し込む。

実機の仕様(stream.cpp v1.8.7):
  - [Start speaking] は printf なので stdout に出る(stderr ではない)
  - no_timestamps = !use_vad。--step 0(VAD)ではセグメントに
    [hh:mm:ss.mmm --> hh:mm:ss.mmm] が付く。外すCLIオプションは無い
  - VAD経路は audio.clear() を呼ばず直近 length_ms を読み直すので、
    連続チャンクが重なり同じ発言が繰り返し出る
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import mtgcommon  # noqa: E402

# 実機(会議中)の相手側 stdout。重なりも誤変換のゆらぎもそのまま。
REAL_OUTPUT = """\
[Start speaking]

### Transcription 1 START | t0 = 0 ms | t1 = 10000 ms

[00:00:00.000 --> 00:00:04.000]  ハヤツさんにメッションつけて確認の依頼を投げようと思いますというところと
[00:00:04.000 --> 00:00:10.000]  あとはコードベースのシークレットマネージャーで管理する
### Transcription 1 END

### Transcription 2 START | t0 = 3000 ms | t1 = 13000 ms

[00:00:00.000 --> 00:00:05.640]  ところと あとはコードレベルにあった データベースのシークレットマネージャー
[00:00:05.640 --> 00:00:06.880]  で管理する件ですね
[00:00:06.880 --> 00:00:10.000]  うちもコメントの
### Transcription 2 END

### Transcription 3 START | t0 = 7000 ms | t1 = 17000 ms

[00:00:00.000 --> 00:00:04.000]  シークレットマネージャーで管理 する件ですね
[00:00:04.000 --> 00:00:07.000]  こっちもコメント残ってないか
[00:00:07.000 --> 00:00:10.000]  今だと私のコードアウトアウトアウトして
### Transcription 3 END

### Transcription 4 START | t0 = 14000 ms | t1 = 24000 ms

[00:00:00.000 --> 00:00:03.440]  こっちもコメント残ってないか
[00:00:03.440 --> 00:00:10.000]  今だと私のコードアウトアウンラップして平文でパスワードを書き込んでたって
[00:00:10.000 --> 00:00:10.000]  [BLANK_AUDIO]
### Transcription 4 END
"""


class FakeProc:
    """LiveTranscriber が読む stdout/stderr だけを持つ最小の偽プロセス"""

    def __init__(self, stdout_text):
        self.stdout = iter(stdout_text.splitlines(keepends=True))
        self.stderr = iter(())

    def poll(self):
        return None


def parse(stdout_text):
    tr = mtgcommon.LiveTranscriber("other", 0, "/dev/null")
    got = []
    tr.on_utterance = lambda side, t, text: got.append((side, round(t, 3), text))
    tr.session_zero = time.monotonic()
    tr.proc = FakeProc(stdout_text)
    tr._read_stdout()
    return tr, got


def check(cond, label):
    print(f"  {'ok  ' if cond else 'FAIL'} {label}")
    return cond


def main():
    tr, got = parse(REAL_OUTPUT)
    texts = [t for _, _, t in got]
    ok = True

    print("パース結果:")
    for _, t, text in got:
        print(f"    [{mtgcommon.format_ts(t)}] {text}")
    print("検査:")

    ok &= check(tr.ready and tr.t_zero is not None,
                "[Start speaking] を stdout から拾って ready になる")
    ok &= check(not any("-->" in t or t.startswith("[0") for t in texts),
                "本文にセグメントのタイムスタンプが混ざらない")
    ok &= check(not any("BLANK_AUDIO" in t for t in texts),
                "非発話マーカーが落ちる")
    # 重なりの除去: 同じ発言が2回以上出ないこと
    ok &= check(sum("ハヤツ" in t for t in texts) == 1, "重複した発言が1回だけになる")
    ok &= check(sum("こっちもコメント残ってないか" in t for t in texts) == 1,
                "チャンクを跨いだ重複が除去される")
    # 末尾の新規発言は残る(消しすぎていない)
    ok &= check(any("パスワードを書き込んでた" in t for t in texts),
                "新しい発言は落とさない")
    ok &= check([t for _, t, _ in got] == sorted(t for _, t, _ in got),
                "発話開始時刻が単調増加する")

    # タイムスタンプ無しモード(--step > 0)でも本文を落とさない
    _, plain = parse("[Start speaking]\nこんにちは\n")
    ok &= check([t for _, _, t in plain] == ["こんにちは"],
                "タイムスタンプ無しの出力も拾える")

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
