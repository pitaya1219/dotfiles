#!/bin/bash
# RocketChat Webhook Notification Script for AI Agents
# Usage: notify.sh [OPTIONS]
#
# Send notifications to RocketChat when agent needs user confirmation.
# Webhook URLs are retrieved from Passage secret store.
#
# Options:
#   --session-id SESSION_ID    Session UUID (default: auto-detect from env or directory)
#   --repo REPO                Repository name (default: auto-detect from git)
#   --agent-type TYPE          Agent type: claude-code, mistral-vibe, opencode, ai-agent
#   --summary TEXT             One-line session summary
#   --confirmation TEXT        Confirmation item (REQUIRED)
#   --webhook-url URL          Override webhook URL
#   --color COLOR              Message color (default: #FFA500 for confirmation)
#   --priority PRIORITY        Priority level: low, medium, high (default: medium)
#   --type TYPE                Message type: confirmation, error, info, success, warning
#
# Examples:
#   ./notify.sh --confirmation "Delete file?"
#   ./notify.sh --session-id "abc123" --repo "myrepo" --confirmation "Merge branch?"

set -euo pipefail

# Default values
SESSION_ID=""
REPO=""
AGENT_TYPE=""
SESSION_SUMMARY=""
CONFIRMATION_ITEM=""
WEBHOOK_URL=""
COLOR="#FFA500"
PRIORITY="medium"
MESSAGE_TYPE="confirmation"

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
      COLOR="$2"
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
      echo "  --color COLOR              Message color" >&2
      echo "  --priority PRIORITY        Priority: low, medium, high" >&2
      echo "  --type TYPE                Message type: confirmation, error, info, success, warning" >&2
      exit 1
      ;;
  esac
done

# Auto-detect if not provided
# Use ${VAR:-} to avoid unbound variable errors with set -u
SESSION_ID=${SESSION_ID:-${VIBE_SESSION_ID:-${CLAUDE_SESSION_ID:-${OPENCODE_SESSION_ID:-}}}}}

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

# Set color based on message type if not overridden
if [ -n "$MESSAGE_TYPE" ] && [ "$COLOR" = "#FFA500" ]; then
  case "$MESSAGE_TYPE" in
    error)
      COLOR="#FF0000"
      ;;
    info)
      COLOR="#439FE0"
      ;;
    success)
      COLOR="#00C292"
      ;;
    warning)
      COLOR="#FFA500"
      ;;
    confirmation)
      COLOR="#FFA500"
      ;;
  esac
fi

# Set color based on priority if still default
if [ "$COLOR" = "#FFA500" ] && [ -n "$PRIORITY" ]; then
  case "$PRIORITY" in
    high)
      COLOR="#FF0000"
      ;;
    low)
      COLOR="#439FE0"
      ;;
    medium)
      COLOR="#FFA500"
      ;;
  esac
fi

# Get webhook URL from Passage if not provided
if [ -z "$WEBHOOK_URL" ]; then
  # Try agent-specific path first
  WEBHOOK_URL=$(passage show "homelab/rocket-chat/webhook/${AGENT_TYPE}" 2>/dev/null || true)
  
  # Fall back to default if agent-specific not found
  if [ -z "$WEBHOOK_URL" ]; then
    WEBHOOK_URL=$(passage show "homelab/rocket-chat/webhook/default" 2>/dev/null || true)
  fi
  
  # Fall back to ai path
  if [ -z "$WEBHOOK_URL" ]; then
    WEBHOOK_URL=$(passage show "homelab/rocket-chat/webhook/ai" 2>/dev/null || true)
  fi
  
  # Allow environment variable override
  WEBHOOK_URL=${WEBHOOK_URL:-${ROCKETCHAT_WEBHOOK_URL:-}}
fi

# Validate required fields
if [ -z "$WEBHOOK_URL" ]; then
  echo "ERROR: No webhook URL available. Set up passage secret at homelab/rocket-chat/webhook/" >&2
  exit 1
fi

if [ -z "$CONFIRMATION_ITEM" ]; then
  echo "ERROR: Confirmation item is required (--confirmation)" >&2
  exit 1
fi

# Build timestamp
TIMESTAMP=$(date -Iseconds)
TIMESTAMP_EPOCH=$(date +%s)

# Set default summary if not provided
SESSION_SUMMARY=${SESSION_SUMMARY:-${SESSION_SUMMARY_UPPER:-No summary provided}}

# Determine title based on message type
case "$MESSAGE_TYPE" in
  error)
    TITLE="❌ Agent Error"
    ;;
  info)
    TITLE="ℹ️ Agent Info"
    ;;
  success)
    TITLE="✅ Agent Success"
    ;;
  warning)
    TITLE="⚠️ Agent Warning"
    ;;
  confirmation|*)
    TITLE="🤖 Agent Confirmation Needed"
    ;;
esac

# Build short session label: e.g. "claude-968ef4fc" or "vibe-a1b2c3d4"
case "$AGENT_TYPE" in
  claude-code)  SHORT_TYPE="claude" ;;
  mistral-vibe) SHORT_TYPE="vibe" ;;
  opencode)     SHORT_TYPE="opencode" ;;
  *)            SHORT_TYPE="agent" ;;
esac
SESSION_LABEL="${SHORT_TYPE}-${SESSION_ID:0:8}"

# Send notification
# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "text": "[${SESSION_LABEL}] Confirmation Required",
  "attachments": [{
    "color": "${COLOR}",
    "title": "${TITLE}",
    "text": "Session ${SESSION_ID} requires your attention",
    "fields": [
      {"title": "Session ID", "value": "${SESSION_ID}", "short": true},
      {"title": "Repository", "value": "${REPO}", "short": true},
      {"title": "Agent", "value": "${AGENT_TYPE}", "short": true},
      {"title": "Priority", "value": "${PRIORITY}", "short": true},
      {"title": "Session Summary", "value": "${SESSION_SUMMARY:-No summary provided}", "short": false},
      {"title": "Confirmation Required", "value": "${CONFIRMATION_ITEM}", "short": false},
      {"title": "Timestamp", "value": "${TIMESTAMP}", "short": true}
    ],
    "footer": "Please respond to continue the session",
    "ts": ${TIMESTAMP_EPOCH}
  }]
}
EOF
)

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$WEBHOOK_URL" 2>&1)

# Check response - RocketChat returns OK or similar on success
if echo "$RESPONSE" | grep -qi "ok\|success\|{.*\"ok\":.*true.*}"; then
  echo "Notification sent successfully to RocketChat"
  echo "Webhook: ${WEBHOOK_URL}"
  echo "Session: ${SESSION_ID}"
  echo "Repository: ${REPO}"
  exit 0
else
  echo "ERROR: Failed to send notification" >&2
  echo "Response: $RESPONSE" >&2
  exit 1
fi
