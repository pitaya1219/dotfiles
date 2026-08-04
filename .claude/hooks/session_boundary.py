#!/usr/bin/env python3
"""
Session Boundary Hook for Claude Code (Global)

PreToolUse hook that enforces session directory boundaries.
Uses shared session_id_detector from dotfiles.
"""

import json
import sys
import os

# Add dotfiles shared programs to path
DOTFILES_AGENT = os.path.expanduser("~/dotfiles/shared/programs/agent")
if os.path.exists(DOTFILES_AGENT):
    sys.path.insert(0, DOTFILES_AGENT)

from session_id_detector import detect_claude_session_id, get_agent_type

# File-modifying tools for Claude Code
FILE_MODIFYING_TOOLS = ["Write", "Edit", "MultiEdit", "NotebookEdit"]


def normalize_path(path: str) -> str:
    """Normalize path to absolute, trailing-slash-free."""
    import re
    
    # Handle tilde expansion
    if path == "~":
        path = os.path.expanduser("~")
    elif path.startswith("~/"):
        path = os.path.expanduser(path)
    
    # Handle relative paths
    if not os.path.isabs(path):
        path = os.path.join(os.getcwd(), path)
    
    # Remove trailing slashes
    return re.sub(r'/+$', '', path)


def check_boundary(target_path: str, session_id: str) -> str | None:
    """Check if target path is within session boundaries."""
    SESSIONS_ROOT = os.path.expanduser("~/agent-sessions")
    
    if not session_id:
        return None
    
    SESSION_DIR = os.path.join(SESSIONS_ROOT, f"session-{session_id}")
    P = target_path
    
    # Inside the current session dir -> allow
    if P.startswith(SESSION_DIR) or P.startswith(SESSION_DIR + '/'):
        return None
    
    # Under agent-sessions: allow workspace root/meta files but block sibling sessions
    if P.startswith(SESSIONS_ROOT):
        rel = P[len(SESSIONS_ROOT):].lstrip('/')
        if rel.startswith("session-"):
            return (
                f"'{target_path}' は別のセッションのディレクトリ内です。"
                f"他のセッションの作業を汚さないでください。"
                f"あなたのセッションディレクトリは '{SESSION_DIR}' です。"
            )
        else:
            # Workspace root / meta file -> allow
            return None
    
    # Allowlist (paths outside agent-sessions)
    ALLOW_PREFIXES = [
        os.path.expanduser("~/.vibe/"),
        os.path.expanduser("~/.config/"),
        os.path.expanduser("~/.agent/"),
        "/tmp/",
        "/private/tmp/",
        "/var/folders/",
    ]
    
    for allow_prefix in ALLOW_PREFIXES:
        normalized_prefix = allow_prefix.rstrip('/') + '/'
        if P.startswith(allow_prefix) or P.startswith(normalized_prefix):
            return None
    
    # Default deny
    return (
        f"'{target_path}' はあなたのセッションディレクトリの外です。"
        f"あなたのセッションディレクトリは '{SESSION_DIR}' です。"
        f"作業ファイルはそこに作成してください。"
        f"リポジトリを扱う場合はまずセッションディレクトリ内に clone してから作業してください。"
        f"例外として ~/.vibe, ~/.config, ~/.agent, /tmp は常に許可されます。"
    )


def main():
    """Entry point for Claude hooks."""
    try:
        # Read hook input from stdin
        input_data = sys.stdin.read()
        if not input_data.strip():
            sys.exit(0)
        
        input_json = json.loads(input_data)
    except (json.JSONDecodeError, Exception):
        # Fail-open: if we can't parse input, allow
        sys.exit(0)
    
    # Extract data from Claude format
    tool_name = input_json.get("tool_name", "")
    tool_input = input_json.get("tool_input", {})
    provided_session_id = input_json.get("session_id", "")
    
    # Only check file-modifying tools
    if tool_name not in FILE_MODIFYING_TOOLS:
        sys.exit(0)
    
    # Get target file path - handle both Write/Edit and MultiEdit/NotebookEdit
    target = tool_input.get("file_path", "") or tool_input.get("notebook_path", "")
    if not target:
        sys.exit(0)
    
    # Normalize path before passing to enforcer
    target = normalize_path(target)
    
    # Try to get session ID with fallback detection
    session_id = provided_session_id
    if not session_id:
        # Use shared detector from dotfiles
        detected_session_id, _ = detect_claude_session_id(get_agent_type())
        if detected_session_id:
            session_id = detected_session_id
    
    # Can't identify session -> fail-open
    if not session_id:
        sys.exit(0)
    
    # Check boundary
    reason = check_boundary(target, session_id)
    
    # If reason is None, allow (exit 0)
    if reason is None:
        sys.exit(0)
    
    # Deny with Claude format
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason
        }
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
