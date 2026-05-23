#!/usr/bin/env bash
# Claude Code PermissionRequest / Notification hook handler.
# No throttling — each event needs immediate attention.
# Reads hook JSON from stdin; auto-detects event type from fields.

HOOK_INPUT=$(cat)

SESSION_ID=$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    print('')
" 2>/dev/null)
SESSION_ID="${SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"

# Extract session title from transcript as summary
PROJECT_PATH=$(pwd | sed 's|/|-|g')
SUMMARY=$(TRANSCRIPT="$HOME/.claude/projects/${PROJECT_PATH}/${SESSION_ID}.jsonl" python3 -c "
import json, os
title = ''
try:
    with open(os.environ['TRANSCRIPT']) as f:
        for line in f:
            try:
                obj = json.loads(line)
                if obj.get('type') == 'ai-title':
                    title = obj.get('aiTitle', '')
            except Exception:
                pass
except Exception:
    pass
print(title)
" 2>/dev/null || true)

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null)

if [ -n "$TOOL_NAME" ]; then
  CONFIRMATION="Permission required: ${TOOL_NAME} (session: ${SESSION_ID})"
  PRIORITY="high"
  MSG_TYPE="confirmation"
else
  CONFIRMATION="Claude Code notification (session: ${SESSION_ID})"
  PRIORITY="medium"
  MSG_TYPE="info"
fi

exec "$HOME/.agent/skills/agent-rocket-chat-notify/notify.sh" \
  --agent-type claude-code \
  --session-id "$SESSION_ID" \
  --summary "$SUMMARY" \
  --type "$MSG_TYPE" \
  --priority "$PRIORITY" \
  --confirmation "$CONFIRMATION" \
  "$@"
