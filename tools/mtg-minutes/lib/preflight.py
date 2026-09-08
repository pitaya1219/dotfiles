"""会議の前提(音声経路と OBS)を整え、終わったら元に戻す。

mtg が録る2つの経路:

    self  … 物理マイク → OBS(RNNoise) → BlackHole 2ch
    other … 通話アプリ → システム出力 → 複数出力装置「会議用」 → BlackHole 16ch

どの link も「録音は完走したのに中身が無い」という形で壊れた実績がある。
これは取り得る中で最悪の壊れ方で、会議が終わるまで誰も気づけない。
ここで見るのはその3つだけ:

  1. BlackHole 2ch / 16ch がデバイス一覧に居ること。BlackHole のデバイスは
     専用の HAL helper プロセスに支えられており、アイドルな helper はメモリ
     逼迫時に jetsam に刈られる。以後デバイスはどの API からも消え、
     coreaudiod を再起動するまで戻らない
  2. 複数出力装置に BlackHole 16ch が入っていること。デバイスが不在の間に
     coreaudiod がメンバーから外し、その状態が *保存される* ので、デバイスが
     戻っても構成は戻らない
  3. OBS が起動し、BlackHole 2ch へモニタリングし、マイクを掴んでいること

OBS を会議のあいだだけ起動するのがこのモジュールの主目的でもある。一日中
常駐させておくとメモリを食い、その圧力がアイドルな 16ch の helper を刈る
= 1に戻る。
"""
import configparser
import plistlib
import re
import subprocess
import time
from pathlib import Path

from mtgcommon import info, warn

OBS_APP_NAME = "OBS"
OBS_CONFIG_DIR = Path.home() / "Library/Application Support/obs-studio"
OBS_LOG_DIR = OBS_CONFIG_DIR / "logs"
AUDIO_SETTINGS_PLIST = Path(
    "/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist")

# OBS が音声を開くまで。実測では起動から1秒かからないが、USB マイクが寝ていた
# 回は16秒かかった。遅い側に倍以上の余地を見ておく。
OBS_READY_TIMEOUT_SEC = 60
OBS_QUIT_TIMEOUT_SEC = 30
# coreaudiod 再起動後、デバイスが一覧に戻るまで
COREAUDIO_SETTLE_TIMEOUT_SEC = 20
POLL_SEC = 0.5

# OBS のログ行。監視先とデバイスの開閉はここでしか runtime の事実が取れない
# (保存済みの設定は「そう設定されている」ことしか言わない)。
OBS_MONITOR_HEAD_RE = re.compile(r"Audio monitoring device:\s*$")
OBS_MONITOR_NAME_RE = re.compile(r"^\s*name:\s*(.+?)\s*$")
OBS_DEVICE_INIT_RE = re.compile(r"coreaudio: Device '(.+?)' \[.*\] initialized")
OBS_DEVICE_LOST_RE = re.compile(r"coreaudio: device '(.+?)' disconnected or changed")
# 設定されたデバイスが居ないとき。OBS は2秒おきに再試行し続けるので、
# この行が出た時点で「待っても来ない」と判断してよい。
OBS_DEVICE_WAIT_RE = re.compile(
    r"coreaudio: failed to find device uid: (.+?), waiting for connection")
# 起動時に音声サブシステムが立ち上がった合図
OBS_AUDIO_UP_RE = re.compile(r"\[Loaded global audio device\]")


def _norm(text):
    """比較用に区切り文字と大小文字を落とす。

    デバイス名は表示名 ('BlackHole 16ch') と UID ('BlackHole16ch_UID') の
    どちらで出てくるかが場所によって違うので、両方を同じ土俵に乗せる。

    落とすのは記号・空白・アンダースコアだけ。ASCII 以外を落とすと
    '会議用' が空文字になり、どの装置とも一致してしまう。
    """
    return re.sub(r"[\W_]+", "", (text or "").lower(), flags=re.UNICODE)


def _matches(candidate, wanted):
    """candidate が wanted を指しているか。wanted が空なら常に False。"""
    needle = _norm(wanted)
    return bool(needle) and needle in _norm(candidate)


# ---------------------------------------------------------------- audio devices

def list_audio_devices(kind="input"):
    """SwitchAudioSource が見ているデバイス名の一覧。取れなければ None。"""
    try:
        res = subprocess.run(["SwitchAudioSource", "-a", "-t", kind],
                             capture_output=True, text=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    return [line.strip() for line in res.stdout.splitlines() if line.strip()]


def missing_devices(wanted, kind="input"):
    """wanted のうち一覧に無い名前。一覧が取れなければ None。"""
    devices = list_audio_devices(kind)
    if devices is None:
        return None
    return [name for name in wanted
            if not any(_matches(dev, name) for dev in devices)]


def hal_helpers():
    """生きている BlackHole 等の HAL helper プロセス名。

    デバイスが消える理由を説明するためだけに使う。判定そのものは
    デバイス一覧で行う(helper が居ても device が出ないことはあり得る)。
    """
    try:
        res = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True)
    except OSError:
        return []
    return [line.strip() for line in res.stdout.splitlines()
            if "Core Audio Driver" in line]


