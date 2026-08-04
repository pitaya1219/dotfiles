"""
Session ID Detector for AI Assistants

Detects current session IDs for various AI assistants by examining their log files
and environment. This module provides a unified way to detect session IDs that can
be used across different tools (agent-sessions, nvim plugins, etc.).

Detection Strategy:
1. Check environment variables first (authoritative)
2. Probe filesystem for Claude Code session logs
3. Probe filesystem for Mistral Vibe session logs
4. Return None if undetected (fail-open)

Usage:
    from session_id_detector import detect_session_id, get_agent_type
    
    session_id = detect_session_id()
    agent_type = get_agent_type()
"""

import os
import json
import glob
from pathlib import Path
from typing import Optional, Tuple
from datetime import datetime


def get_agent_type() -> str:
    """
    Identify the running AI agent from environment variables.
    
    Returns:
        'claude-code', 'vibe', or 'unknown'
    """
    # Check AI_AGENT first (Claude Code sets this)
    ai_agent = os.environ.get('AI_AGENT', '')
    if ai_agent:
        if 'claude-code' in ai_agent.lower():
            return 'claude-code'
        elif 'vibe' in ai_agent.lower():
            return 'vibe'
    
    # Check CLAUDECODE and CLAUDE_CODE_SESSION_ID
    if os.environ.get('CLAUDECODE', '') == '1' or os.environ.get('CLAUDE_CODE_SESSION_ID', ''):
        return 'claude-code'
    
    # Check VIBE_SESSION_ID
    if os.environ.get('VIBE_SESSION_ID', ''):
        return 'vibe'
    
    return 'unknown'


def detect_claude_session_id(agent_type: Optional[str] = None) -> Tuple[Optional[str], Optional[str]]:
    """
    Detect Claude Code session ID and transcript path.
    
    Only searches Claude Code logs if agent_type is 'claude-code' or 'unknown'.
    This prevents cross-contamination where a Vibe session could be misidentified
    as Claude Code.
    
    Args:
        agent_type: If provided, skip detection if not 'claude-code' or 'unknown'
    
    Returns:
        Tuple of (session_id, transcript_path) or (None, None) if not detected
    """
    # Skip if we know we're running under a different agent
    if agent_type and agent_type not in ('claude-code', 'unknown'):
        return None, None
    
    try:
        cwd = os.getcwd()
        encoded_path = cwd.replace('/', '-')
        
        # Build Claude projects base path
        claude_projects = os.path.expanduser("~/.claude/projects")
        
        # Strategy 0: Authoritative environment variable (recent CLI)
        if os.environ.get('CLAUDE_CODE_SESSION_ID', ''):
            session_id = os.environ['CLAUDE_CODE_SESSION_ID']
            # Find transcript by matching session ID across all project dirs
            transcript_path = _find_claude_transcript_by_id(session_id)
            if transcript_path:
                return session_id, transcript_path
            # If transcript not found, still return the ID
            return session_id, None
        
        # Strategy 1: ~/.claude/projects/<workdir-encoded>/<uuid>.jsonl
        project_dir = os.path.join(claude_projects, encoded_path)
        if os.path.exists(project_dir):
            session_id, transcript_path = _find_claude_session_in_dir(project_dir)
            if session_id:
                return session_id, transcript_path
        
        # Strategy 1b: Walk up parent dirs and try each ancestor's encoded key
        # Claude Code keys the project dir by the cwd it was launched from,
        # which may be an ancestor of the current dir.
        _d = cwd
        while _d != "/" and not (session_id and transcript_path):
            _d = os.path.dirname(_d)
            _enc = _d.replace('/', '-')
            _ancestor_dir = os.path.join(claude_projects, _enc)
            if os.path.exists(_ancestor_dir):
                session_id, transcript_path = _find_claude_session_in_dir(_ancestor_dir)
                if session_id:
                    return session_id, transcript_path
        
        # Strategy 2: /tmp tasks dir filtered by workdir
        session_id = _find_claude_session_in_tmp(encoded_path)
        if session_id:
            return session_id, None
        
        # Strategy 3: /tmp tasks dir across all workdirs
        session_id = _find_claude_session_in_tmp_all()
        if session_id:
            return session_id, None
        
        return None, None
        
    except Exception:
        return None, None


