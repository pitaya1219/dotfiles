---
name: daily-report
description: Generate a personal daily activity report from configured sources (GitHub, Slack, Asana, session directories)
user-invocable: true
version: 2.1.0
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

**Step A — Get own user GID** (needed for comment filtering):

Call `mcp__claude_ai_Asana__asana_get_user` (no arguments → returns authenticated user). Save `data.gid` as `MY_GID`.

**Step B — Assigned tasks**:

Use `mcp__claude_ai_Asana__asana_search_tasks` in parallel:
- Updated today: `modified_on=TODAY`, `assignee_any=me`, `completed=false`, `opt_fields=name,memberships.section.name,projects.name`
- Completed today: `completed_on=TODAY`, `assignee_any=me`, `opt_fields=name,projects.name`

Collect resulting task GIDs as `assigned_gids`.

**Step C — Comment activity on non-assigned tasks**:

Call `mcp__claude_ai_Asana__asana_search_tasks` with `followers_any=me`, `modified_on=TODAY`, `completed=false`, `opt_fields=name,projects.name`, `limit=50`.

From the results, exclude tasks already in `assigned_gids`. For each remaining task, call `mcp__claude_ai_Asana__asana_get_stories_for_task` (run lookups in parallel) with `opt_fields=created_by.gid,text,type,created_at`.

A task counts as "Commented" if it has at least one story where:
- `type == "comment"`
- `created_by.gid == MY_GID`
- `created_at` starts with TODAY (UTC date prefix, e.g. `2026-06-12`)

For matching tasks, record: task name, project name, and first 80 chars of the earliest matching comment.

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

### Commented
- task name (project) — "comment preview…"

## Agent Sessions
### session-XXXX
- Files: ...
- Purpose: ...

## Notes
Unresolved items or observations.
```

## Step 4: Save

### Local (`output.local`)

If `output.local` is present in config (or `output` key is absent entirely):

```bash
LOCAL_DIR=$(cat ~/.agent/daily-report.json | jq -r '.output.local.dir // "~/agent-sessions"' | sed "s|~|$HOME|")
```

Save the report to `$LOCAL_DIR/daily-YYYY-MM-DD.md`.
If `$ARGUMENTS` is provided, use that path instead.

### Logseq (`output.logseq`)

If `output.logseq` is present and truthy in config, invoke the **logseq-write** skill with:
- **Page**: today's date (e.g. `2026-06-08`)
- **Format**: `markdown`
- **Title**: `Daily Report — YYYY-MM-DD`
- **Tag**: `daily-report`
- **Content**: the report generated in Step 3

Print all saved/posted locations when done.
