#!/usr/bin/env python3
"""前提点検(preflight)のパース部分の回帰テスト。

    python3 tools/mtg-minutes/tests/test_preflight.py

固定データは実機から取ったものをそのまま使う。ここで見ている3つは、
どれも「推測で書くと通るのに実機で外れる」性質のものだった:

  - 複数出力装置のメンバーは name を持たないことがある(内蔵ヘッドフォン出力)。
    uid でしか照合できないので、表示名と uid を同じ土俵に乗せる必要がある
  - OBS の監視先はログの「Audio monitoring device:」の *次の行* にある
  - OBS のマイクは起動から 0.4 秒で開くこともあれば 16 秒かかることもあり、
    その間に切断→再接続が挟まる。最後のイベントだけが現在の状態を表す
"""
import plistlib
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import preflight  # noqa: E402

# 実機の /Library/Preferences/Audio/com.apple.audio.SystemSettings.plist から、
# 複数出力装置「会議用」の定義だけを抜いたもの。先頭メンバーに name が無い。
MEETING_DEVICE_PLIST = {
    "device.BlackHole16ch_UID": {"volume": 1.0},
    "MetaDevice.~:AMS2_StackedOutput:0": {
        "name": "会議用",
        "stacked": 1,
        "subdevices": [
            {"drift": 1, "uid": "BuiltInHeadphoneOutputDevice"},
            {"drift": 0, "name": "BlackHole 16ch", "uid": "BlackHole16ch_UID"},
            {"drift": 1, "name": "YYK-526", "uid": "27-55-F9-A6-EE-EA:output"},
        ],
    },
}

# 16ch が刈られていた間に構成から外された状態(2026-09-07 の実障害)。
BROKEN_DEVICE_PLIST = {
    "MetaDevice.~:AMS2_StackedOutput:0": {
        "name": "会議用",
        "stacked": 1,
        "subdevices": [{"drift": 1, "uid": "BuiltInHeadphoneOutputDevice"}],
    },
}

# 実機の OBS ログ。マイクが起動 16 秒後にようやく開き、その後で切断された回。
OBS_LOG_LOST_MIC = """\
15:59:44.185: [macOS] Permission for audio device access granted.
15:59:44.776: Audio monitoring device:
15:59:44.776: \tname: BlackHole 2ch
15:59:44.776: \tid: BlackHole2ch_UID
15:59:46.873: coreaudio: Device 'MacBook Proのマイク' [48000 Hz] initialized
15:59:46.916: [Loaded global audio device]: 'NoiseC'
16:00:00.654: coreaudio: Device 'UAB-80' [48000 Hz] initialized
16:03:40.837: coreaudio: device 'UAB-80' disconnected or changed.  attempting to reconnect
"""

# 同じ環境の正常な回。マイクは 0.4 秒で開き、切断は無い。
OBS_LOG_HEALTHY = """\
16:19:34.828: Audio monitoring device:
16:19:34.828: \tname: BlackHole 2ch
16:19:34.828: \tid: BlackHole2ch_UID
16:19:35.250: coreaudio: Device 'UAB-80' [48000 Hz] initialized
16:19:35.283: [Loaded global audio device]: 'NoiseC'
"""

# マイクが繋がっていない回(2026-09-08 の実ログ)。OBS は2秒おきに再試行し続け、
# 初期化されるのは監視先の BlackHole 2ch だけ。待っても状況は変わらない。
OBS_LOG_NO_MIC = """\
21:54:42.370: Audio monitoring device:
21:54:42.370: \tname: BlackHole 2ch
21:54:42.835: coreaudio: failed to find device uid: AppleUSBAudioEngine:Sony Corporation:UAB-80:1110000:2,1, waiting for connection
21:54:42.866: [Loaded global audio device]: 'NoiseC'
21:55:00.857: coreaudio: Device 'BlackHole 2ch' [48000 Hz] initialized
"""

# OBS のソースを別のマイクに差し替えた回(2026-09-08 の実ログ)。UAB-80 を待つ行は
# ログに残り続けるが、そのあと YYK-526 が開いているので探し物は解消している。
# OBS は待つときは uid、開いたときは表示名で書くので、キーの上書きでは消えない。
OBS_LOG_SWITCHED_MIC = """\
22:42:42.132: Audio monitoring device:
22:42:42.132: \tname: BlackHole 2ch
22:42:43.305: coreaudio: failed to find device uid: AppleUSBAudioEngine:Sony Corporation:UAB-80:1110000:2,1, waiting for connection
22:42:43.355: [Loaded global audio device]: 'NoiseC'
22:42:52.239: coreaudio: Device 'BlackHole 2ch' [48000 Hz] initialized
22:44:55.880: coreaudio: Device 'YYK-526' [16000 Hz] initialized
"""

# 監視先も音声も、まだ何も出ていない起動直後。
OBS_LOG_STARTING = """\
16:19:34.185: [macOS] Permission for audio device access granted.
16:19:34.189: OBS 32.0.1 (mac)
"""