def restart_coreaudiod(wanted, timeout=COREAUDIO_SETTLE_TIMEOUT_SEC):
    """coreaudiod を再起動して HAL プラグインを読み直させる。

    死んでいるのはデバイスではなく helper プロセスなので、これ以外に戻す手が
    無い(再インストールは不要)。sudo が要るのでターミナルでパスワードを聞かれる。
    """
    info("coreaudiod を再起動します(sudo のパスワードを聞かれます)")
    try:
        subprocess.run(["sudo", "killall", "coreaudiod"], check=True)
    except FileNotFoundError:
        warn("sudo が見つかりませんでした。")
        return False
    except subprocess.CalledProcessError as exc:
        warn(f"coreaudiod の再起動に失敗しました (rc={exc.returncode})。")
        return False

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if missing_devices(wanted) == []:
            return True
        time.sleep(POLL_SEC)
    return False


def multi_output_members(name):
    """複数出力装置 name の構成メンバー名。定義が見つからなければ None。

    メンバーは name を持たないことがある(内蔵ヘッドフォン出力など)ので、
    その場合は uid を代わりに返す。呼び出し側は _matches で照合する。
    """
    try:
        settings = plistlib.loads(AUDIO_SETTINGS_PLIST.read_bytes())
    except (OSError, plistlib.InvalidFileException):
        return None
    for key, value in settings.items():
        if not key.startswith("MetaDevice") or not isinstance(value, dict):
            continue
        if not _matches(value.get("name"), name):
            continue
        return [sub.get("name") or sub.get("uid")
                for sub in value.get("subdevices", []) if isinstance(sub, dict)]
    return None


# ------------------------------------------------------------------------ OBS

def obs_pid():
    res = subprocess.run(["pgrep", "-x", OBS_APP_NAME], capture_output=True, text=True)
    first = res.stdout.split()
    return int(first[0]) if first else None


def obs_logs():
    """OBS のログファイル。存在しなければ空。"""
    try:
        return set(OBS_LOG_DIR.glob("*.txt"))
    except OSError:
        return set()


def newest_obs_log(among=None):
    """一番新しい OBS ログ。among を渡すとその中から選ぶ。

    起動を待つときは「今回の起動で増えたログ」を among に渡す。mtime の
    新しさで選ぶと、直前に終了した OBS のログを掴んでしまう(終了時刻は
    たった今なので、どんな時刻の猶予を置いても区別がつかない)。
    """
    logs = obs_logs() if among is None else among
    if not logs:
        return None
    try:
        return max(logs, key=lambda path: path.stat().st_mtime)
    except OSError:
        return None


def obs_log_state(log):
    """OBS ログから、監視先と各デバイスの最後の開閉イベントを読む。

    設定ファイルではなくログを読むのは、実際に効いている状態が要るため。
    「マイクを挿し直したらモニタリングが復帰しない」という実障害は、設定上は
    正常なまま起きる。ログには disconnected が残るので判別できる。
    """
    state = {"monitoring_device": None, "devices": {}, "audio_up": False}
    try:
        lines = log.read_text(errors="replace").splitlines()
    except OSError:
        return state
    events = []
    expect_name = False
    for line in lines:
        if expect_name:
            m = OBS_MONITOR_NAME_RE.search(line.split(": ", 1)[-1])
            if m:
                state["monitoring_device"] = m.group(1)
            expect_name = False
            continue
        if OBS_MONITOR_HEAD_RE.search(line):
            expect_name = True
            continue
        if OBS_AUDIO_UP_RE.search(line):
            state["audio_up"] = True
            continue
        m = OBS_DEVICE_INIT_RE.search(line)
        if m:
            events.append(("initialized", m.group(1)))
            continue
        m = OBS_DEVICE_LOST_RE.search(line)
        if m:
            events.append(("disconnected", m.group(1)))
            continue
        m = OBS_DEVICE_WAIT_RE.search(line)
        if m:
            events.append(("waiting", m.group(1)))

    # 状態はイベント順に畳む。デバイスごとの上書きだけでは「探している」が
    # 解消できない: OBS は待つときは uid で、開いたときは表示名で書くので、
    # 同じデバイスでもキーが違って上書きにならない。入力が1つでも開いたら、
    # それ以前の「探している」は解消したと見なす(OBS のソースを別のマイクに
    # 差し替えた場合がこれで、古い uid を待つ行がログに残り続ける)。
    # 監視先の初期化では解消しない。マイク不在のときに開くのは監視先だけなので、
    # これを数えると不在を見逃す。
    for status, name in events:
        if status == "initialized" and not _matches(name, state["monitoring_device"]):
            for waiting in [n for n, s in state["devices"].items() if s == "waiting"]:
                del state["devices"][waiting]
        state["devices"][name] = status
    return state


