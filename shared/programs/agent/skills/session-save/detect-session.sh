#!/usr/bin/env bash
# detect-session.sh — resolve the current agent session's identity and transcript.
#
# Source this (do not exec) to populate, in the caller's shell:
#   AGENT_TYPE       claude-code | vibe | unknown
#   SESSION_ID       session UUID (or trailing hash for Vibe fallback); may be empty
#   WORKDIR_ENCODED  $(pwd) with '/' → '-' (Claude Code project-dir encoding)
#   TRANSCRIPT_PATH  absolute path to the full raw transcript (.jsonl); may be empty
#
# All agent-type branching for session-save lives here so SKILL.md stays orchestration.
# Best-effort: leaves values empty rather than failing when nothing is detected.

AGENT_TYPE="unknown"
SESSION_ID=""
TRANSCRIPT_PATH=""
WORKDIR_ENCODED=$(pwd | sed 's|/|-|g')

# --- Claude Code -----------------------------------------------------------
# 1. ~/.claude/projects/<workdir-encoded>/<uuid>.jsonl (most reliable; is the transcript)
_cc_jsonl=$(ls -t "$HOME/.claude/projects/${WORKDIR_ENCODED}"/*.jsonl 2>/dev/null | head -1)
if [ -n "$_cc_jsonl" ]; then
  SESSION_ID=$(basename "$_cc_jsonl" .jsonl)
  TRANSCRIPT_PATH="$_cc_jsonl"
  AGENT_TYPE="claude-code"
fi

# 2. Claude Code /tmp tasks dir filtered by workdir (SESSION_ID only)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(find /tmp -maxdepth 7 -type d -name "tasks" 2>/dev/null | \
    grep -e "${WORKDIR_ENCODED}" | \
    while read d; do echo "$(stat -c %Y "$d") $d"; done | \
    sort -rn | head -1 | awk '{print $2}' | \
    grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
  [ -n "$SESSION_ID" ] && AGENT_TYPE="claude-code"
fi

# 3. Claude Code /tmp tasks dir across all workdirs (SESSION_ID only)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(find /tmp -maxdepth 7 -type d -name "tasks" -path "*/claude-*" 2>/dev/null | \
    while read d; do echo "$(stat -c %Y "$d") $d"; done | \
    sort -rn | head -1 | awk '{print $2}' | \
    grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
  [ -n "$SESSION_ID" ] && AGENT_TYPE="claude-code"
fi

# For methods 2/3 the transcript is reconstructable from the encoded workdir + id.
if [ "$AGENT_TYPE" = "claude-code" ] && [ -z "$TRANSCRIPT_PATH" ] && [ -n "$SESSION_ID" ]; then
  _cc_reconstructed="$HOME/.claude/projects/${WORKDIR_ENCODED}/${SESSION_ID}.jsonl"
  [ -f "$_cc_reconstructed" ] && TRANSCRIPT_PATH="$_cc_reconstructed"
fi

# --- Vibe ------------------------------------------------------------------
# 4. <base>/logs/session/session_*/{meta.json,messages.jsonl}
if [ -z "$SESSION_ID" ]; then
  _meta=$(ls -dt \
    "$(pwd)/.vibe/logs/session"/session_*/meta.json \
    "$HOME/agent-sessions/.vibe/logs/session"/session_*/meta.json \
    "${VIBE_HOME:-$HOME/.vibe}/logs/session"/session_*/meta.json \
    2>/dev/null | head -1)
  if [ -n "$_meta" ]; then
    AGENT_TYPE="vibe"
    SESSION_ID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['session_id'])" "$_meta" 2>/dev/null)
    [ -z "$SESSION_ID" ] && SESSION_ID=$(echo "$_meta" | grep -oE 'session_[0-9]+_[0-9]+_([0-9a-f]+)' | grep -oE '[0-9a-f]+$')
    _vibe_msgs="$(dirname "$_meta")/messages.jsonl"
    [ -f "$_vibe_msgs" ] && TRANSCRIPT_PATH="$_vibe_msgs"
  fi
fi

export AGENT_TYPE SESSION_ID WORKDIR_ENCODED TRANSCRIPT_PATH
