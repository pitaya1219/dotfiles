#!/usr/bin/env python3
"""Locate and read Vibe sessions stored in the unified harness layout
(`mistral.vibe.unified-session-store/v1`) under <root>/<session-uuid>/.

Unlike the legacy `session_*` directories, a unified session has no
`messages.jsonl`; the transcript only exists as content-addressed chunks that a
generation manifest lists in order. Callers that expect a `.jsonl` file
(attach_transcript.py) therefore need it rebuilt first.

Subcommands (stdout carries the result, stderr the reason on failure):

  resolve <match|any> <cwd> <root>...
      Print the session directory to use, or nothing.
      match: only sessions whose meta.json environment.working_directory is
             <cwd> or one of its ancestors; the nearest directory level wins
             and, within it, the newest bumped_at. The launch directory may be
             an ancestor of <cwd> (e.g. a clone inside a session directory).
      any:   newest bumped_at across all sessions, regardless of directory.

  transcript <session-dir>
      Print the path of a temp .jsonl holding one message object per line.
      CURRENT names the newest generation, whose manifest.json lists
      checkpoint.chunks in order; each chunks/<id>.json is a list of
      {"message": ..., "source": ...}. The turn in flight is only journaled,
      not yet checkpointed, so the transcript ends at the last checkpoint.
"""
import glob
import json
import os
import sys
import tempfile


def _load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _candidates(roots):
    for root in roots:
        for meta_path in glob.glob(os.path.join(root, "*", "meta.json")):
            try:
                meta = _load(meta_path)
            except (OSError, ValueError):
                continue
            if not isinstance(meta, dict):
                continue
            workdir = (meta.get("environment") or {}).get("working_directory") or ""
            # bumped_at is ISO-8601 with a fixed UTC offset, so it sorts as text.
            yield (meta.get("bumped_at") or ""), workdir, os.path.dirname(meta_path)


def resolve(mode, cwd, roots):
    found = list(_candidates(roots))
    if mode == "match":
        d = os.path.normpath(cwd)
        while True:
            level = [c for c in found if c[1] and os.path.normpath(c[1]) == d]
            if level:
                return max(level)[2]
            parent = os.path.dirname(d)
            if parent == d:
                return ""
            d = parent
    return max(found)[2] if found else ""


def transcript(session_dir):
    current = _load(os.path.join(session_dir, "CURRENT"))
    manifest = _load(os.path.join(session_dir, "generations", current["generation"], "manifest.json"))
    chunk_ids = manifest["checkpoint"]["chunks"]

    fd, out_path = tempfile.mkstemp(prefix="session-save-", suffix=".jsonl")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            for chunk_id in chunk_ids:
                for entry in _load(os.path.join(session_dir, "chunks", f"{chunk_id}.json")):
                    if isinstance(entry, dict) and "message" in entry:
                        out.write(json.dumps(entry["message"], ensure_ascii=False) + "\n")
    except BaseException:
        os.unlink(out_path)
        raise
    return out_path


def main(argv):
    try:
        if len(argv) >= 5 and argv[1] == "resolve" and argv[2] in ("match", "any"):
            print(resolve(argv[2], argv[3], argv[4:]))
            return 0
        if len(argv) == 3 and argv[1] == "transcript":
            print(transcript(argv[2]))
            return 0
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"vibe_unified: {argv[1]} failed: {e!r}", file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
