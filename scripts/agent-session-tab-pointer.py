#!/usr/bin/env python3
# Records the authoritative session_id for the current nvim-managed agent
# terminal tab, so the nvim tabline and RocketChat notifications never have
# to guess it (via terminal-buffer text scanning or log-directory mtimes).
#
# Called from:
#   - Claude Code's SessionStart hook   (~/.claude/settings.json)
#   - Mistral Vibe's post_agent hook    (~/.vibe/hooks.toml)
#
# Consumed by:
#   - shared/programs/neovim/plugin/90_claude.lua
#   - shared/programs/neovim/plugin/92_vibe.lua
#
# nvim tags each termopen() it starts for claude/vibe with a unique
# AGENT_TAB_MARKER env var. That var flows down through the shell into the
# agent process and, in turn, into every hook subprocess the agent spawns
# (hooks inherit the parent process environment). This script reads the
# marker plus session_id from the hook's JSON stdin and writes it to a
# pointer file nvim polls for — no guessing required on either side.
#
# Usage: agent-session-tab-pointer.py

import json
import os
import sys
import tempfile
import time

POINTER_DIR = "/tmp/agent-tab-sessions"


def main() -> None:
    marker = os.environ.get("AGENT_TAB_MARKER", "")
    if not marker:
        # Not launched from a marker-tagged nvim tab; nothing to record.
        return

    out_path = os.path.join(POINTER_DIR, f"{marker}.json")
    if os.path.exists(out_path):
        # Already resolved for this tab (Vibe's pre_tool hook re-fires on
        # every tool call in the session) — nothing left to do.
        return

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    session_id = payload.get("session_id", "")
    if not session_id:
        return

    data = {"session_id": session_id, "updated_at": time.time()}

    os.makedirs(POINTER_DIR, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=POINTER_DIR)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(tmp_path, out_path)
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
