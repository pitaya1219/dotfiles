#!/usr/bin/env python3
"""
Language steering hook for Mistral Vibe.

Appends a short language reminder to every post_tool result via
``additional_context``, keeping the steering signal close to the
generation point even as context grows long. Without this, the language
policy in AGENTS.md sits at the top of the context and its influence
dilutes over long sessions — particularly for CJK-trained models (GLM,
Qwen, DeepSeek) that drift toward Chinese when attention is spread thin.

Wire protocol: ``hook_specific_output.additional_context`` in a
``post_tool`` response is appended to ``tool_output_text`` by Vibe's
AfterToolHandler (vibe/core/hooks/_after_tool.py).
"""

import json
import sys

REMINDER = "[language] Reason in English. Respond in Japanese. Never output Chinese."


def main():
    try:
        input_data = sys.stdin.read()
        if not input_data.strip():
            sys.exit(0)
        input_json = json.loads(input_data)
    except (json.JSONDecodeError, Exception):
        sys.exit(0)

    if input_json.get("hook_event_name") != "post_tool":
        sys.exit(0)

    print(json.dumps({
        "hook_specific_output": {
            "additional_context": REMINDER,
        },
    }))


if __name__ == "__main__":
    main()
