#!/usr/bin/env python3
"""
Secret Guard Hook for Mistral Vibe

Entry point for vibe's pre_tool/post_tool hooks.
Translates between vibe's hook format and the shared secret_guard logic.

Field names below (tool_name, tool_input, tool_output_text, decision,
hook_specific_output.additional_context, ...) come from vibe's own bundled
hook wire-protocol docs (`vibe.core.skills.builtins.vibe`), not the public
docs site, which lags the installed version.
"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../.agent'))

from secret_guard.scanner import is_risky_command, redact


# Tools whose output can plausibly contain leaked secrets.
SCANNED_TOOLS = {"bash", "read_file", "grep"}


def handle_pre_tool(input_json):
    if input_json.get("tool_name") != "bash":
        return

    command = input_json.get("tool_input", {}).get("command", "")
    if not command:
        return

    risk = is_risky_command(command)
    if risk is None:
        return

    print(json.dumps({
        "decision": "deny",
        "reason": (
            f"このコマンドはsecretを標準出力に漏らす可能性が高いため拒否しました "
            f"({risk})。必要なら特定の変数/ファイルだけを対象にしてください。"
        ),
    }))


def handle_post_tool(input_json):
    if input_json.get("tool_name") not in SCANNED_TOOLS:
        return

    text = input_json.get("tool_output_text", "")
    if not text:
        return

    redacted, names = redact(text)
    if not names:
        return

    # decision:"deny" replaces tool_output_text with `reason` wholesale, so
    # `reason` carries the redacted text itself (secrets swapped, everything
    # else preserved) rather than a denial message.
    print(json.dumps({
        "decision": "deny",
        "reason": redacted,
        "hook_specific_output": {
            "additional_context": (
                f"secret_guard: {len(names)} 件のsecretらしき文字列を検出したため redact しました "
                f"({', '.join(sorted(set(names)))})。"
            ),
        },
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
    if event == "pre_tool":
        handle_pre_tool(input_json)
    elif event == "post_tool":
        handle_post_tool(input_json)

    sys.exit(0)


if __name__ == "__main__":
    main()
