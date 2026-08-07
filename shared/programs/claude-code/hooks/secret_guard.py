#!/usr/bin/env python3
"""
Secret Guard Hook for Claude Code

Entry point for Claude's PreToolUse/PostToolUse hooks.
Translates between Claude's hook format and the shared secret_guard logic.
"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../.agent'))

from secret_guard.scanner import is_risky_command, redact


# Tools whose output can plausibly contain leaked secrets.
SCANNED_TOOLS = {"Bash", "Read", "Grep"}


def handle_pre_tool_use(input_json):
    tool_name = input_json.get("tool_name", "")
    if tool_name != "Bash":
        return

    command = input_json.get("tool_input", {}).get("command", "")
    if not command:
        return

    risk = is_risky_command(command)
    if risk is None:
        return

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"このコマンドはsecretを標準出力に漏らす可能性が高いため拒否しました "
                f"({risk})。必要なら特定の変数/ファイルだけを対象にしてください。"
            ),
        }
    }))


def handle_post_tool_use(input_json):
    tool_name = input_json.get("tool_name", "")
    if tool_name not in SCANNED_TOOLS:
        return

    output = input_json.get("tool_output", "")
    if not output:
        return

    redacted, names = redact(output)
    if not names:
        return

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "updatedToolOutput": redacted,
            "additionalContext": (
                f"secret_guard: {len(names)} 件のsecretらしき文字列を検出したため redact しました "
                f"({', '.join(sorted(set(names)))})。"
            ),
        }
    }))


def main():
    try:
        input_data = sys.stdin.read()
        if not input_data.strip():
            sys.exit(0)
        input_json = json.loads(input_data)
    except (json.JSONDecodeError, Exception):
        # Fail-open: if we can't parse input, allow
        sys.exit(0)

    event = input_json.get("hook_event_name", "")
    if event == "PreToolUse":
        handle_pre_tool_use(input_json)
    elif event == "PostToolUse":
        handle_post_tool_use(input_json)

    sys.exit(0)


if __name__ == "__main__":
    main()
