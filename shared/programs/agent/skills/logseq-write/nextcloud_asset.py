#!/usr/bin/env python3
"""Upload a file to Nextcloud (logseq-assets dir) and print a Logseq-ready
markdown link to stdout.

Shared by logseq-write's --asset and session-save's raw-transcript
attachment (the latter imports `upload()` via sys.path against this file's
absolute ~/.agent/skills/logseq-write/ path). Credentials come from
`passage`, not ~/.agent/logseq.json — kept separate on purpose since the
Logseq API token and the Nextcloud WebDAV credentials are different secrets.

CLI usage: nextcloud_asset.py <path> [name]
Prints the markdown link on success and exits 0; prints nothing to stdout
and exits 1 on failure (reason on stderr).
"""
import base64
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from logseq_common import USER_AGENT  # noqa: E402

NC_DIR = "logseq-assets"
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp"}

_credentials = None  # cached (host, user, password) — resolved at most once per process
_dir_ensured = False  # MKCOL is idempotent but each call is a network round-trip; do it once


def _passage_show(key):
    out = subprocess.run(
        ["passage", "show", key], capture_output=True, text=True, check=True, timeout=15
    )
    return out.stdout.strip()


def _credentials_for_upload():
    global _credentials
    if _credentials is None:
        host = _passage_show("logseq-assets/nextcloud/host").rstrip("/")
        user = _passage_show("logseq-assets/nextcloud/ryu/id")
        password = _passage_show("logseq-assets/nextcloud/ryu/password")
        _credentials = (host, user, password)
    return _credentials


def _basic_auth_header(user, password):
    return "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()


def _dav(method, url, user, password, data=None, headers=None):
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    req.add_header("Authorization", _basic_auth_header(user, password))
    req.add_header("User-Agent", USER_AGENT)
    return urllib.request.urlopen(req, timeout=30)


def upload(src_path, name=None, display_name=None):
    """Upload src_path to Nextcloud and return a markdown link, or None on
    failure (reason printed to stderr; caller decides whether that's fatal —
    the original bash always treated asset failures as skip-and-continue).

    `name` is the filename stored on Nextcloud (defaults to src_path's
    basename); `display_name` is the link text shown in Logseq, when it
    should differ from the stored filename (defaults to `name`).
    """
    if not os.path.isfile(src_path):
        print(f"asset not found, skipping: {src_path}", file=sys.stderr)
        return None
    name = name or os.path.basename(src_path)
    display_name = display_name or name

    host, user, password = _credentials_for_upload()

    base = f"{host}/remote.php/dav/files/{urllib.parse.quote(user)}/{NC_DIR}/"
    global _dir_ensured
    if not _dir_ensured:
        try:
            _dav("MKCOL", base, user, password)
        except urllib.error.HTTPError:
            pass  # no-op if the directory already exists
        _dir_ensured = True

    target = base + urllib.parse.quote(name)
    with open(src_path, "rb") as f:
        data = f.read()
    try:
        _dav("PUT", target, user, password, data=data)
    except (urllib.error.HTTPError, urllib.error.URLError) as e:
        print(f"nextcloud upload failed ({e}), skipping: {src_path}", file=sys.stderr)
        return None

    propfind_body = (
        '<?xml version="1.0"?>'
        '<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">'
        "<d:prop><oc:fileid/></d:prop></d:propfind>"
    ).encode()
    try:
        resp = _dav(
            "PROPFIND",
            target,
            user,
            password,
            data=propfind_body,
            headers={"Depth": "0", "Content-Type": "application/xml"},
        )
        body = resp.read().decode()
    except (urllib.error.HTTPError, urllib.error.URLError) as e:
        print(f"nextcloud fileid lookup failed ({e}), skipping: {name}", file=sys.stderr)
        return None

    m = re.search(r"<oc:fileid>(\d+)</oc:fileid>", body)
    if not m:
        print(f"nextcloud fileid lookup failed, skipping: {name}", file=sys.stderr)
        return None
    file_id = m.group(1)

    ext = os.path.splitext(name)[1].lower()
    prefix = "!" if ext in IMAGE_EXTS else ""
    return f"{prefix}[{display_name}]({host}/f/{file_id})"


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print("usage: nextcloud_asset.py <path> [name]", file=sys.stderr)
        sys.exit(2)
    link = upload(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)
    if link is None:
        sys.exit(1)
    print(link)
