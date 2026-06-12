# Asana collector (`sources.asana`)

Feeds the report's **Asana** section (Updated / Completed / Commented).

## Step A — Own user GID (for comment filtering)

Call `mcp__claude_ai_Asana__asana_get_user` (no arguments → returns authenticated user). Save `data.gid` as `MY_GID`.

## Step B — Assigned tasks

Use `mcp__claude_ai_Asana__asana_search_tasks` in parallel:
- Updated today: `modified_on=TODAY`, `assignee_any=me`, `completed=false`, `opt_fields=name,memberships.section.name,projects.name`
- Completed today: `completed_on=TODAY`, `assignee_any=me`, `opt_fields=name,projects.name`

Collect resulting task GIDs as `assigned_gids`.

## Step C — Comment activity on non-assigned tasks

Call `mcp__claude_ai_Asana__asana_search_tasks` with `followers_any=me`, `modified_on=TODAY`, `completed=false`, `opt_fields=name,projects.name`, `limit=50`.

From the results, exclude tasks already in `assigned_gids`. For each remaining task, call `mcp__claude_ai_Asana__asana_get_stories_for_task` (run lookups in parallel) with `opt_fields=created_by.gid,text,type,created_at`.

A task counts as "Commented" if it has at least one story where:
- `type == "comment"`
- `created_by.gid == MY_GID`
- `created_at` starts with TODAY (UTC date prefix, e.g. `2026-06-12`)

For matching tasks, record: task name, project name, and first 80 chars of the earliest matching comment.

## API call budget

Per report: `asana_get_user` ×1, `asana_search_tasks` ×3, `asana_get_stories_for_task` ×(non-assigned followers, ~10–15). Total ~15–20 (acceptable).
