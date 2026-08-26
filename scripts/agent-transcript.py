#!/usr/bin/env python3
# Renders a coding agent's own session log as plain text, so scripts/herdr-copy.sh
# has something to open when the pane's scrollback is empty.
#
# Claude Code's fullscreen renderer and Vibe's TUI both draw on the alternate
# screen and keep their scrollback virtualized inside the process, so no line
# ever reaches the host terminal: `herdr pane read` on an agent pane returns
# exactly the visible rows and nothing more, whatever --lines asks for. The
# agent's own log on disk is the only remaining source, and it is a better one —
# it carries the model's reasoning and full tool payloads, which the pane
# renders truncated or not at all.
#
# Consumed by:
#   - scripts/herdr-copy.sh (prefix+y), which falls back to `herdr pane read`
#     whenever this exits non-zero — shell panes, agents without a resolvable
#     session, opencode.
#
# opencode is deliberately not handled. Its transcript lives in SQLite
# (~/.local/share/opencode/opencode-stable.db, tables session/message/part) and
# is perfectly readable, but herdr reports neither tokens.session nor
# agent_session for an opencode pane, so there is no reliable pane -> session
# link to hang an adapter off; matching on session.directory alone picks the
# wrong row as soon as two opencode panes share a directory.
#
# Usage: agent-transcript.py [--pane ID] [--agent claude|vibe] [--session ID]

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Iterator, NoReturn

# scripts/herdr-agent-report.py truncates the session id to this many characters
# before publishing it as the pane's `session` token, because a full UUID would
# crowd the agent label out of the sidebar row. herdr also carries an untruncated
# id in `agent_session`, but only for sources it recognises as its own
# ("herdr:claude"); the report from this repo is filed under
# "dotfiles:agent-session" and lands in the metadata tokens instead. So the
# truncated token is the one field always present, and every lookup here has to
# work from a prefix.
SESSION_TOKEN_CHARS = 8


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        # HERDR_ACTIVE_PANE_ID is the pane a keybinding fired from and is the
        # only one herdr sets there; HERDR_PANE_ID covers running this by hand
        # from inside a pane. Same order as tools/agent-open/agent-open.sh.
        "--pane",
        default=os.environ.get("HERDR_ACTIVE_PANE_ID")
        or os.environ.get("HERDR_PANE_ID", ""),
        help="herdr pane to resolve the agent and session from. Defaults to "
        "HERDR_ACTIVE_PANE_ID, then HERDR_PANE_ID.",
    )
    parser.add_argument(
        "--agent",
        choices=tuple(ADAPTERS),
        help="Agent whose logs to read. With --session, skips the pane lookup.",
    )
    parser.add_argument(
        "--session",
        default="",
        help="Session id, or any leading part of one. With --agent, skips the "
        "pane lookup.",
    )
    return parser.parse_args()


def die(message: str) -> NoReturn:
    print(f"agent-transcript: {message}", file=sys.stderr)
    raise SystemExit(1)


