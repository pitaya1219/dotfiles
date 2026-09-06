#!/bin/bash
# Matrix (matrix-hookshot generic webhook) Notification Script for AI Agents
#
# Supports two modes:
# 1. Command-line mode: notify.sh [OPTIONS] (original behavior)
# 2. Hooks mode: Reads JSON from stdin (Mistral Vibe experimental hooks)
#
# Usage (command-line):
#   ./matrix-notify.sh --confirmation "Delete file?"
#   ./matrix-notify.sh --session-id "abc123" --repo "myrepo" --confirmation "Merge branch?"
#
# Usage (hooks):
#   echo '{"session_id":"abc123","hook_event_name":"before_tool","tool_name":"bash"}' | ./matrix-notify.sh
#
# Sends notifications to a Matrix room via matrix-hookshot's generic webhook
# connector (homelab/apps/communication/hookshot) when an agent needs user
# confirmation. The webhook URL is retrieved from Passage.

set -euo pipefail

# Default values
SESSION_ID=""
REPO=""
AGENT_TYPE=""
SESSION_SUMMARY=""
CONFIRMATION_ITEM=""
WEBHOOK_URL=""
PRIORITY="medium"
MESSAGE_TYPE="confirmation"
HOOK_MODE=false

# Check if we're running in hooks mode (JSON on stdin)
# Hooks mode: stdin is not a terminal and has content
if ! [ -t 0 ] && [ -p /dev/stdin ]; then
    # Try to read stdin as JSON (hooks mode)
    HOOK_JSON=$(cat 2>/dev/null || true)

    # Check if stdin looks like JSON
    if command -v jq >/dev/null 2>&1 && echo "$HOOK_JSON" | jq empty 2>/dev/null; then
        HOOK_MODE=true

        # Extract values from hooks JSON
        SESSION_ID=$(echo "$HOOK_JSON" | jq -r '.session_id // ""')
        REPO=$(echo "$HOOK_JSON" | jq -r '.cwd // ""' | xargs -I{} basename {} 2>/dev/null || echo "")
        HOOK_EVENT=$(echo "$HOOK_JSON" | jq -r '.hook_event_name // ""')
        TOOL_NAME=$(echo "$HOOK_JSON" | jq -r '.tool_name // ""')
        TOOL_STATUS=$(echo "$HOOK_JSON" | jq -r '.tool_status // ""')
        TOOL_INPUT=$(echo "$HOOK_JSON" | jq -r '.tool_input // ""')
        TOOL_ERROR=$(echo "$HOOK_JSON" | jq -r '.tool_error // ""')
        TRANSCRIPT_PATH=$(echo "$HOOK_JSON" | jq -r '.transcript_path // ""')

        # Set agent type
        AGENT_TYPE="mistral-vibe"

        # Determine message type and confirmation text based on hook event.
        # NOTE: these must match vibe's actual HookType values (pre_tool /
        # post_tool / post_agent) -- the previous before_tool/after_tool/
        # post_agent_turn names never matched anything Vibe sends, so every
        # hook invocation silently fell through to the generic "*)" case.
        case "$HOOK_EVENT" in
            "pre_tool")
                if [ -n "$TOOL_NAME" ]; then
                    CONFIRMATION_ITEM="Tool execution requested: $TOOL_NAME"
                    if [ -n "$TOOL_INPUT" ]; then
                        # Truncate tool input if too long
                        TOOL_INPUT_PREVIEW=$(echo "$TOOL_INPUT" | head -c 100)
                        CONFIRMATION_ITEM="$CONFIRMATION_ITEM (input: $TOOL_INPUT_PREVIEW...)"
                    fi
                else
                    CONFIRMATION_ITEM="Tool execution requested"
                fi
                MESSAGE_TYPE="confirmation"
                PRIORITY="medium"
                ;;
            "post_tool")
                if [ -n "$TOOL_NAME" ]; then
                    if [ "$TOOL_STATUS" = "success" ]; then
                        CONFIRMATION_ITEM="Tool $TOOL_NAME completed successfully"
                        MESSAGE_TYPE="success"
                        PRIORITY="low"
                    elif [ "$TOOL_STATUS" = "failure" ]; then
                        CONFIRMATION_ITEM="Tool $TOOL_NAME failed: ${TOOL_ERROR:-Unknown error}"
                        MESSAGE_TYPE="error"
                        PRIORITY="high"
                    else
                        CONFIRMATION_ITEM="Tool $TOOL_NAME finished with status: $TOOL_STATUS"
                        MESSAGE_TYPE="info"
                        PRIORITY="medium"
                    fi
                else
                    CONFIRMATION_ITEM="Tool execution completed with status: $TOOL_STATUS"
                    MESSAGE_TYPE="info"
                fi
                ;;
            "post_agent")
                # Fires once per completed user turn (control back to the
                # user) -- the correct "waiting for response" signal, no
                # idle-guessing needed.
                CONFIRMATION_ITEM="Agent turn completed - awaiting next input"
                MESSAGE_TYPE="info"
                PRIORITY="low"
                ;;
            *)
                CONFIRMATION_ITEM="Vibe hook triggered: $HOOK_EVENT"
                MESSAGE_TYPE="info"
                ;;
        esac

        # post_agent-only: throttle (fires on every turn).
        if [ "$HOOK_EVENT" = "post_agent" ]; then
            RATE_LIMIT="${VIBE_NOTIFY_RATE:-10}"
            STATE_FILE="/tmp/vibe-notify-${SESSION_ID:-unknown}"
            NOW=$(date +%s)
            LAST_NOTIFY=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
            if (( NOW - LAST_NOTIFY < RATE_LIMIT )); then
                exit 0
            fi
            echo "$NOW" > "$STATE_FILE"

            if [ -n "$TRANSCRIPT_PATH" ]; then
                METAFILE="$(dirname "$TRANSCRIPT_PATH")/meta.json"
                if [ -f "$METAFILE" ]; then
                    SESSION_SUMMARY=$(METAFILE="$METAFILE" python3 -c "
import json, os
try:
    with open(os.environ['METAFILE']) as f:
        print(json.load(f).get('title', ''))
except Exception:
    print('')
" 2>/dev/null || true)
                fi
            fi
        fi

        # If repo is still empty, try to detect from current directory
        if [ -z "$REPO" ]; then
            REPO=$(git remote -v 2>/dev/null | head -1 | sed 's/.*\///' | sed 's/\.git$//' || echo "unknown")
        fi

        # If session_id is still empty, try environment variables
        if [ -z "$SESSION_ID" ]; then
            SESSION_ID=${VIBE_SESSION_ID:-${CLAUDE_SESSION_ID:-${OPENCODE_SESSION_ID:-}}}
        fi

        # If still empty, try directory name
        if [ -z "$SESSION_ID" ]; then
            CURRENT_DIR=$(basename $(pwd) 2>/dev/null || echo "")
            if [[ "$CURRENT_DIR" =~ ^session-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$ ]]; then
                SESSION_ID="${BASH_REMATCH[1]}"
            fi
        fi

        # Default to unknown if still empty
        SESSION_ID=${SESSION_ID:-unknown}
    fi
fi

# If not in hooks mode, parse command-line arguments (original behavior)
if [ "$HOOK_MODE" = false ]; then
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --session-id)
                SESSION_ID="$2"
                shift 2
                ;;
            --repo)
                REPO="$2"
                shift 2
                ;;
            --agent-type)
                AGENT_TYPE="$2"
                shift 2
                ;;
            --summary)
                SESSION_SUMMARY="$2"
                shift 2
                ;;
            --confirmation)
                CONFIRMATION_ITEM="$2"
                shift 2
                ;;
            --webhook-url)
                WEBHOOK_URL="$2"
                shift 2
                ;;
            --color)
                # Accepted for CLI compatibility with the old rocketchat-notify.sh
                # call sites; Matrix messages have no per-message color, so this
                # is a no-op.
                shift 2
                ;;
            --priority)
                PRIORITY="$2"
                shift 2
                ;;
            --type)
                MESSAGE_TYPE="$2"
                shift 2
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                echo "Usage: $0 [OPTIONS]" >&2
                echo "  --session-id SESSION_ID    Session UUID" >&2
                echo "  --repo REPO                Repository name" >&2
                echo "  --agent-type TYPE          Agent type" >&2
                echo "  --summary TEXT             Session summary" >&2
                echo "  --confirmation TEXT        Confirmation item (REQUIRED)" >&2
                echo "  --webhook-url URL          Override webhook URL" >&2
                echo "  --priority PRIORITY        Priority: low, medium, high" >&2
                echo "  --type TYPE                Message type: confirmation, error, info, success, warning" >&2
                exit 1
                ;;
        esac
    done

    # Auto-detect if not provided
    # Use ${VAR:-} to avoid unbound variable errors with set -u
    SESSION_ID=${SESSION_ID:-${VIBE_SESSION_ID:-${CLAUDE_SESSION_ID:-${OPENCODE_SESSION_ID:-}}}}

    # Try to detect from session directory name if still empty
    if [ -z "$SESSION_ID" ]; then
        CURRENT_DIR=$(basename $(pwd) 2>/dev/null || echo "")
        if [[ "$CURRENT_DIR" =~ ^session-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$ ]]; then
            SESSION_ID="${BASH_REMATCH[1]}"
        fi
    fi

    # Default to unknown if still empty
    SESSION_ID=${SESSION_ID:-unknown}

    REPO=${REPO:-$(git remote -v 2>/dev/null | head -1 | sed 's/.*\///' | sed 's/\.git$//' || echo "unknown")}

    # Detect agent type if not provided
    if [ -z "$AGENT_TYPE" ]; then
        if [ -n "${VIBE_SESSION_ID:-}" ]; then
            AGENT_TYPE="mistral-vibe"
        elif [ -n "${CLAUDE_SESSION_ID:-}" ]; then
            AGENT_TYPE="claude-code"
        elif [ -n "${OPENCODE_SESSION_ID:-}" ]; then
            AGENT_TYPE="opencode"
        else
            AGENT_TYPE="ai-agent"
        fi
    fi