def detect_vibe_session_id(agent_type: Optional[str] = None) -> Tuple[Optional[str], Optional[str]]:
    """
    Detect Mistral Vibe session ID and transcript path.
    
    Only searches Vibe logs if agent_type is not 'claude-code'.
    This prevents cross-contamination where a leftover Vibe log could be
    misidentified as the current session when running under Claude Code.
    
    Args:
        agent_type: If provided, skip detection if 'claude-code'
    
    Returns:
        Tuple of (session_id, transcript_path) or (None, None) if not detected
    """
    # Never search Vibe logs when running under Claude Code
    if agent_type == 'claude-code':
        return None, None
    
    try:
        # Search paths in priority order:
        # 1. Project-local: ./.vibe/logs/session/
        # 2. agent-sessions global: ~/agent-sessions/.vibe/logs/session/
        # 3. Global: $VIBE_HOME/.vibe/logs/session/ or ~/./vibe/logs/session/
        
        # Strategy 1: Project-local
        session_id, transcript_path = _find_vibe_session_in_path(
            os.path.join(os.getcwd(), ".vibe/logs/session")
        )
        if session_id:
            return session_id, transcript_path
        
        # Strategy 2: agent-sessions global
        session_id, transcript_path = _find_vibe_session_in_path(
            os.path.join(os.path.expanduser("~"), "agent-sessions", ".vibe/logs/session")
        )
        if session_id:
            return session_id, transcript_path
        
        # Strategy 3: Global Vibe logs
        vibe_home = os.environ.get('VIBE_HOME', os.path.expanduser('~/.vibe'))
        global_paths = [
            os.path.join(vibe_home, ".vibe/logs/session"),
            os.path.join(vibe_home, "logs/session"),
        ]
        
        for base_path in global_paths:
            session_id, transcript_path = _find_vibe_session_in_path(base_path)
            if session_id:
                return session_id, transcript_path
        
        return None, None
        
    except Exception:
        return None, None


def detect_session_id() -> Tuple[Optional[str], Optional[str], str]:
    """
    Detect current session ID, transcript path, and agent type.
    
    Uses authoritative environment variables first, then falls back to
    filesystem probing. Each agent only probes its own log directories to
    prevent cross-contamination.
    
    Returns:
        Tuple of (session_id, transcript_path, agent_type)
        session_id and transcript_path may be None if not detected
        agent_type is 'claude-code', 'vibe', or 'unknown'
    """
    # Get agent type from environment
    agent_type = get_agent_type()
    
    # Check authoritative environment variables first
    session_id = os.environ.get('CLAUDE_CODE_SESSION_ID', '') or \
                os.environ.get('VIBE_SESSION_ID', '') or \
                os.environ.get('SESSION_ID', '')
    
    transcript_path = None
    
    if session_id:
        # If we have a session ID from env, try to find the transcript
        if agent_type == 'claude-code' or agent_type == 'unknown':
            transcript_path = _find_claude_transcript_by_id(session_id)
        # For Vibe, we'd need to search meta.json files, but session_id from env is authoritative
        return session_id, transcript_path, agent_type
    
    # Probe filesystem based on agent type
    if agent_type in ('claude-code', 'unknown'):
        session_id, transcript_path = detect_claude_session_id(agent_type)
        if session_id:
            return session_id, transcript_path, 'claude-code'
    
    if agent_type != 'claude-code':
        session_id, transcript_path = detect_vibe_session_id(agent_type)
        if session_id:
            return session_id, transcript_path, 'vibe'
    
    return None, None, agent_type


def _is_uuid(s: str) -> bool:
    """Check if string matches UUID format."""
    import re
    uuid_pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    return bool(re.match(uuid_pattern, s, re.IGNORECASE))


def _find_claude_session_in_dir(project_dir: str) -> Tuple[Optional[str], Optional[str]]:
    """Find Claude Code session in a project directory."""
    try:
        candidates = []
        
        # Look for UUID.jsonl files
        try:
            all_files = os.listdir(project_dir)
            for filename in all_files:
                if filename.endswith('.jsonl'):
                    basename = filename.replace('.jsonl', '')
                    if _is_uuid(basename):
                        full_path = os.path.join(project_dir, filename)
                        mtime = os.path.getmtime(full_path)
                        candidates.append((mtime, basename, full_path))
        except (OSError, PermissionError):
            pass
        
        # Look for UUID directories
        try:
            for entry in os.listdir(project_dir):
                full_path = os.path.join(project_dir, entry)
                if os.path.isdir(full_path) and _is_uuid(entry):
                    # Look for .jsonl file inside the directory
                    jsonl_path = os.path.join(full_path, f"{entry}.jsonl")
                    if os.path.exists(jsonl_path):
                        mtime = os.path.getmtime(jsonl_path)
                        candidates.append((mtime, entry, jsonl_path))
                    else:
                        mtime = os.path.getmtime(full_path)
                        candidates.append((mtime, entry, None))
        except (OSError, PermissionError):
            pass
        
        # Return the most recently modified
        if candidates:
            candidates.sort(reverse=True, key=lambda x: x[0])
            _, session_id, transcript_path = candidates[0]
            return session_id, transcript_path
        
        return None, None
        
    except Exception:
        return None, None


