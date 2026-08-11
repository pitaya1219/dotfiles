#!/usr/bin/env python3
"""Check whether Logseq is reachable via the configured HTTP API.

Exit 0 if reachable, exit 1 otherwise — including a missing/malformed
~/.agent/logseq.json, which is a normal "Logseq not set up on this machine"
case, not an error. Prints nothing; callers branch on the exit code (this is
what session-save's USE_LOGSEQ check does).

Imported by session-save via absolute path under ~/.agent/skills/logseq-write/.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from logseq_common import ConfigError, is_available, load_config  # noqa: E402

if __name__ == "__main__":
    try:
        url, token = load_config()
    except ConfigError:
        sys.exit(1)
    sys.exit(0 if is_available(url, token) else 1)