fi

# Get webhook URL from Passage if not provided. One shared generic-webhook
# connector for every agent type (matrix-hookshot room command
# `!hookshot webhook homelab-agents`) -- the `username` field in the payload
# is what tells them apart in the room, so there's no per-agent-type fallback
# chain to maintain here.
if [ -z "$WEBHOOK_URL" ]; then
    WEBHOOK_URL=$(passage show "homelab/matrix/hookshot/webhook/agents" 2>/dev/null || true)
    WEBHOOK_URL=${WEBHOOK_URL:-${MATRIX_NOTIFY_WEBHOOK_URL:-}}
fi

# Validate required fields
if [ -z "$WEBHOOK_URL" ]; then
    # In hooks mode, silently exit (don't break the hook chain)
    if [ "$HOOK_MODE" = true ]; then
        exit 0
    else
        echo "ERROR: No webhook URL available. Set up passage secret at homelab/matrix/hookshot/webhook/agents" >&2
        exit 1
    fi
fi

# In hooks mode, CONFIRMATION_ITEM might be set from the hook event
# But we still need to validate we have something to send
if [ -z "$CONFIRMATION_ITEM" ]; then
    # In hooks mode, silently exit
    if [ "$HOOK_MODE" = true ]; then
        exit 0
    else
        echo "ERROR: Confirmation item is required (--confirmation)" >&2
        exit 1
    fi
