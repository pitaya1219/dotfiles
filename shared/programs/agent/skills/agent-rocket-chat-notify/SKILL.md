---
name: agent-rocket-chat-notify
description: Send RocketChat webhook notifications automatically when agent needs user confirmation
user-invocable: true
version: 1.0.0
autonomous: true
allowed-tools:
  - curl
  - passage
  - git
  - grep
  - sed
  - awk
  - date
  - basename
---

# Agent RocketChat Notification Skill

## What This Skill Does

Provides a standardized way for AI agents (Claude, Mistral Vibe, OpenCode, etc.) to send RocketChat webhook notifications when user confirmation is required during a session.

## Permissions

**This agent has explicit permission to:**
- Send notifications to RocketChat via configured webhooks **without requiring user confirmation**
- Retrieve webhook URLs from Passage secret store
- Auto-detect session information (ID, repository, agent type)
- Send notifications automatically when confirmation is needed
- Use the `homelab/rocket-chat/webhook/*` Passage secrets

**No user confirmation is required** for sending notifications. The agent may send notifications to `#agent-notifications` channel at any time when it needs user attention.

## When to Use

Use this skill when:
- The agent needs user input to proceed
- User confirmation is required for a critical decision
- A blocking situation requires human intervention
- Session progress needs to be communicated to the user

## Webhook URL Configuration

Webhook URLs are retrieved from Passage secret store with agent-specific paths:

| Agent Type | Passage Path |
|------------|--------------|
| Claude Code | `homelab/rocket-chat/webhook/claude` |
| Mistral Vibe | `homelab/rocket-chat/webhook/mistral-vibe` |
| OpenCode | `homelab/rocket-chat/webhook/opencode` |
| Other AI | `homelab/rocket-chat/webhook/ai` |
| Generic | `homelab/rocket-chat/webhook/default` |

## Message Structure

The notification message is a JSON payload sent via POST to the webhook URL:

```json
{
  "text": "[AI Agent] Confirmation Required",
  "attachments": [
    {
      "color": "#FFA500",
      "title": "🤖 Agent Confirmation Needed",
      "text": "Session requires your attention",
      "fields": [
        {"title": "Session ID", "value": "{{SESSION_ID}}", "short": true},
        {"title": "Repository", "value": "{{REPO}}", "short": true},
        {"title": "Agent", "value": "{{AGENT_TYPE}}", "short": true},
        {"title": "Session Summary", "value": "{{SESSION_SUMMARY}}", "short": false},
        {"title": "Confirmation Required", "value": "{{CONFIRMATION_ITEM}}", "short": false},
        {"title": "Timestamp", "value": "{{TIMESTAMP}}", "short": true}
      ],
      "footer": "Please respond to continue the session",
      "ts": "{{TIMESTAMP_EPOCH}}"
    }
  ]
}
```

## Required Information

### 1. Session ID
- **Source**: Session directory name or `VIBE_SESSION_ID` / `CLAUDE_SESSION_ID` environment variable
- **Format**: UUID string (e.g., `9de85976-8a2b-97b0-f872-4157480a2c8c`)
- **Extraction**: From directory name `session-{UUID}` or environment

```bash
# Extract from session directory
SESSION_DIR=$(basename $(pwd))
SESSION_ID=${SESSION_DIR#session-}

# Or from environment (Mistral Vibe)
SESSION_ID=${VIBE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}
```

### 2. Repository
- **Source**: Current git repository
- **Format**: Repository name or full URL
- **Extraction**: From git remote

```bash
REPO=$(git remote -v | head -1 | sed 's/.*\///' | sed 's/\.git$//')
REPO_URL=$(git remote -v | head -1 | awk '{print $2}')
```

### 3. Agent Type
- **Source**: Environment variables or detection
- **Format**: String identifier (e.g., `mistral-vibe`, `claude-code`, `opencode`)
- **Detection**:

```bash
# Detect agent type
if [ -n "$VIBE_SESSION_ID" ]; then
  AGENT_TYPE="mistral-vibe"
elif [ -n "$CLAUDE_SESSION_ID" ]; then
  AGENT_TYPE="claude-code"
elif [ -n "$OPENCODE_SESSION_ID" ]; then
  AGENT_TYPE="opencode"
else
  AGENT_TYPE="ai-agent"
fi
```

### 4. Session Summary
- **Source**: User-provided or generated from session context
- **Format**: One-line description (max 200 characters recommended)
- **Example**: "Implementing RocketChat notification skill for agent confirmations"

