#!/usr/bin/env python3
# Replays Vibe panes back into their conversation after a herdr server restart.
#
# herdr's own [session] resume_agents_on_restore types `<agent> --resume <id>`
# into every restored pane it holds an agent session for, but it only records
# one when the report names an agent it ships a resume command for and arrives
# from that agent's own integration source, `herdr:<agent>`. Vibe is not one of
# them, so `pane.report_agent_session` answers "ok" and drops the report, and
# Vibe panes come back as bare shells. scripts/herdr-agent-report.py parks the
# session id in the state directory below instead; this hook spends it.
#
# Runs from the plugin manifest's [[startup]] hook, which is the only signal a
# plugin gets that a restore happened: restored panes emit no pane_created,
# tab_created or workspace_created event (herdr 0.8.2), so an event hook has
# nothing to fire on.

import json
import os
import socket
import sys
import time
from pathlib import Path

# A pane is only safe to type into while nothing but its shell is running
# there. Restored panes are idle immediately, but the shell herdr spawns is
# wrapped in `direnv exec` (shared/programs/herdr.nix), so allow it a moment to
# settle rather than reading one busy sample as "occupied".
IDLE_TIMEOUT_SECONDS = 3.0
IDLE_POLL_SECONDS = 0.25

SOCKET_TIMEOUT_SECONDS = 2.0


def server_name(sock_path: str) -> str:
    # `herdr --session <name>` runs a server of its own, and pane ids restart
    # at w1:p1 in each one, so the parked entries have to be kept apart per
    # server. herdr keeps a named session's socket in
    # <config>/herdr/sessions/<name>/ and the default one directly in
    # <config>/herdr/, which makes the name readable straight off the path.
    directory = Path(sock_path).parent
    if directory.parent.name == "sessions":
        return directory.name
    return "default"


def state_dir(sock_path: str) -> Path:
    # Deliberately not HERDR_PLUGIN_STATE_DIR: herdr hands that path to the
    # plugin, but the writer at the other end is a Claude Code / Vibe hook that
    # never sees it — and herdr shares that directory across every server, which
    # is the one thing this path must not do. Both ends spell this out, so keep
    # them in step.
    base = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    return Path(base) / "herdr-vibe-resume" / "panes" / server_name(sock_path)


def herdr_call(sock_path: str, method: str, params: dict) -> dict:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(SOCKET_TIMEOUT_SECONDS)
    client.connect(sock_path)
    request = {"id": f"vibe-resume:{time.time_ns()}", "method": method, "params": params}
    try:
        client.sendall((json.dumps(request) + "\n").encode())
        buffer = b""
        while b"\n" not in buffer:
            chunk = client.recv(65536)
            if not chunk:
                break
            buffer += chunk
    finally:
        client.close()
    return json.loads(buffer.split(b"\n", 1)[0].decode())


def live_panes(sock_path: str) -> dict:
    reply = herdr_call(sock_path, "pane.list", {})
    panes = reply.get("result", {}).get("panes", [])
    return {pane["pane_id"]: pane for pane in panes if pane.get("pane_id")}


def wait_until_idle(sock_path: str, pane_id: str) -> bool:
    deadline = time.monotonic() + IDLE_TIMEOUT_SECONDS
    while True:
        info = herdr_call(sock_path, "pane.process_info", {"pane_id": pane_id})
        info = info.get("result", {}).get("process_info", {})
        shell = info.get("shell_pid")
        foreground = info.get("foreground_process_group_id")
        if shell is not None and shell == foreground:
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(IDLE_POLL_SECONDS)


def resume_pane(sock_path: str, pane: dict, entry: dict) -> None:
    # Same command shape as tools/agent-resume/agent-resume.sh: Vibe's
    # --resume takes the full session id as readily as the short one.
    command = f"{entry['agent']} --resume {entry['session_id']}"
    herdr_call(
        sock_path,
        "pane.send_text",
        {"pane_id": pane["pane_id"], "text": command + "\n"},
    )


def process(sock_path: str, path: Path, panes: dict) -> None:
    entry = json.loads(path.read_text())
    pane = panes.get(entry["pane_id"])
    if pane is None:
        # The pane the session was reported from is gone for good: herdr
        # restores pane ids verbatim, so an id missing here will not come back.
        path.unlink()
        return

    # A restore respawns the pane's terminal, so a terminal_id that still
    # matches the one already resumed into means no restart happened between
    # then and now and the conversation is either running or was dismissed.
    if pane.get("terminal_id") == entry.get("resumed_terminal_id"):
        return

    if not wait_until_idle(sock_path, pane["pane_id"]):
        print(f"{pane['pane_id']}: busy, left alone", file=sys.stderr)
        return

    resume_pane(sock_path, pane, entry)
    entry["resumed_terminal_id"] = pane.get("terminal_id")
    path.write_text(json.dumps(entry))
    print(f"{pane['pane_id']}: resumed {entry['agent']} {entry['session_id']}")


def main() -> None:
    sock_path = os.environ.get("HERDR_SOCKET_PATH", "")
    if not sock_path:
        return
    panes = live_panes(sock_path)
    for path in sorted(state_dir(sock_path).glob("*.json")):
        try:
            process(sock_path, path, panes)
        except (OSError, ValueError, KeyError) as err:
            # One unreadable or half-written entry must not cost the rest
            # their resume.
            print(f"{path.name}: {err}", file=sys.stderr)


if __name__ == "__main__":
    main()