def obs_audio_ready(state):
    """OBS が入力について結論を出したか(ログから読んだ state で判断)。

    音声サブシステムが上がっただけでは足りない。マイクが開くのはその前後で、
    実機では起動から1秒かからないこともあれば 16 秒かかることもあった
    (遅い側は USB マイクが寝ていたとき)。開く前に録音を始めると自分側の頭が
    落ちるので、入力デバイスが開くところまで待つ。

    監視先(BlackHole 2ch)を数から外すのは、それが入力ではなくモニタリングの
    出力先だから。マイクが不在のときは監視先だけが初期化されるので、これを
    数に入れると「マイクが無いのに準備完了」になる。

    待ちを打ち切る条件が2つあるのは、マイクが来ない場合があるため。
    設定されたデバイスが居ないと OBS は "waiting for connection" を出して
    2秒おきに再試行し続ける。この行が出たら待っても状況は変わらないので、
    準備完了として扱い、理由は _check_obs が警告する。
    """
    if not state["audio_up"]:
        return False
    monitoring = state["monitoring_device"]
    return any(
        (status == "initialized" and not _matches(name, monitoring))
        or status == "waiting"
        for name, status in state["devices"].items())


def obs_confirm_on_exit():
    """OBS の「終了時に確認」設定。読めなければ None。"""
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(OBS_CONFIG_DIR / "user.ini", encoding="utf-8")
    except (OSError, configparser.Error):
        return None
    value = parser.get("General", "ConfirmOnExit", fallback=None)
    return None if value is None else value.strip().lower() == "true"