fi

# Build short session label: e.g. "vibe-968ef4fc" or "claude-a1b2c3d4"
case "$AGENT_TYPE" in
    claude-code)  SHORT_TYPE="claude" ;;
    mistral-vibe) SHORT_TYPE="vibe" ;;
    opencode)     SHORT_TYPE="opencode" ;;
    *)            SHORT_TYPE="agent" ;;
esac
SESSION_LABEL="${SHORT_TYPE}-${SESSION_ID:0:8}"

# Determine title based on message type
case "$MESSAGE_TYPE" in
    error)   TITLE="Agent Error" ;;
    info)    TITLE="Agent Info" ;;
    success) TITLE="Agent Success" ;;
    warning) TITLE="Agent Warning" ;;
    confirmation|*) TITLE="Agent Confirmation Needed" ;;
esac

BODY="[${SESSION_LABEL}] ${TITLE}"$'\n'"repo: ${REPO} | priority: ${PRIORITY}"
if [ -n "$SESSION_SUMMARY" ]; then
    BODY="${BODY}"$'\n'"${SESSION_SUMMARY}"
fi
BODY="${BODY}"$'\n'"${CONFIRMATION_ITEM}"

# matrix-hookshot's generic webhook maps a top-level "text" field to the
# Matrix message body and prepends "username" as the room-visible sender
# label -- no attachments/color fields like the old Rocket.Chat payload.
JSON_PAYLOAD=$(jq -n --arg username "$AGENT_TYPE" --arg text "$BODY" '{username: $username, text: $text}')

# curl already prints "000" via %{http_code} on a connection failure (no
# HTTP response at all); `|| true` just keeps its own non-zero exit (e.g. 7)
# from tripping `set -e` before that "000" is checked below.
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$WEBHOOK_URL" 2>/dev/null || true)

if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "201" ]; then
    if [ "$HOOK_MODE" = false ]; then
        echo "Notification sent to Matrix (session: ${SESSION_ID}, repo: ${REPO})"
    fi
    exit 0
else
    if [ "$HOOK_MODE" = true ]; then
        exit 0
    else
        echo "ERROR: Failed to send notification (HTTP ${RESPONSE})" >&2
        exit 1
    fi
fi