def _find_claude_transcript_by_id(session_id: str) -> Optional[str]:
    """Find Claude Code transcript by session ID across all project dirs."""
    try:
        claude_projects = os.path.expanduser("~/.claude/projects")
        
        # Search for the transcript file matching the session ID
        pattern = os.path.join(claude_projects, "*", f"{session_id}.jsonl")
        matches = glob.glob(pattern)
        
        if matches:
            # Return the most recently modified
            matches.sort(key=lambda x: os.path.getmtime(x), reverse=True)
            return matches[0]
        
        return None
        
    except Exception:
        return None


def _find_claude_session_in_tmp(encoded_path: str) -> Optional[str]:
    """Find Claude Code session in /tmp/tasks dir filtered by workdir."""
    try:
        # Find /tmp tasks dir filtered by workdir
        import subprocess
        result = subprocess.run(
            ['find', '/tmp', '-maxdepth', '7', '-type', 'd', '-name', 'tasks'],
            capture_output=True, text=True, timeout=10
        )
        
        if result.returncode == 0 and result.stdout.strip():
            # Filter by workdir and extract UUID
            for line in result.stdout.strip().split('\n'):
                if encoded_path in line:
                    # Extract UUID from path
                    uuid = _extract_uuid_from_path(line)
                    if uuid:
                        return uuid
        
        return None
        
    except Exception:
        return None


def _find_claude_session_in_tmp_all() -> Optional[str]:
    """Find Claude Code session in /tmp/tasks dir across all workdirs."""
    try:
        import subprocess
        result = subprocess.run(
            ['find', '/tmp', '-maxdepth', '7', '-type', 'd', '-name', 'tasks', '-path', '*/claude-*'],
            capture_output=True, text=True, timeout=10
        )
        
        if result.returncode == 0 and result.stdout.strip():
            # Get the most recently modified directory
            paths_with_mtime = []
            for line in result.stdout.strip().split('\n'):
                if os.path.exists(line):
                    try:
                        mtime = os.path.getmtime(line)
                        paths_with_mtime.append((mtime, line))
                    except:
                        pass
            
            if paths_with_mtime:
                paths_with_mtime.sort(reverse=True, key=lambda x: x[0])
                latest_path = paths_with_mtime[0][1]
                uuid = _extract_uuid_from_path(latest_path)
                if uuid:
                    return uuid
        
        return None
        
    except Exception:
        return None


def _extract_uuid_from_path(path: str) -> Optional[str]:
    """Extract UUID from a filesystem path."""
    import re
    # Look for UUID pattern in the path
    match = re.search(r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', path, re.IGNORECASE)
    if match:
        return match.group(1)
    return None


def _find_vibe_session_in_path(base_path: str) -> Tuple[Optional[str], Optional[str]]:
    """Find Vibe session in a specific path."""
    try:
        # Find all session_*/meta.json files
        pattern = os.path.join(base_path, "session_*", "meta.json")
        meta_files = glob.glob(pattern)
        
        if not meta_files:
            return None, None
        
        # Sort by modification time, newest first
        meta_files.sort(key=lambda x: os.path.getmtime(x), reverse=True)
        
        # Try each meta file
        for meta_file in meta_files:
            session_id = _extract_session_id_from_meta(meta_file)
            if session_id:
                # Messages file is in the same directory
                messages_file = os.path.join(os.path.dirname(meta_file), "messages.jsonl")
                if os.path.exists(messages_file):
                    return session_id, messages_file
                return session_id, None
        
        return None, None
        
    except Exception:
        return None, None


def _extract_session_id_from_meta(meta_file: str) -> Optional[str]:
    """Extract session_id from a Vibe meta.json file."""
    try:
        with open(meta_file, 'r', encoding='utf-8') as f:
            meta = json.load(f)
        return meta.get('session_id')
    except (json.JSONDecodeError, IOError, KeyError):
        return None


if __name__ == "__main__":
    # CLI usage: print session info as JSON for easy parsing
    session_id, transcript_path, agent_type = detect_session_id()
    
    import json
    result = {
        "agent_type": agent_type,
        "session_id": session_id,
        "transcript_path": transcript_path
    }
    print(json.dumps(result, ensure_ascii=False))