### 5. Confirmation Item
- **Source**: The specific question or action requiring confirmation
- **Format**: Clear, actionable statement
- **Examples**:
  - "Proceed with deleting session directory?"
  - "Merge feature branch into main?"
  - "Overwrite existing configuration file?"

## Usage Examples

### Example 1: Basic Confirmation Request

```bash
# Set variables
SESSION_ID="9de85976-8a2b-97b0-f872-4157480a2c8c"
REPO="dotfiles"
AGENT_TYPE="mistral-vibe"
SESSION_SUMMARY="Creating RocketChat notification skill"
CONFIRMATION_ITEM="Should I proceed with creating the skill directory?"

# Send notification
NOTIFY_SCRIPT="$HOME/.vibe/skills/agent-rocket-chat-notify/notify.sh"
"$NOTIFY_SCRIPT" \
  --session-id "$SESSION_ID" \
  --repo "$REPO" \
  --agent-type "$AGENT_TYPE" \
  --summary "$SESSION_SUMMARY" \
  --confirmation "$CONFIRMATION_ITEM"
```

### Example 2: From Session Directory

```bash
#!/bin/bash
# From within session directory

# Auto-detect information
SESSION_DIR=$(basename $(pwd))
SESSION_ID=${SESSION_DIR#session-}
REPO=$(git remote -v | head -1 | sed 's/.*\///' | sed 's/\.git$//')

# Detect agent
if [ -n "$VIBE_SESSION_ID" ]; then
  AGENT_TYPE="mistral-vibe"
elif [ -n "$CLAUDE_SESSION_ID" ]; then
  AGENT_TYPE="claude-code"
else
  AGENT_TYPE="ai-agent"
fi

# Get webhook URL
WEBHOOK_URL=$(passage show "homelab/rocket-chat/webhook/${AGENT_TYPE}" 2>/dev/null)
WEBHOOK_URL=${WEBHOOK_URL:-$(passage show "homelab/rocket-chat/webhook/default" 2>/dev/null)}

# Send notification
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"[${AGENT_TYPE}] Confirmation Required\",\"attachments\":[{\"color\":\"#FFA500\",\"title\":\"🤖 Agent Confirmation Needed\",\"text\":\"Session requires your attention\",\"fields\":[{\"title\":\"Session ID\",\"value\":\"${SESSION_ID}\",\"short\":true},{\"title\":\"Repository\",\"value\":\"${REPO}\",\"short\":true},{\"title\":\"Agent\",\"value\":\"${AGENT_TYPE}\",\"short\":true},{\"title\":\"Session Summary\",\"value\":\"${SESSION_SUMMARY}\",\"short\":false},{\"title\":\"Confirmation Required\",\"value\":\"${CONFIRMATION_ITEM}\",\"short\":false},{\"title\":\"Timestamp\",\"value\":\"$(date -Iseconds)\",\"short\":true}]}]}" \
  "$WEBHOOK_URL"
```

## Additional Features

### Priority Levels

You can add priority to notifications:

```json
{
  "color": "#FF0000",  // Red for high priority
  "color": "#FFA500",  // Orange for medium priority (default)
  "color": "#439FE0"   // Blue for low priority
}
```

### Message Types

Different message types can be indicated:

| Type | Color | Use Case |
|------|-------|----------|
| `confirmation` | `#FFA500` | User confirmation required |
| `error` | `#FF0000` | Critical error occurred |
| `info` | `#439FE0` | Informational update |
| `success` | `#00C292` | Operation completed successfully |
| `warning` | `#FFA500` | Warning about potential issues |

### Enhanced Message with Actions

For better user experience, include action buttons:

```json
{
  "text": "[AI Agent] Confirmation Required",
  "attachments": [
    {
      "color": "#FFA500",
      "title": "🤖 Agent Confirmation Needed",
      "text": "Session requires your attention",
      "fields": [...],
      "actions": [
        {
          "type": "button",
          "text": "Approve",
          "url": "https://your-bot-endpoint.com/approve?session={{SESSION_ID}}&action={{ACTION_ID}}",
          "style": "primary"
        },
        {
          "type": "button",
          "text": "Reject",
          "url": "https://your-bot-endpoint.com/reject?session={{SESSION_ID}}&action={{ACTION_ID}}",
          "style": "danger"
        }
      ]
    }
  ]
}

## Integration with Agent Workflows

### Pre-Confirmation Check

Before performing destructive actions:

```bash
# Before deleting a file
CONFIRMATION_ITEM="Delete file ${FILE_PATH} permanently?"
source shared/programs/agent/skills/agent-rocket-chat-notify/notify.sh --confirmation "$CONFIRMATION_ITEM"
# Wait for user response (implementation depends on your agent framework)
# Then proceed or abort based on response
```

### Session Start Notification

Notify user when a session starts:

```bash
SESSION_SUMMARY="Working on ${TASK_DESCRIPTION}"
CONFIRMATION_ITEM="Session started. No action required."
AGENT_TYPE="mistral-vibe"

