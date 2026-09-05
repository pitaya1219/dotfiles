#!/usr/bin/env python3
"""Upload one or more local files to pages.pitaya.f5.si and print their URLs.

For content meant to be opened and viewed as-is (an HTML page and the
assets it references) — not a general file store. Everything else already
has a home via logseq-write's --asset / session-save's transcript
attachment (Nextcloud); use that instead.

Auth is ZITADEL client_credentials against the `pages-writer` machine user
(core/identity/tofu/pages.tf in the homelab repo), gated by Pomerium in
front of dufs (core/gateway/pomerium/config.yaml). Credentials come from
passage, resolved fresh each run — never read from the homelab repo's own
.envrc, so this works from any host with passage + network access to
auth.pitaya.f5.si, not just one running inside that repo's direnv.

CLI usage: pages_upload.py <path> [<path> ...] --dir <dest-dir> [--name <name>]
--name only valid with a single path; otherwise each file keeps its own
basename under --dir. Prints one URL per uploaded file to stdout and exits
0 on full success; exits 1 if any file failed (reason on stderr).
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOKEN_URL = "https://auth.pitaya.f5.si/oauth/v2/token"
UPLOAD_BASE = "https://pages.pitaya.f5.si"
PAGES_PROJECT_ID = "388310531120824324"
SCOPE = (
    "openid profile "
    f"urn:zitadel:iam:org:project:id:{PAGES_PROJECT_ID}:aud "
    "urn:zitadel:iam:org:projects:roles"
)

# Cloudflare (fronting auth.pitaya.f5.si and pages.pitaya.f5.si) 403s
# Python's default `Python-urllib/x.y` User-Agent with "error code: 1010" —
# a bot-blocking heuristic curl's UA sails through. Same workaround as
# logseq-write's logseq_common.USER_AGENT.
USER_AGENT = "curl/8.5.0"

CACHE_PATH = os.path.expanduser("~/.cache/agent-pages-upload/token.json")
# Refresh this long before the token's actual ~12h expiry so a slow upload
# never straddles the boundary and gets a 401 mid-request.
EXPIRY_MARGIN_S = 300


def _passage_show(key):
    out = subprocess.run(
        ["passage", "show", key], capture_output=True, text=True, check=True, timeout=15
    )
    return out.stdout.strip()


def _fetch_token():
    client_id = _passage_show("homelab/zitadel/apps/pages-writer/client/id")
    client_secret = _passage_show("homelab/zitadel/apps/pages-writer/client/secret")

    data = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": SCOPE}).encode()
    req = urllib.request.Request(TOKEN_URL, data=data, method="POST")
    basic = subprocess.run(
        ["python3", "-c", "import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())",
         f"{client_id}:{client_secret}"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    req.add_header("Authorization", f"Basic {basic}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    req.add_header("User-Agent", USER_AGENT)

    with urllib.request.urlopen(req, timeout=20) as resp:
        body = json.loads(resp.read().decode())

    token = body["access_token"]
    expires_at = time.time() + body.get("expires_in", 0)
    return token, expires_at


def _cached_token():
    try:
        with open(CACHE_PATH) as f:
            cached = json.load(f)
        if cached["expires_at"] - EXPIRY_MARGIN_S > time.time():
            return cached["access_token"]
    except (OSError, KeyError, ValueError):
        pass

    token, expires_at = _fetch_token()
    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    with open(CACHE_PATH, "w") as f:
        json.dump({"access_token": token, "expires_at": expires_at}, f)
    os.chmod(CACHE_PATH, 0o600)
    return token


def _request(method, url, token, data=None):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("User-Agent", USER_AGENT)
    return urllib.request.urlopen(req, timeout=60)


def _ensure_dir(dest_dir, token):
    url = f"{UPLOAD_BASE}/{urllib.parse.quote(dest_dir.strip('/'))}/"
    try:
        _request("MKCOL", url, token)
    except urllib.error.HTTPError:
        pass  # already exists, or dufs otherwise rejects a redundant MKCOL


def upload_file(local_path, dest_dir, dest_name=None, token=None):
    """Returns the public URL on success, or None (reason on stderr)."""
    if not os.path.isfile(local_path):
        print(f"not a file, skipping: {local_path}", file=sys.stderr)
        return None
    dest_name = dest_name or os.path.basename(local_path)
    token = token or _cached_token()

    url = f"{UPLOAD_BASE}/{urllib.parse.quote(dest_dir.strip('/'))}/{urllib.parse.quote(dest_name)}"
    with open(local_path, "rb") as f:
        data = f.read()

    try:
        _request("PUT", url, token, data=data)
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f"upload failed ({e.code}): {local_path}", file=sys.stderr)
            return None
        # Directory doesn't exist yet -- dufs' PUT won't create it for you.
        _ensure_dir(dest_dir, token)
        try:
            _request("PUT", url, token, data=data)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e2:
            print(f"upload failed after mkdir ({e2}): {local_path}", file=sys.stderr)
            return None
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"upload failed ({e}): {local_path}", file=sys.stderr)
        return None

    return url


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--dir", required=True, help="destination directory under pages.pitaya.f5.si")
    parser.add_argument("--name", help="override filename; only valid with a single path")
    args = parser.parse_args()

    if args.name and len(args.paths) > 1:
        print("--name requires exactly one path", file=sys.stderr)
        sys.exit(2)

    token = _cached_token()
    ok = True
    for path in args.paths:
        url = upload_file(path, args.dir, args.name, token=token)
        if url is None:
            ok = False
        else:
            print(url)

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