def start_obs(timeout=OBS_READY_TIMEOUT_SEC):
    """OBS を起動し、音声が立ち上がるまで待つ。

    戻り値は (起動したか, 準備できたか)。既に動いていたら (False, True)。
    """
    if obs_pid() is not None:
        return False, True
    known_logs = obs_logs()
    info("OBS を起動します")
    try:
        subprocess.run(["open", "-a", OBS_APP_NAME], check=True,
                       capture_output=True, text=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        warn(f"OBS を起動できませんでした: {exc}")
        return False, False

    # プロセスの出現ではなく「ログに音声デバイスが載った」ことを待つ。
    # 起動直後は音声がまだ開いておらず、そこで録音を始めると自分側の頭が
    # 落ちる。ログはそれを外から観測できる唯一の手段(WebSocket は無効)。
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        log = newest_obs_log(among=obs_logs() - known_logs)
        if log is not None and obs_audio_ready(obs_log_state(log)):
            return True, True
        time.sleep(POLL_SEC)
    warn(f"OBS の音声が {timeout} 秒で立ち上がりませんでした。"
         "自分側が無音になるかもしれません。")
    return obs_pid() is not None, False


def quit_obs(timeout=OBS_QUIT_TIMEOUT_SEC):
    """OBS を終了する。終了できたら True。

    osascript の戻り値は見ない。実機では終了できているのに
    -128 (ユーザによってキャンセルされました) を返すため、
    成否はプロセスが消えたかどうかだけで判定する。
    """
    if obs_pid() is None:
        return True
    info("OBS を終了します")
    subprocess.run(["osascript", "-e", f'quit app "{OBS_APP_NAME}"'],
                   capture_output=True, text=True)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if obs_pid() is None:
            return True
        time.sleep(POLL_SEC)
    hint = ""
    if obs_confirm_on_exit():
        hint = "(OBS の「終了時に確認」が有効です。ダイアログが出ていないか確認してください)"
    warn(f"OBS が {timeout} 秒で終了しませんでした。{hint}")
    return False


# ---------------------------------------------------------------- orchestration

class Preflight:
    """会議前の点検と、直せるものの復旧。

    致命的なもの(problems)と、録音は続けられるが劣化するもの(notes)を分ける。
    録音の片側が丸ごと無音になる条件だけを problems に入れる: そこで止めないと
    「完走したのに中身が無い」という、会議が終わるまで気づけない失敗になる。
    OBS まわりを notes に留めるのは、自分側が落ちても相手側の録音と議事録は
    成立するのと、判定材料がログという間接的なものだからでもある。
    """

    def __init__(self, self_device, other_device, output_device,
                 manage_obs=True, fix=True):
        self.self_device = self_device
        self.other_device = other_device
        self.output_device = output_device
        self.manage_obs = manage_obs
        self.fix = fix
        self.problems = []
        self.notes = []
        self.started_obs = False
        self._obs_was_running = False

    def _problem(self, message):
        self.problems.append(message)
        warn(message)

    def _note(self, message):
        self.notes.append(message)
        warn(message)

    def run(self):
        """点検を順に回す。致命的な問題が無ければ True。

        順番には意味がある。coreaudiod を再起動するとデバイスが総取り替えに
        なるので、複数出力装置の確認も OBS の起動もその後でなければならない。
        """
        self._obs_was_running = obs_pid() is not None
        self._check_capture_devices()
        self._check_meeting_output()
        if self.manage_obs:
            self._check_obs()
        return not self.problems

    def _check_capture_devices(self):
        wanted = [self.self_device, self.other_device]
        missing = missing_devices(wanted)
        if missing is None:
            self._note("SwitchAudioSource が無いため音声デバイスを確認できませんでした。")
            return
        if not missing:
            return

        warn(f"音声デバイスが見つかりません: {', '.join(missing)}")
        helpers = hal_helpers()
        warn("生きている HAL helper: " + (", ".join(helpers) if helpers else "なし"))
        warn("BlackHole の helper がメモリ逼迫で停止したときの症状です。")
        if not self.fix:
            self._problem("coreaudiod の再起動が必要です: sudo killall coreaudiod")
            return

        # OBS が掴んだままだと、再起動後に握り直されないデバイスが残る。
        # 閉じてよいのは _check_obs が起動し直す場合だけ。--no-obs のときに
        # 閉じると、開いたままより悪い状態(誰も起動しない)で終わる。
        if obs_pid() is not None:
            if self.manage_obs:
                info("coreaudiod の再起動前に OBS を終了します")
                quit_obs()
            else:
                warn("OBS がデバイスを掴んだままです。再起動後に"
                     "モニタリングが戻らないことがあります。")

        if restart_coreaudiod(wanted):
            info(f"音声デバイスが復帰しました: {', '.join(missing)}")
        else:
            self._problem(
                f"coreaudiod を再起動しても {', '.join(missing)} が戻りませんでした。")

    def _check_meeting_output(self):
        members = multi_output_members(self.output_device)
        if members is None:
            self._note(f"複数出力装置 '{self.output_device}' の定義を読めませんでした。")
        elif not any(_matches(member, self.other_device) for member in members):
            listed = ", ".join(members) or "なし"
            self._problem(
                f"複数出力装置 '{self.output_device}' の構成に "
                f"{self.other_device} が入っていません(現在: {listed})。")
            warn("デバイスが不在の間に coreaudiod がメンバーから外した可能性が"
                 "あります。その場合、デバイスが戻っても構成は復活しません。")
            warn(f"Audio MIDI 設定を開いて '{self.output_device}' の "
                 f"{self.other_device} にチェックを入れ直してください"
                 "(コマンドからは直せません)。")
            return

        outputs = list_audio_devices("output")
        if outputs is None:
            return
        if not any(_matches(device, self.output_device) for device in outputs):
            self._problem(
                f"複数出力装置 '{self.output_device}' が出力デバイス一覧にありません。"
                "相手の声がどこにも届きません。")

    def _check_obs(self):
        if not self.fix:
            if obs_pid() is None:
                self._note("OBS が起動していません。自分側は無音になります。")
        else:
            started, _ready = start_obs()
            self.started_obs = started and not self._obs_was_running

        log = newest_obs_log()
        if log is None:
            self._note("OBS のログが見つからないため、監視先を確認できませんでした。")
            return
        state = obs_log_state(log)

        monitoring = state["monitoring_device"]
        if monitoring is None:
            self._note("OBS の監視先をログから読めませんでした。")
        elif not _matches(monitoring, self.self_device):
            self._note(f"OBS の監視先が '{monitoring}' です。"
                       f"自分側は {self.self_device} から録るので、"
                       "OBS の設定 → 音声 → モニタリングデバイスを直してください。")

        waiting = [name for name, status in state["devices"].items()
                   if status == "waiting"]
        if waiting:
            self._note(f"OBS が {', '.join(waiting)} を探し続けています。"
                       "マイクが接続されていません。このまま録ると自分側は無音になります。")

        lost = [name for name, status in state["devices"].items()
                if status == "disconnected"]
        if lost:
            self._note(f"OBS のデバイス {', '.join(lost)} が切断されたままです。"
                       "OBS でモニタリングを OFF→ON し直さないと音が流れません。")

    def teardown(self, keep_obs=False):
        """会議後、こちらが起動したものだけ元に戻す。

        自分で開いていた OBS を落とされると困る(配信や録画に使っている)ので、
        点検の時点で動いていなかった場合しか終了させない。
        """
        if self.started_obs and not keep_obs:
            quit_obs()
        self.started_obs = False

    def report(self):
        if not self.problems and not self.notes:
            info("前提の点検: 問題なし")
