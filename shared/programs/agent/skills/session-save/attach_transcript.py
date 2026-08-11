#!/usr/bin/env python3
"""Compress the current session's raw transcript with zstd and upload it to
Nextcloud, printing the `raw-transcript` page-property link on success.

Best-effort by design (matches the original prose): any failure prints a
short reason to stderr and the script exits 0 with no stdout output, so
callers can do `REF=$(python3 attach_transcript.py ...)` and just check
whether $REF is non-empty rather than branching on exit status.

Usage: attach_transcript.py <session_id> <transcript_path>
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.expanduser("~/.agent/skills/logseq-write"))
import nextcloud_asset  # noqa: E402


def main():
    if len(sys.argv) != 3:
        print("usage: attach_transcript.py <session_id> <transcript_path>", file=sys.stderr)
        sys.exit(0)  # best-effort: never fail the caller's session-save flow
    session_id, transcript_path = sys.argv[1], sys.argv[2]

    if not os.path.isfile(transcript_path):
        print(f"transcript not found, skipping: {transcript_path}", file=sys.stderr)
        return

    asset_name = f"session-{session_id}.jsonl.zst"
    with tempfile.TemporaryDirectory() as tmp:
        compressed = os.path.join(tmp, asset_name)
        result = subprocess.run(
            ["zstd", "-q", "-f", "-19", "-o", compressed, transcript_path],
            capture_output=True,
        )
        if result.returncode != 0 or not os.path.isfile(compressed):
            print(f"zstd compression failed: {result.stderr.decode(errors='replace')}", file=sys.stderr)
            return

        link = nextcloud_asset.upload(compressed, asset_name, display_name="session.jsonl.zst")
        if link is None:
            return  # nextcloud_asset already printed the reason to stderr
        print(link)


if __name__ == "__main__":
    main()
