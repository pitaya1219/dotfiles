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
#
# The running agent is identified from the process environment FIRST and treated as
# authoritative. Filesystem heuristics only ever look in the store of the agent we
# are actually running under, so a leftover log from the *other* agent can never
# masquerade as the current session (e.g. an old ~/.vibe session being picked up
# while running under Claude Code).

AGENT_TYPE="unknown"
SESSION_ID=""
TRANSCRIPT_PATH=""
WORKDIR_ENCODED=$(pwd | sed 's|/|-|g')

# --- Identify the running agent from the environment (authoritative) --------
# Claude Code sets CLAUDECODE=1, AI_AGENT=claude-code_*, and (recent CLIs)
# CLAUDE_CODE_SESSION_ID. Vibe sets its own markers. Trust these over the
# filesystem so we never cross-label one agent's session as the other's.
_running="unknown"
case "${AI_AGENT:-}" in
  claude-code*) _running="claude-code" ;;
  vibe*)        _running="vibe" ;;
esac
if [ "$_running" = "unknown" ]; then
  if [ "${CLAUDECODE:-}" = "1" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    _running="claude-code"
  elif [ -n "${VIBE_SESSION_ID:-}" ]; then
    _running="vibe"
  fi
fi

# --- Claude Code -----------------------------------------------------------
# Runs when we know we are under Claude Code, or when the agent is unknown
# (best-effort probe of the Claude store).
if [ "$_running" = "claude-code" ] || [ "$_running" = "unknown" ]; then

  # 0. Authoritative: session id straight from the environment (recent CLI).
  #    The transcript is <session-id>.jsonl under some project dir; the id is
  #    globally unique, so match it by name and ignore pwd entirely.
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    SESSION_ID="$CLAUDE_CODE_SESSION_ID"
    AGENT_TYPE="claude-code"
    TRANSCRIPT_PATH=$(ls -t "$HOME/.claude/projects"/*/"${SESSION_ID}.jsonl" 2>/dev/null | head -1)
  fi

  # 1. ~/.claude/projects/<workdir-encoded>/<uuid>.jsonl (is the transcript).
  if [ -z "$SESSION_ID" ]; then
    _cc_jsonl=$(ls -t "$HOME/.claude/projects/${WORKDIR_ENCODED}"/*.jsonl 2>/dev/null | head -1)
    if [ -n "$_cc_jsonl" ]; then
      SESSION_ID=$(basename "$_cc_jsonl" .jsonl)
      TRANSCRIPT_PATH="$_cc_jsonl"
      AGENT_TYPE="claude-code"
    fi
  fi

  # 1b. Claude Code keys the project dir by the cwd it was launched from, which
  #     may be an ANCESTOR of the current dir (e.g. a git clone in a subdir).
  #     Walk up parent dirs and try each ancestor's encoded key.
  if [ -z "$SESSION_ID" ]; then
    _d="$(pwd)"
    while [ "$_d" != "/" ] && [ -z "$SESSION_ID" ]; do
      _d=$(dirname "$_d")
      _enc=$(printf '%s' "$_d" | sed 's|/|-|g')
      _cc_jsonl=$(ls -t "$HOME/.claude/projects/${_enc}"/*.jsonl 2>/dev/null | head -1)
      if [ -n "$_cc_jsonl" ]; then
        SESSION_ID=$(basename "$_cc_jsonl" .jsonl)
        TRANSCRIPT_PATH="$_cc_jsonl"
        AGENT_TYPE="claude-code"
      fi
    done
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

  # For methods 1b/2/3 the transcript is reconstructable by matching the id.
  if [ "$AGENT_TYPE" = "claude-code" ] && [ -z "$TRANSCRIPT_PATH" ] && [ -n "$SESSION_ID" ]; then
    _cc_reconstructed=$(ls -t "$HOME/.claude/projects"/*/"${SESSION_ID}.jsonl" 2>/dev/null | head -1)
    [ -z "$_cc_reconstructed" ] && [ -f "$HOME/.claude/projects/${WORKDIR_ENCODED}/${SESSION_ID}.jsonl" ] \
      && _cc_reconstructed="$HOME/.claude/projects/${WORKDIR_ENCODED}/${SESSION_ID}.jsonl"
    [ -n "$_cc_reconstructed" ] && TRANSCRIPT_PATH="$_cc_reconstructed"
  fi
fi

# --- Vibe ------------------------------------------------------------------
# 4. <base>/logs/session/session_*/{meta.json,messages.jsonl}
# Only when we are NOT running under Claude Code — otherwise a leftover Vibe
# log from a previous session would masquerade as the current one.
if [ -z "$SESSION_ID" ] && [ "$_running" != "claude-code" ]; then
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
