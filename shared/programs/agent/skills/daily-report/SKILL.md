---
name: daily-report
description: Generate a personal daily activity report from configured sources (GitHub, Slack, Asana, session directories)
user-invocable: true
version: 2.0.0
---

Generate a daily activity report by reading `~/.agent/daily-report.json` to determine which sources to collect from.

## Step 1: Load Config

```bash
cat ~/.agent/daily-report.json
```

Parse the JSON. The `sources` key controls what to collect:
- `sources.github` — present → collect GitHub events
- `sources.slack` — present → collect Slack activity
- `sources.asana` — true → collect Asana tasks
- `sources.sessions.dir` — collect session directory artifacts

The `output` key controls where to write the report:
- `output.local` — present (or `output` absent) → save to `output.local.dir` as `daily-YYYY-MM-DD.md`
- `output.logseq` — present → also POST to Logseq HTTP API
  - `url` / `token` — each accepts a plain string, `{ "file": "..." }`, or `{ "command": "..." }`

If the file does not exist, print an error and stop:
> No config found at ~/.agent/daily-report.json. Set dotfiles.agent.dailyReport in your Nix profile.

Today's date: run `date +%Y-%m-%d`.

## Step 2: Collect Data (only enabled sources)

### GitHub (`sources.github`)

```bash
GITHUB_USER=$(cat ~/.agent/daily-report.json | jq -r '.sources.github.user')
TODAY=$(date +%Y-%m-%d)
gh api /users/$GITHUB_USER/events --paginate \
  -q ".[] | select(.created_at | startswith(\"$TODAY\"))" 2>/dev/null
```

Group by event type:
- `PushEvent` → repo, branch, commit messages (`.payload.commits[].message`)
- `PullRequestReviewEvent` / `PullRequestReviewCommentEvent` → repo, PR title
- `PullRequestEvent` → opened/merged PRs
- `CreateEvent` / `DeleteEvent` → branch lifecycle

### Slack (`sources.slack`)

First calculate today's midnight Unix timestamp (JST):
```bash
TODAY_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" "+%s" 2>/dev/null || \
           date -d "$(date +%Y-%m-%d) 00:00:00 JST" "+%s" 2>/dev/null)
```

Use `mcp__claude_ai_Slack__slack_search_public_and_private` with:
- `query`: `from:<@<sources.slack.user_id>>`
- `after`: `$TODAY_TS` (Unix timestamp — do NOT put `after:date` in the query string, it doesn't work for non-current years)
- `limit`: 20, `sort`: `timestamp`

For mentions:
- `query`: `<@<sources.slack.user_id>>`
- `after`: `$TODAY_TS`
- `limit`: 20

Note channels active in and key topics discussed.

### Asana (`sources.asana`)

Use `mcp__claude_ai_Asana__asana_search_tasks`:
- Updated today: `modified_on=TODAY`, `assignee_any=me`, `completed=false`
- Completed today: `completed_on=TODAY`, `assignee_any=me`
- `opt_fields`: `name,memberships.section.name,projects.name`

### Session Directories (`sources.sessions`)

```bash
SESSIONS_DIR=$(cat ~/.agent/daily-report.json | jq -r '.sources.sessions.dir' | sed "s|~|$HOME|")
TODAY=$(date +%Y-%m-%d)
for d in "$SESSIONS_DIR"/session-*/; do
  [ "$(date -r "$d" +%Y-%m-%d 2>/dev/null)" = "$TODAY" ] && echo "=== $d ===" && ls "$d"
done
```

## Step 3: Output

```markdown
# Daily Report — YYYY-MM-DD

## Summary
2-3 sentence narrative of the day.

## GitHub
### Commits & Pushes
- `repo` (branch): message

### Reviews
- `repo` PR#N: title

## Slack
### Sent
- `#channel`: topic

### Mentioned
- `#channel`: context

## Asana
### Updated
- [ ] task (project › section)

### Completed
- [x] task

## Agent Sessions
### session-XXXX
- Files: ...
- Purpose: ...

## Notes
Unresolved items or observations.
```

## Step 4: Save

### Local (`output.local`)

```bash
LOCAL_DIR=$(cat ~/.agent/daily-report.json | jq -r '.output.local.dir // "~/agent-sessions"' | sed "s|~|$HOME|")
```

Save the report to `$LOCAL_DIR/daily-YYYY-MM-DD.md`.
If `$ARGUMENTS` is provided, use that path instead.

### Logseq (`output.logseq`)

If `output.logseq` is present in config:

Both `url` and `token` support three forms: a plain string (static), `{ "file": "..." }`, or `{ "command": "..." }`.

```bash
TODAY=$(date +%Y-%m-%d)

# Resolve a value that may be a string, { file }, or { command }
resolve_secret() {
  local KEY="$1"
  local TYPE=$(cat ~/.agent/daily-report.json | jq -r "$KEY | type")
  if [ "$TYPE" = "string" ]; then
    cat ~/.agent/daily-report.json | jq -r "$KEY"
  else
    local SUBKEY=$(cat ~/.agent/daily-report.json | jq -r "$KEY | keys[0]")
    if [ "$SUBKEY" = "file" ]; then
      local PATH=$(cat ~/.agent/daily-report.json | jq -r "$KEY.file" | sed "s|~|$HOME|")
      cat "$PATH" 2>/dev/null
    elif [ "$SUBKEY" = "command" ]; then
      local CMD=$(cat ~/.agent/daily-report.json | jq -r "$KEY.command")
      eval "$CMD" 2>/dev/null
    fi
  fi
}

LOGSEQ_URL=$(resolve_secret '.output.logseq.url')
LOGSEQ_TOKEN=$(resolve_secret '.output.logseq.token')
```

Append to today's Logseq journal page (page name = `$TODAY`):

1. Create parent block with tag property:
```bash
PARENT_UUID=$(curl -sf \
  -H "Authorization: Bearer $LOGSEQ_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"method\": \"logseq.Editor.appendBlockInPage\", \"args\": [\"$TODAY\", \"Daily Report — $TODAY\ntags:: #daily-report\"]}" \
  "$LOGSEQ_URL/api" | jq -r '.result.uuid')
```

2. Insert report content as child block:
```bash
curl -sf \
  -H "Authorization: Bearer $LOGSEQ_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"method\": \"logseq.Editor.insertBlock\", \"args\": [\"$PARENT_UUID\", $(cat "$LOCAL_DIR/daily-$TODAY.md" | jq -Rs .), {\"sibling\": false}]}" \
  "$LOGSEQ_URL/api"
```

If the token cannot be resolved or any API call fails, print a warning and skip Logseq output without aborting.

Print all saved/posted locations when done.