def check(cond, label):
    print(f"  {'ok  ' if cond else 'FAIL'} {label}")
    return cond


def log_state(text):
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "obs.txt"
        path.write_text(text)
        return preflight.obs_log_state(path)


def members(data):
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "settings.plist"
        path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
        original = preflight.AUDIO_SETTINGS_PLIST
        preflight.AUDIO_SETTINGS_PLIST = path
        try:
            return preflight.multi_output_members("会議用")
        finally:
            preflight.AUDIO_SETTINGS_PLIST = original


def main():
    ok = True

    print("複数出力装置のメンバー")
    healthy = members(MEETING_DEVICE_PLIST)
    ok &= check(healthy == ["BuiltInHeadphoneOutputDevice", "BlackHole 16ch", "YYK-526"],
                "name の無いメンバーは uid で埋める")
    ok &= check(any(preflight._matches(m, "BlackHole 16ch") for m in healthy),
                "表示名で 16ch が居ると分かる")
    broken = members(BROKEN_DEVICE_PLIST)
    ok &= check(not any(preflight._matches(m, "BlackHole 16ch") for m in broken),
                "外された構成では 16ch が見つからない")
    ok &= check(members({"MetaDevice.x": {"name": "別の装置", "subdevices": []}}) is None,
                "名前が違う装置は拾わない")
    ok &= check(preflight._matches("BlackHole16ch_UID", "BlackHole 16ch"),
                "uid と表示名を同一視する")
    ok &= check(not preflight._matches("BlackHole 2ch", "BlackHole 16ch"),
                "2ch を 16ch と取り違えない")
    # 記号だけを落とす正規化にしている理由。ASCII 以外まで落とすと '会議用' が
    # 空文字になり、どの装置とも一致してしまう。
    ok &= check(preflight._matches("会議用", "会議用")
                and not preflight._matches("BlackHole 2ch", "会議用"),
                "日本語のデバイス名が空文字に潰れない")

    print("OBS ログ")
    lost = log_state(OBS_LOG_LOST_MIC)
    ok &= check(lost["monitoring_device"] == "BlackHole 2ch",
                "監視先を『Audio monitoring device:』の次の行から読む")
    ok &= check(lost["devices"].get("UAB-80") == "disconnected",
                "初期化のあとに来た切断が最後の状態として残る")
    ok &= check(lost["devices"].get("MacBook Proのマイク") == "initialized",
                "切断されていないデバイスは初期化のまま")
    ok &= check(lost["audio_up"], "音声サブシステムの起動を検出する")

    healthy_log = log_state(OBS_LOG_HEALTHY)
    ok &= check(healthy_log["devices"] == {"UAB-80": "initialized"},
                "正常な回に切断は残らない")
    ok &= check(preflight.obs_audio_ready(healthy_log), "正常な回は準備完了と判定")

    starting = log_state(OBS_LOG_STARTING)
    ok &= check(starting["monitoring_device"] is None and not starting["audio_up"],
                "起動直後はまだ何も分からない")
    ok &= check(not preflight.obs_audio_ready(starting), "起動直後は準備完了にしない")

    # 音声サブシステムだけ上がってマイクがまだ開いていない状態。ここで録り
    # 始めると自分側の頭が落ちるので、準備完了にしてはいけない。
    half = log_state(OBS_LOG_HEALTHY.replace(
        "16:19:35.250: coreaudio: Device 'UAB-80' [48000 Hz] initialized\n", ""))
    ok &= check(half["audio_up"] and not preflight.obs_audio_ready(half),
                "マイクが開くまでは準備完了にしない")

    no_mic = log_state(OBS_LOG_NO_MIC)
    ok &= check(no_mic["devices"].get(
        "AppleUSBAudioEngine:Sony Corporation:UAB-80:1110000:2,1") == "waiting",
                "見つからないデバイスを waiting として拾う")
    # 監視先(BlackHole 2ch)は入力ではないので、これが開いただけでは
    # 準備完了にならない。打ち切るのは waiting を見たからで、60秒待たない。
    ok &= check(no_mic["devices"].get("BlackHole 2ch") == "initialized"
                and preflight.obs_audio_ready(no_mic),
                "マイクが来ないと分かった時点で待ちを打ち切る")

    switched = log_state(OBS_LOG_SWITCHED_MIC)
    ok &= check(not any(s == "waiting" for s in switched["devices"].values()),
                "別のマイクが開いたら古い waiting は解消する")
    ok &= check(switched["devices"].get("YYK-526") == "initialized"
                and preflight.obs_audio_ready(switched),
                "差し替えたマイクで準備完了になる")
    # 監視先(BlackHole 2ch)は waiting のあとに開いているが、これで解消しては
    # いけない。マイク不在のときに開くのは監視先だけなので不在を見逃す。
    ok &= check(no_mic["devices"].get(
        "AppleUSBAudioEngine:Sony Corporation:UAB-80:1110000:2,1") == "waiting",
                "監視先が開いただけでは waiting を解消しない")

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
