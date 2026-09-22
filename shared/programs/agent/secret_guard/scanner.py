"""
Secret Guard Scanner

Pure business logic for detecting and redacting secrets in tool output,
and for flagging shell commands that are likely to dump secrets to stdout.
No I/O or AI-specific formatting here — that belongs in the entry points.
"""

import re
from typing import List, Optional, Pattern, Tuple

from .patterns import (
    BARE_DUMP_PATTERNS,
    GENERIC_ASSIGNMENT,
    PLACEHOLDER_VALUES,
    RISKY_COMMAND_PATTERNS,
    SECRET_PATTERNS,
)

# Splits a command into independent statements -- a pipe within one of
# these stays intact (that's exactly what _is_bare_secret_dump needs to see
# to tell a piped-away dump from a bare one).
_STATEMENT_SPLIT = re.compile(r"\n|;|&&|\|\|")


def _is_placeholder(value: str) -> bool:
    v = value.strip().strip("[]").lower()
    if v.startswith("redacted"):
        return True
    return v in PLACEHOLDER_VALUES


def find_secrets(text: str) -> List[Tuple[str, int, int]]:
    """Return non-overlapping (name, start, end) spans, sorted by position."""
    specific = []
    for name, pattern in SECRET_PATTERNS:
        for m in pattern.finditer(text):
            specific.append((name, m.start(), m.end()))

    # The generic key=value matcher's *key* half often swallows a
    # specific pattern that starts later in the same assignment (e.g.
    # "token: ghp_..." — key "token" starts before the ghp_ token itself),
    # which would otherwise win a naive earliest-start overlap resolution.
    # Only keep a generic match when its value span doesn't already sit
    # inside a specific match.
    generic = []
    for m in GENERIC_ASSIGNMENT.finditer(text):
        value = m.group("value")
        if _is_placeholder(value):
            continue
        v_start, v_end = m.start("value"), m.end("value")
        if any(s_start <= v_start and v_end <= s_end for _, s_start, s_end in specific):
            continue
        generic.append(("generic_secret_assignment", v_start, v_end))

    matches = specific + generic
    matches.sort(key=lambda t: (t[1], t[0]))

    result: List[Tuple[str, int, int]] = []
    last_end = -1
    for name, start, end in matches:
        if start < last_end:
            continue
        result.append((name, start, end))
        last_end = end
    return result


def redact(text: str) -> Tuple[str, List[str]]:
    """Replace each detected secret span with [REDACTED:<name>].

    Returns (redacted_text, names) where names is the list of pattern
    names that fired, in order of appearance (may contain duplicates).
    """
    matches = find_secrets(text)
    if not matches:
        return text, []

    out = []
    cursor = 0
    names = []
    for name, start, end in matches:
        out.append(text[cursor:start])
        out.append(f"[REDACTED:{name}]")
        names.append(name)
        cursor = end
    out.append(text[cursor:])
    return "".join(out), names


def _is_bare_secret_dump(command: str, invocation: Pattern) -> bool:
    """True if `invocation` matches within some statement of `command` in a
    way that would put its stdout directly into this tool call's own
    visible output: not piped into another command, and not captured via
    $(...)/backticks into a variable.
    """
    for statement in _STATEMENT_SPLIT.split(command):
        m = invocation.search(statement)
        if not m:
            continue
        prefix = statement[: m.start()]
        if "$(" in prefix or "`" in prefix:
            continue
        if "|" in statement[m.end() :]:
            continue
        return True
    return False


def is_risky_command(command: str) -> Optional[str]:
    """Return the name of the matched risky-command pattern, or None."""
    for name, pattern in RISKY_COMMAND_PATTERNS:
        if pattern.search(command):
            return name
    for name, pattern in BARE_DUMP_PATTERNS:
        if _is_bare_secret_dump(command, pattern):
            return name
    return None
