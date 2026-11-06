#!/usr/bin/env python3
"""Exit 0 when Logseq can be written on this machine, 1 otherwise.

A machine without Logseq set up (no programs.logseq-db) is a normal case, not
an error. Prints nothing; callers branch on the exit code (session-save's
USE_LOGSEQ check does).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from logseq_common import available  # noqa: E402

if __name__ == "__main__":
    sys.exit(0 if available() else 1)