# Use info color instead of confirmation color
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"[${AGENT_TYPE}] Session Started\",\"attachments\":[{\"color\":\"#439FE0\",\"title\":\"ℹ️ New Session\",\"text\":\"${SESSION_SUMMARY}\",\"fields\":[{\"title\":\"Session ID\",\"value\":\"${SESSION_ID}\",\"short\":true},{\"title\":\"Repository\",\"value\":\"${REPO}\",\"short\":true}]}]}" \
  "$WEBHOOK_URL"
```

### Session End Notification

Notify user when a session completes:

```bash
CONFIRMATION_ITEM="Session completed successfully"
# Use success color
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"[${AGENT_TYPE}] Session Complete\",\"attachments\":[{\"color\":\"#00C292\",\"title\":\"✅ Session Completed\",\"text\":\"${SESSION_SUMMARY}\",\"fields\":[{\"title\":\"Session ID\",\"value\":\"${SESSION_ID}\",\"short\":true},{\"title\":\"Duration\",\"value\":\"${DURATION}\",\"short\":true},{\"title\":\"Files Changed\",\"value\":\"${FILES_CHANGED}\",\"short\":true}]}]}" \
  "$WEBHOOK_URL"
```

## Error Handling

If webhook notification fails:
- Log the error to session directory
- Continue with default behavior (ask user directly)
- Don't block the session

```bash
if ! notify.sh --session-id "$SESSION_ID" --confirmation "$CONFIRMATION_ITEM"; then
  echo "[WARN] RocketChat notification failed, falling back to direct confirmation" >&2
  read -p "$CONFIRMATION_ITEM (y/n): " answer
fi
```

## Configuration Setup

### 1. Set Up Passage Secrets

```bash
# For each agent type, create a Passage secret
passage add homelab/rocket-chat/webhook/claude
passage add homelab/rocket-chat/webhook/mistral-vibe
passage add homelab/rocket-chat/webhook/opencode
passage add homelab/rocket-chat/webhook/default

# Enter the webhook URLs when prompted
```

### 2. Configure RocketChat Webhook

1. Go to RocketChat Administration > Integrations > New Integration > Incoming Webhook
2. Configure the webhook:
   - Name: `AI Agent Notifications`
   - Channel: `#ai-agents` or your preferred channel
   - Enable: Script Enabled (optional)
3. Copy the Webhook URL and store it in Passage

### 3. Test the Configuration

```bash
# Test Claude webhook
passage show homelab/rocket-chat/webhook/claude

# Test Mistral Vibe webhook
passage show homelab/rocket-chat/webhook/mistral-vibe

# Send test notification
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"text":"Test notification"}' \
  "$(passage show homelab/rocket-chat/webhook/default)"
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `VIBE_SESSION_ID` | Mistral Vibe session ID | No (auto-detected) |
| `CLAUDE_SESSION_ID` | Claude Code session ID | No (auto-detected) |
| `OPENCODE_SESSION_ID` | OpenCode session ID | No (auto-detected) |
| `ROCKETCHAT_WEBHOOK_URL` | Override webhook URL | No |
| `ROCKETCHAT_DEFAULT_CHANNEL` | Default channel for notifications | No |

## Best Practices

1. **Use appropriate message types**: Different colors for different situations
2. **Keep messages concise**: Session summary should be one line
3. **Include actionable information**: What does the user need to do?
4. **Don't spam**: Only send notifications for important confirmations
5. **Handle failures gracefully**: Fall back to direct user interaction if webhook fails
6. **Secure your webhooks**: Use Passage for secret management, don't hardcode URLs
7. **Rate limiting**: Consider rate limiting to avoid overwhelming users

## Related Files

- `notify.sh` - Helper script for sending notifications
- Passage secrets at `homelab/rocket-chat/webhook/*` - Webhook URL configurations

## Version History

- **1.0.0** (2025-01-XX): Initial version with basic notification support

---

**Maintainer**: AI Agent Team  
**Contact**: #ai-agents on RocketChat  
**License**: MIT
