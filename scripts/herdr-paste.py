#!/usr/bin/env python3
# Herdr ships a tmux-style copy mode but no paste counterpart, so prefix+] is
# bound to this script instead. It pastes the register scripts/herdr-copy.sh
# writes, or the system clipboard, which is where herdr's own copy mode yanks.
#
# The text is handed over through the socket API's pane.send_input rather than
# `herdr pane send-text`, because send_input is the only entry point that wraps
# the payload in the pane's live bracketed-paste mode; without it a multi-line
# paste reaches the pane as a burst of Enter presses and an agent prompt
# submits itself line by line.

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path

DEFAULT_SESSION_NAME = "default"

CLIPBOARD_READERS = [
    ["pbpaste"],
    ["wl-paste", "--no-newline"],
    ["xclip", "-selection", "clipboard", "-out"],
    ["xsel", "--clipboard", "--output"],
]


def socket_path():
    """Resolve the API socket the way herdr's own client does.

    Herdr exports HERDR_SOCKET_PATH to every custom-command keybinding, so the
    rest of this only matters when the script is run by hand from a shell.
    """
    override = os.environ.get("HERDR_SOCKET_PATH")
    if override:
        return Path(override)
    config_home = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
    config_dir = Path(config_home) / "herdr"
    session = os.environ.get("HERDR_SESSION")
    if session and session != DEFAULT_SESSION_NAME:
        return config_dir / "sessions" / session / "herdr.sock"
    return config_dir / "herdr.sock"


def request(method, params):
    payload = json.dumps({"id": f"herdr-paste:{method}", "method": method, "params": params})
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(str(socket_path()))
        sock.sendall(payload.encode() + b"\n")
        buffered = b""
        while b"\n" not in buffered:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buffered += chunk
    response = json.loads(buffered.split(b"\n", 1)[0])
    if "error" in response:
        raise SystemExit(f"herdr {method} failed: {response['error']}")
    return response.get("result", {})


def clipboard_text():
    for reader in CLIPBOARD_READERS:
        if shutil.which(reader[0]) is None:
            continue
        result = subprocess.run(reader, capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout
    raise SystemExit("no clipboard reader available")


def register_path():
    override = os.environ.get("HERDR_PASTE_REGISTER")
    if override:
        return Path(override)
    state_home = os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local" / "state")
    return Path(state_home) / "herdr" / "paste-register"


def main():
    parser = argparse.ArgumentParser(description="Paste into the focused herdr pane.")
    parser.add_argument(
        "--source",
        choices=["register", "clipboard"],
        default="register",
        help="register falls back to the clipboard until scripts/herdr-copy.sh has run once",
    )
    args = parser.parse_args()

    text = ""
    if args.source == "register":
        register = register_path()
        text = register.read_text() if register.is_file() else ""
    if not text:
        text = clipboard_text()
    if not text:
        return

    # Herdr captures the invoking pane in HERDR_ACTIVE_PANE_ID before running
    # the keybinding, which stays right even for commands that steal focus.
    pane_id = os.environ.get("HERDR_ACTIVE_PANE_ID")
    if not pane_id:
        pane_id = request("session.snapshot", {})["snapshot"]["focused_pane_id"]
    request("pane.send_input", {"pane_id": pane_id, "text": text})


if __name__ == "__main__":
    sys.exit(main())
