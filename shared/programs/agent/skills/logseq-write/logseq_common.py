#!/usr/bin/env python3
"""Helpers shared by logseq-write's scripts and session-save's bundled ones.

They reference this file by the absolute ~/.agent/skills/logseq-write/ path,
so keep its location and public names stable. Logseq itself is reached
through the `logseq-db` command (tools/logseq-db).
"""
import json
import subprocess
import sys

# Cloudflare (fronting the Nextcloud host) returns HTTP 403 "error code: 1010"
# for Python's default `Python-urllib/x.y` User-Agent; curl's passes.
USER_AGENT = "curl/8.5.0"


class LogseqError(RuntimeError):
    pass


def available():
    """True when Logseq can be written on this machine."""
    try:
        return subprocess.run(["logseq-db", "status"], capture_output=True).returncode == 0
    except OSError:
        return False


def write(page, properties=None, blocks=None):
    """Upsert `page` with `properties` and append `blocks`, a tree of
    {"content", "children"?, "tags"?}. Returns logseq-db's result."""
    spec = {"page": page, "properties": properties or {}, "blocks": blocks or []}
    try:
        proc = subprocess.run(["logseq-db", "write"], input=json.dumps(spec, ensure_ascii=False),
                              capture_output=True, text=True)
    except OSError as e:
        raise LogseqError(f"logseq-db is not installed: {e}")
    if proc.stderr:
        print(proc.stderr.strip(), file=sys.stderr)
    if proc.returncode != 0:
        raise LogseqError(proc.stderr.strip() or "logseq-db write failed")
    return json.loads(proc.stdout)
