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

# Identifies this reporter to herdr, which arbitrates between sources when
# more than one claims the same pane. Distinct from "herdr:claude", the source
# herdr's own `integration install claude` hook uses — that hook cannot be
# installed here because it rewrites ~/.claude/settings.json, which is a
# read-only symlink into the Nix store.
HERDR_SOURCE = "dotfiles:agent-session"

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


def report_to_herdr(agent: str, state: str, payload: dict) -> None:
    if os.environ.get("HERDR_ENV") != "1":
        return
    sock_path = os.environ.get("HERDR_SOCKET_PATH", "")
    pane_id = os.environ.get("HERDR_PANE_ID", "")
    if not sock_path or not pane_id:
        return

    # A subagent's session is not the pane's session; reporting it would
    # relabel the sidebar row for the duration of the subagent's run.
    if payload.get("agent_id"):
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

    params = {
        "pane_id": pane_id,
        "source": HERDR_SOURCE,
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
