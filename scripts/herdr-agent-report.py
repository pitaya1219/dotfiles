#!/usr/bin/env python3
# Reports the authoritative session_id and lifecycle state of the current agent
# to herdr, so the sidebar never has to guess either one (via terminal-buffer
# text scanning or log-directory mtimes).
#
# Called from:
#   - Claude Code's SessionStart hook   (~/.claude/settings.json)
#   - Mistral Vibe's pre_tool hook      (~/.vibe/hooks.toml)
#   - Mistral Vibe's post_agent hook    (~/.vibe/hooks.toml)
#
# Consumed by:
#   - herdr's sidebar, via the socket API
#       shared/programs/herdr.nix  ($session token in ui.sidebar.agents.rows)
#
# herdr tags each pane's shell with HERDR_PANE_ID and HERDR_SOCKET_PATH, and
# those flow down through the shell into the agent process and, in turn, into
# every hook subprocess the agent spawns (hooks inherit the parent process
# environment). Both are absent when the agent runs from a bare terminal, and
# then this script does nothing.
#
# Usage: herdr-agent-report.py --agent <label> [--state <status>]

import argparse
import json
import os
import random
import socket
import sys
import time
from pathlib import Path

# Identifies this reporter to herdr, which arbitrates between sources when
# more than one claims the same pane.
HERDR_SOURCE = "dotfiles:agent-session"

# The source herdr's own `integration install <agent>` hook would report from.
# pane.report_agent_session is the one call that will not take HERDR_SOURCE:
# herdr answers any other source "ok" and drops it, so a session reported under
# our own name never reaches [session] resume_agents_on_restore. Borrowing the
# official name is what makes the restore work, and it is ours to borrow —
# `integration install claude` cannot run here, because it rewrites
# ~/.claude/settings.json, which is a read-only symlink into the Nix store.
#
# Only agents herdr ships a resume command for are accepted; measured on 0.8.2:
# claude, codex, copilot, cursor, devin, droid, grok, hermes, qodercli, qwen.
# Anything else — Vibe included — is dropped whatever the source, and falls
# back to park_session() below.
HERDR_SESSION_SOURCES = {"claude": "herdr:claude"}

# Where the sessions herdr refuses to hold are parked for the vibe-resume
# plugin to replay on the next server start. Spelled out in
# tools/herdr-vibe-resume/vibe-resume.py too, which reads it — herdr hands the
# plugin its own HERDR_PLUGIN_STATE_DIR, but a hook subprocess never sees it,
# and that directory is shared by every server anyway.
PARKED_SESSION_DIR = "herdr-vibe-resume/panes"

# A full UUID would crowd the agent label out of a sidebar row that is 26
# columns wide by default.
SESSION_TOKEN_CHARS = 8


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--agent",
        required=True,
        help="Agent label to report to herdr (matches herdr's canonical id "
        "where one exists, e.g. claude).",
    )
    parser.add_argument(
        "--state",
        choices=("working", "idle", "blocked"),
        default="",
        help="Lifecycle state to report to herdr. Omit for agents herdr "
        "detects on its own — see report_to_herdr().",
    )
    return parser.parse_args()


def read_payload() -> dict:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return {}
    return payload if isinstance(payload, dict) else {}


def herdr_call(sock_path: str, method: str, params: dict) -> None:
    request = {
        "id": f"{HERDR_SOURCE}:{time.time_ns()}:{random.randrange(1_000_000):06d}",
        "method": method,
        "params": params,
    }
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(0.5)
        client.connect(sock_path)
        client.sendall((json.dumps(request) + "\n").encode())
        try:
            client.recv(4096)
        except OSError:
            pass
        client.close()
    except OSError:
        pass


