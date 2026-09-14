# Asana collector (`sources.asana`)

Feeds the report's **Asana** section (Updated / Completed / Commented).

`DATE` below is the report date (`bash scripts/lib.sh report_date`). The search
filters take explicit dates, so nothing here depends on the day being today.

## Step A — Own user GID (for comment filtering)

Call `mcp__claude_ai_Asana__get_me` (no arguments). Save `data.gid` as `MY_GID`.

## Step B — Assigned tasks

Use `mcp__claude_ai_Asana__search_tasks` in parallel. The date filters are
range-only — there is no bare `modified_on` / `completed_on`, so pin both ends
to `DATE` to get a single day:

- Updated: `modified_on_after=DATE`, `modified_on_before=DATE`, `assignee_any=me`, `completed=false`, `opt_fields=name,memberships.section.name,projects.name`
- Completed: `completed_on_after=DATE`, `completed_on_before=DATE`, `assignee_any=me`, `completed=true`, `opt_fields=name,projects.name`

Collect resulting task GIDs as `assigned_gids`.

## Step C — Comment activity on non-assigned tasks

Call `mcp__claude_ai_Asana__search_tasks` with `followers_any=me`,
`modified_on_after=DATE`, `modified_on_before=DATE`, `completed=false`,
`opt_fields=name,projects.name`, `limit=50`.

From the results, exclude tasks already in `assigned_gids`. For each remaining
task, call `mcp__claude_ai_Asana__get_task` (run lookups in parallel) with
`include_subtasks=false`, `opt_fields=name`, and `comment_limit` set to a
little more than a busy day's traffic (5–10). It returns the *most recent*
comments, which is the only part of the thread that can fall on `DATE`.

A task counts as "Commented" if one of those comments has
`created_by.gid == MY_GID` and a `created_at` whose UTC date is `DATE`.

For matching tasks, record: task name, project name, and first 80 chars of the
earliest matching comment.

> Do not reach for `get_task_stories` here. It ignores `opt_fields`, so every
> call returns the task's whole activity feed with full comment bodies — tens of
> thousands of tokens per busy task, and paginated on top. Use it only when the
> full history is actually the thing you need.

## API call budget

Per report: `get_me` ×1, `search_tasks` ×3, `get_task` ×(non-assigned
followers, ~10–20). Total ~15–25 (acceptable).
