#!/usr/bin/env python3
"""Shared Logseq HTTP API config resolution and request helper.

Imported by logseq-write's own script and by session-save's bundled scripts
via `sys.path` (they reference this file by the absolute
~/.agent/skills/logseq-write/ path, same convention session-save already uses
for detect-session.sh) — keep this file's location and public names stable.
"""
import json
import os
import subprocess
import urllib.error
import urllib.request

CONFIG_PATH = os.path.expanduser("~/.agent/logseq.json")

# Cloudflare (fronting logseq-api.pitaya.f5.si) returns HTTP 403 "error code:
# 1010" for Python's default `Python-urllib/x.y` User-Agent — it's on some
# bot-blocking heuristic that curl's UA sails through. Set an explicit one on
# every request so this doesn't silently look like "Logseq unreachable".
USER_AGENT = "curl/8.5.0"


class ConfigError(RuntimeError):
    pass


def _resolve_value(cfg, key):
    """Resolve a config value that is a plain string, {"file": ...}, or
    {"command": ...}. Mirrors the resolve_value() shell function the old
    SKILL.md prose asked each agent to hand-copy — centralized here so every
    caller resolves indirection identically instead of occasionally reading
    the wrapper object as a literal string.
    """
    val = cfg.get(key)
    if isinstance(val, str):
        return val
    if isinstance(val, dict):
        if "file" in val:
            path = os.path.expanduser(val["file"])
            try:
                with open(path) as f:
                    return f.read().strip()
            except OSError:
                return ""
        if "command" in val:
            try:
                out = subprocess.run(
                    val["command"], shell=True, capture_output=True, text=True, check=True
                )
                return out.stdout.strip()
            except subprocess.CalledProcessError:
                return ""
    return ""


def load_config():
    """Returns (url, token) with trailing slash stripped from url.
    Raises ConfigError with a user-facing message on any failure.
    """
    if not os.path.exists(CONFIG_PATH):
        raise ConfigError(
            f"No config at {CONFIG_PATH}. Set dotfiles.agent.logseq in your Nix profile."
        )
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    url = _resolve_value(cfg, "url")
    token = _resolve_value(cfg, "token")
    if not (url.startswith("http://") or url.startswith("https://")):
        raise ConfigError(f"LOGSEQ_URL did not resolve to a URL (got: {url!r}).")
    if not token:
        raise ConfigError("LOGSEQ_TOKEN is empty after resolution.")
    return url.rstrip("/"), token


def call_api(url, token, method, args, timeout=60):
    """POST a Logseq API call. Returns (status_code, body_text).
    status_code is 0 on connection-level failure or timeout (body_text holds
    the reason) — callers should treat non-200 as failure and print
    status+body, the same "never swallow the response body" discipline the
    old prose called out around `curl -sf`.

    Default timeout is 60s, not a "fast fail" value: insertBatchBlock calls
    carrying a full session-summary block tree (tens of blocks, low tens of
    KB) have been observed taking longer than 15s to process server-side,
    and this isn't a hot path — a slow-but-successful write is preferable to
    a spurious failure. Callers that want a fast liveness probe instead
    (is_available()) pass their own short timeout.
    """
    body = json.dumps({"method": method, "args": args}).encode()
    req = urllib.request.Request(
        f"{url}/api",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except urllib.error.URLError as e:
        return 0, str(e.reason)
    except TimeoutError:
        # A read timeout mid-response (as opposed to a connection-time
        # failure) raises a bare TimeoutError that urllib does NOT wrap in
        # URLError, so it must be caught separately or it crashes the whole
        # script with a raw traceback instead of a clean caller-visible
        # failure.
        return 0, f"timed out after {timeout}s"


def is_available(url, token, timeout=3):
    status, _ = call_api(url, token, "logseq.App.getUserConfigs", [], timeout=timeout)
    return status == 200