def herdr_server_name(sock_path: str) -> str:
    # `herdr --session <name>` runs a server of its own, and pane ids restart
    # at w1:p1 in each one, so parking by pane id alone would have two servers
    # overwrite each other. herdr keeps a named session's socket in
    # <config>/herdr/sessions/<name>/ and the default one directly in
    # <config>/herdr/, which makes the name readable straight off the path.
    directory = Path(sock_path).parent
    if directory.parent.name == "sessions":
        return directory.name
    return "default"


def park_session(sock_path: str, pane_id: str, agent: str, session_id: str) -> None:
    base = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    directory = Path(base) / PARKED_SESSION_DIR / herdr_server_name(sock_path)
    entry = {"pane_id": pane_id, "agent": agent, "session_id": session_id}
    # The plugin adds a resumed_terminal_id of its own; rewriting the file
    # whole drops it, which is what a fresh report should mean — the pane is
    # live again and its next restore is a new one to serve.
    try:
        directory.mkdir(parents=True, exist_ok=True)
        # The colon in a pane id is legal in a filename but reads as a path
        # separator in enough places to be worth avoiding.
        path = directory / f"{pane_id.replace(':', '-')}.json"
        temporary = path.with_suffix(".json.new")
        temporary.write_text(json.dumps(entry))
        temporary.replace(path)
    except OSError:
        pass


def report_to_herdr(agent: str, state: str, payload: dict) -> None:
    if os.environ.get("HERDR_ENV") != "1":
        return
    sock_path = os.environ.get("HERDR_SOCKET_PATH", "")
    pane_id = os.environ.get("HERDR_PANE_ID", "")
    if not sock_path or not pane_id:
        return

    # A subagent's session is not the pane's session; reporting it would
    # relabel the sidebar row for the duration of the subagent's run, and park
    # the subagent's conversation as the one to resume the pane into. Claude
    # Code marks those with agent_id, Vibe with a parent_session_id.
    if payload.get("agent_id") or payload.get("parent_session_id"):
        return

    session_id = payload.get("session_id") or ""

    # herdr orders reports by seq, so a hook that fires late (Vibe's pre_tool
    # runs on every tool call) cannot undo a newer one.
    seq = time.time_ns()

    if state:
        # Reporting a state claims lifecycle authority for the pane, which
        # switches herdr's own screen-scraping detection off. That is correct
        # for Vibe, which ships no detection manifest and would otherwise never
        # appear in the sidebar at all; it would be a downgrade for Claude
        # Code, which has a manifest that distinguishes blocked from working.
        # If a Vibe turn dies before its post_agent hook runs, the row stays
        # "working" — `herdr pane release-agent <pane>` hands detection back.
        herdr_call(
            sock_path,
            "pane.report_agent",
            {
                "pane_id": pane_id,
                "source": HERDR_SOURCE,
                "agent": agent,
                "state": state,
                "seq": seq,
            },
        )

    if not session_id:
        return

    session_source = HERDR_SESSION_SOURCES.get(agent)
    if session_source is None:
        park_session(sock_path, pane_id, agent, session_id)
    else:
        params = {
            "pane_id": pane_id,
            "source": session_source,
            "agent": agent,
            "seq": seq,
            "agent_session_id": session_id,
        }
        transcript_path = payload.get("transcript_path")
        if isinstance(transcript_path, str) and transcript_path:
            params["agent_session_path"] = transcript_path
        if payload.get("hook_event_name") == "SessionStart":
            session_start_source = payload.get("source")
            if isinstance(session_start_source, str) and session_start_source:
                params["session_start_source"] = session_start_source
        # Feeds [session] resume_agents_on_restore: herdr replays the pane back
        # into this conversation after a server restart.
        herdr_call(sock_path, "pane.report_agent_session", params)

    herdr_call(
        sock_path,
        "pane.report_metadata",
        {
            "pane_id": pane_id,
            "source": HERDR_SOURCE,
            "seq": seq,
            "tokens": {"session": session_id[:SESSION_TOKEN_CHARS]},
        },
    )


def main() -> None:
    args = parse_args()
    report_to_herdr(args.agent, args.state, read_payload())


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