def pane_info(pane_id: str) -> dict:
    herdr = os.environ.get("HERDR_BIN_PATH") or "herdr"
    try:
        completed = subprocess.run(
            [herdr, "pane", "get", pane_id],
            capture_output=True,
            text=True,
            timeout=5.0,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        die(f"could not ask herdr about pane {pane_id}: {error}")
    if completed.returncode != 0:
        die(f"herdr pane get {pane_id} failed: {completed.stderr.strip()}")
    try:
        return json.loads(completed.stdout)["result"]["pane"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        die(f"herdr pane get {pane_id} returned no pane: {error}")


def resolve(args: argparse.Namespace) -> tuple[str, str]:
    if args.agent and args.session:
        return args.agent, args.session
    if not args.pane:
        die("no --pane, and neither HERDR_ACTIVE_PANE_ID nor HERDR_PANE_ID is set")

    pane = pane_info(args.pane)
    agent = args.agent or pane.get("agent") or ""
    if agent not in ADAPTERS:
        die(f"pane {args.pane} runs {agent or 'no agent'}, which has no adapter")

    # agent_session holds an untruncated id, which turns the prefix match in the
    # locators into an exact one, so it goes ahead of the token.
    session = (
        args.session
        or (pane.get("agent_session") or {}).get("value")
        or (pane.get("tokens") or {}).get("session")
        or ""
    )
    if not session:
        die(
            f"pane {args.pane} reports no session id — the agent's hook has not "
            "run yet, or it started before scripts/herdr-agent-report.py was wired up"
        )
    return agent, session


def newest(candidates: Iterable[Path]) -> Path | None:
    """Pick the most recently written of an ambiguous prefix match.

    A truncated session id can in principle name more than one session. Ordering
    by mtime puts the live one first, which is the one prefix+y was pressed over.
    """
    return max(candidates, key=lambda path: path.stat().st_mtime, default=None)


def records(path: Path) -> Iterator[dict]:
    """Stream a jsonl log, skipping anything that does not parse.

    Line by line rather than through read_text().splitlines(): a session log
    reaches tens of megabytes, and a single non-BMP character anywhere in it
    forces CPython to hold the whole-file string as UCS-4.
    """
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


# --- rendering ---------------------------------------------------------------
#
# The output is read in nvim (scripts/herdr-copy.lua), so it is laid out for `/`
# and for yanking: every message opens with a "## " line, and payloads are
# written raw rather than as JSON, because an escaped "\n" is neither
# searchable nor pasteable.


def emit(out: list[str], heading: str, body: str) -> None:
    out.append(f"## {heading}")
    if body:
        out.append(body.rstrip("\n"))
    out.append("")


def fields_text(fields: dict) -> str:
    """Lay out a tool's arguments, one field per entry.

    Multi-line strings go on their own lines under the key; everything else fits
    beside it.
    """
    lines: list[str] = []
    for key, value in fields.items():
        text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
        if "\n" in text:
            lines.append(f"{key}:")
            # Not a bare rstrip(): a Bash command can end in significant spaces.
            lines.append(text.rstrip("\n"))
        else:
            lines.append(f"{key}: {text}")
    return "\n".join(lines)


def flatten(content) -> str:
    """Reduce an Anthropic-style content list to the text a reader wants."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and isinstance(block.get("text"), str):
                parts.append(block["text"])
            elif isinstance(block, str):
                parts.append(block)
            else:
                parts.append(json.dumps(block, ensure_ascii=False))
        return "\n".join(parts)
    return json.dumps(content, ensure_ascii=False)


def stamped(label: str, timestamp: str) -> str:
    """Append the time of day to a heading, or leave it bare if there is none."""
    if not isinstance(timestamp, str) or "T" not in timestamp:
        return label
    return f"{label}  {timestamp.split('T', 1)[1][:8]}"


# --- claude ------------------------------------------------------------------


def claude_log(session: str) -> Path:
    root = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (Path.home() / ".claude"))
    found = newest(root.glob(f"projects/*/{session}*.jsonl"))
    if found is None:
        die(f"no Claude Code transcript under {root}/projects matching {session}*")
    return found


def render_claude(path: Path) -> list[str]:
    out: list[str] = []
    for record in records(path):
        # Everything else in this file is bookkeeping the pane never showed:
        # queued prompts, permission-mode flips, file-history snapshots.
        if record.get("type") not in ("user", "assistant"):
            continue
        message = record.get("message")
        if not isinstance(message, dict):
            continue

        # Subagents write into the same file as the session that spawned them.
        # Marking them keeps an interleaved run readable.
        suffix = " (subagent)" if record.get("isSidechain") else ""
        role = message.get("role", record["type"])
        timestamp = record.get("timestamp", "")

        content = message.get("content")
        if isinstance(content, str):
            emit(out, stamped(role + suffix, timestamp), content)
            continue
        if not isinstance(content, list):
            continue

        for block in content:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if kind == "text":
                emit(out, stamped(role + suffix, timestamp), block.get("text", ""))
            elif kind == "thinking":
                # Redacted thinking arrives as an empty string; a bare heading
                # over nothing is just noise.
                if block.get("thinking"):
                    emit(out, stamped("thinking" + suffix, timestamp), block["thinking"])
            elif kind == "tool_use":
                name = block.get("name", "?")
                emit(out, f"tool {name}{suffix}", fields_text(block.get("input") or {}))
            elif kind == "tool_result":
                failed = " (error)" if block.get("is_error") else ""
                emit(out, f"result{failed}{suffix}", flatten(block.get("content")))
    return out


# --- vibe --------------------------------------------------------------------


def vibe_log(session: str) -> Path:
    # Vibe names each session directory <prefix>_<timestamp>_<short id>, where
    # the short id is the same leading slice herdr publishes as the pane token.
    pattern = f"logs/session/session_*_{session[:SESSION_TOKEN_CHARS]}*/messages.jsonl"
    # A session directory can carry its own VIBE_HOME, and a popup keybinding
    # inherits herdr's environment rather than the pane's, so that root has to
    # be searched by name. tools/agent-open/agent-open.sh scans the same two.
    roots = [Path(os.environ.get("VIBE_HOME") or (Path.home() / ".vibe"))]
    roots += Path.home().glob("agent-sessions/*/.vibe")

    found = newest(match for root in roots for match in root.glob(pattern))
    if found is None:
        die(f"no Vibe transcript under {roots[0]} matching {pattern}")
    return found


def render_vibe(path: Path) -> list[str]:
    out: list[str] = []
    for record in records(path):
        role = record.get("role", "")

        if role == "tool":
            emit(
                out,
                f"result {record.get('name', '')}".rstrip(),
                flatten(record.get("content")),
            )
            continue

        # Vibe puts the reasoning ahead of the reply it produced, which is the
        # order it was generated in.
        if record.get("reasoning_content"):
            emit(out, "thinking", flatten(record["reasoning_content"]))
        if record.get("content"):
            # Injected messages are context Vibe adds on the user's behalf
            # (file mentions, hook output); they were never typed.
            injected = " (injected)" if record.get("injected") else ""
            emit(out, f"{role}{injected}", flatten(record["content"]))

        for call in record.get("tool_calls") or []:
            function = call.get("function") or {}
            arguments = function.get("arguments") or "{}"
            try:
                parsed = json.loads(arguments)
            except json.JSONDecodeError:
                parsed = None
            body = fields_text(parsed) if isinstance(parsed, dict) else arguments
            emit(out, f"tool {function.get('name', '?')}", body)
    return out


# Keyed by the agent name herdr reports for a pane. Deriving --agent's choices
# and resolve()'s guard from this table is what keeps a half-added adapter from
# silently rendering one agent's log with another's renderer.
ADAPTERS = {
    "claude": (claude_log, render_claude),
    "vibe": (vibe_log, render_vibe),
}


def main() -> None:
    args = parse_args()
    agent, session = resolve(args)

    locate, render = ADAPTERS[agent]
    path = locate(session)
    lines = render(path)
    if not lines:
        die(f"{path} holds no messages yet")

    # Named so that a reader who reached this through prefix+y can tell the
    # transcript apart from the pane's own scrollback, and knows what to grep
    # outside the popup.
    sys.stdout.write(f"# {agent} {session}\n# {path}\n\n")
    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # Transcripts are long enough that piping into head or grep is the
        # normal way to read one from a shell. Redirect the dead stdout so the
        # interpreter's own flush at exit does not print a second traceback.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        raise SystemExit(0) from None
