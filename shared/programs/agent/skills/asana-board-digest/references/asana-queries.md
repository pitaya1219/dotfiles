# Asana MCP recipes for the board digest

## Contents

- Pass 1 — tasks changed since the cutoff (and why it is not exhaustive)
- Pass 2 — board inventory for staleness (and why `sections_any` is unusable)
- Reading stories without drowning (two-phase walk, wait-reason comments)
- `resource_subtype` values worth acting on
- Telling a real update from a bulk sweep
- `modified_at` moved but there are no stories
- Call budget

Tools live on the `claude_ai_Asana` MCP server and must be called by their fully
qualified names — `mcp__claude_ai_Asana__search_tasks` and so on — since several MCP
servers are usually connected and a bare name resolves to nothing. Verify the roster
with ToolSearch before the first call: the server has renamed tools before
(`asana_search_tasks` → `search_tasks`), and a stale name fails the whole run.

## Pass 1 — tasks changed since the cutoff

```
mcp__claude_ai_Asana__search_tasks
  projects_any     = <projectGid>
  modified_at_after= <cutoff from scripts/bizdays.py>
  limit            = 100
  opt_fields       = name,completed,assignee.name,modified_at,
                     memberships.project.gid,memberships.section.name
```

`modified_at_after` takes UTC while the board is read in JST, which is why the cutoff
comes from `scripts/bizdays.py cutoff` rather than being assembled by hand: midnight
JST is 15:00Z on the *previous* day.

`modified_at` **does** advance on a new comment, so this query reliably finds
discussion, not just field edits. It also advances on things that leave no story at
all (see below), so a hit here is a candidate, not a confirmed update.

`memberships` is the lane fallback for tasks outside the work/wait lanes, which pass 2
never sees. It carries one entry per project the task belongs to, so read the entry
whose `project.gid` is the configured project — hence `memberships.project.gid` in
`opt_fields`, without which the entries cannot be told apart. Some tasks come back
with `memberships: []` despite sitting in a lane (subtasks pulled in by the project
filter behave this way), which is why pass 2 outranks this field rather than the
other way round.

`completed` marks tasks closed inside the window, which belong in the digest as
closures. Every other field costs tokens on all 100 rows without being printed —
`due_on` and `created_at` in particular have no consumer here.

### This query is neither exhaustive nor sorted

Two behaviours, both measured on Elec Hub on 2026-09-01 and both of which lose tasks
without saying so:

**It omits tasks that match.** `恒久対応③` (`1215644962268046`, modified
`2026-09-01T01:43:30`) did not come back, while tasks modified at 00:56 and 02:25 the
same day did — so this is neither the 100-row cap nor a window edge, and it reproduced
on two consecutive runs. Pass 2 returned the task in `Doing`, where it belonged. So
take the **union** of pass 1 and every pass-2 task whose `modified_at` is at or after
the cutoff: the work and wait lanes are then covered twice, and only the ignored lanes
are left resting on pass 1 alone.

**The rows are not ordered by `modified_at`.** A task modified at 09:05 came back near
the end of the list and one modified at 01:24 came back last, so "the last row is the
oldest" is not true and neither is the API's documented default sort. If the query
returns exactly 100 rows it truncated, and the way to collect the remainder is to
re-run with `modified_at_after = min(modified_at)` across the rows already in hand —
correct whatever the order turns out to be, at the price of re-fetching the ties.
Splitting the window in half instead re-fetches up to 100 rows you already have.

## Pass 2 — board inventory for staleness

`search_tasks` caps at 100 results and exposes no offset, so a project-wide "all
incomplete tasks" query silently truncates — Elec Hub alone carries ~300 incomplete
tasks. Query per section with `get_tasks`, which paginates:

```
mcp__claude_ai_Asana__get_tasks
  section         = <section gid>
  completed_since = <today 00:00Z>
  limit           = 100
  offset          = <next_page.offset, when present>
  opt_fields      = name,completed,assignee.name,modified_at
```

One call per classified lane. Section GIDs come from
`get_project(project_id, include_sections=true)`; do not hardcode them, boards get
re-organised.

`get_tasks` has no `completed=false` filter, and finished tasks stay in the lane they
were completed in — `Checking with W/S or Kraken` returned 63 rows of which 43 were
closed. `completed_since` means "incomplete, or completed after this instant", so
passing today's date returns essentially just the open ones: the same query dropped
to 20 rows. Still drop any `completed == true` client-side, since a task closed
earlier today survives the filter.

### Do not use `search_tasks(sections_any=…)` for this

It does not filter to the section. Measured on Elec Hub, 2026-09-01:
`sections_any = <Doing>` returned `中止イベントリカバリ_Failed to get contract unitの修正`,
whose `memberships` puts it squarely in `Checking with W/S or Kraken（カンバン）`.
`get_tasks(section = <Doing>)` did not return it. A staleness report built on
`sections_any` attributes tasks to the wrong lane, which then picks the wrong tier.

## Reading stories without drowning

`get_task_stories` returns **oldest first** and paginates forward only. For a ticket
opened a year ago, the recent activity is on the last page, and there is no way to
seek to it. Walking it in the obvious way — every page, every field — is what makes a
single old ticket cost 20k tokens, and discarding the text afterwards saves nothing,
because the tokens were spent when the response arrived.

Walk it in two phases instead. First find the boundary with the text left out:

```
mcp__claude_ai_Asana__get_task_stories
  task_id    = <gid>
  limit      = 100
  offset     = <next_page.offset, when present>
  opt_fields = created_at,resource_subtype
```

A story reduced to those two fields costs a few dozen tokens, so a year of history is
a few thousand rather than twenty thousand. Note the offset of the page where
`created_at` first reaches the cutoff, then re-request that page and any after it with
`opt_fields=created_at,created_by.name,resource_subtype,text`.

Process tasks in batches and append the per-task summary to a scratch file as you go.
A run over a busy board exceeds what fits in one context, and the notes file is what
survives a mid-run summarisation.

For the wait-reason check in Step 4 of the skill, comments alone are enough and
`get_task` returns the **newest** ones directly. Ask for only those:

```
mcp__claude_ai_Asana__get_task
  task_id          = <gid>
  include_comments = true
  comment_limit    = 2
  include_subtasks = false
  opt_fields       = name
```

The defaults are not cheap — `include_subtasks` is on, `comment_limit` is 10, and the
description, custom fields, followers and dependencies come along unless `opt_fields`
narrows them. This call returns no system stories, so it cannot answer "did this
change lane".

One `get_task` has been seen to hang for 400s and return nothing at all. Re-issuing
the same call worked, and so did looking the task up through `search_tasks` instead.
A stalled call is a transient, not a signal about the task — retry it once before
giving up on the row, and do not abandon the run over it.

### resource_subtype values worth acting on

| Subtype                     | Meaning                                                  |
|-----------------------------|----------------------------------------------------------|
| `comment_added`             | Real discussion — the substance of the digest             |
| `section_changed`           | Lane move. `text` names the project; ignore other boards  |
| `assigned` / `unassigned`   | Ownership handoff — worth a line                          |
| `attachment_added`          | Usually a PR link; keep the PR number                     |
| `marked_complete`           | Task closed inside the window                             |
| `enum_custom_field_changed` | Field edit. Substantive only if it is a real status move   |
| `story_reaction_added`      | Emoji. Never substantive                                  |
| `mentioned`                 | Someone linked this task elsewhere. Not substantive alone  |
| `unknown` (no text)         | Field-change side effects. Ignore                          |

## Telling a real update from a bulk sweep

Boards get periodic housekeeping passes: one person edits `スプリント`, `案件進捗`,
`案件種別` across dozens of tasks. Every one of those tasks surfaces in pass 1, and
counting them as updates buries the handful that actually moved.

Spot the cluster before reading any stories. Pass 1 already returned every task's
`modified_at`, and a sweep leaves dozens of them within the same minute or two. Take
one task from such a cluster, read its stories, and if they are all
`*_custom_field_changed` by a single author with no comment, treat the rest of the
cluster the same way instead of reading each one. That turns dozens of story walks
into one, and it is the difference between a cheap run and an expensive one on the
day after a tidy-up.

A sprint field moving from one week to the next is a schedule slip, not progress —
also 参考, though it is worth a sentence when a task has slipped several sprints in a
row.

## modified_at moved but there are no stories

Board reordering and subtask edits bump `modified_at` without writing a story. If a
task appears in pass 1 and has nothing at or after the cutoff, it is not an update —
bucket it by whatever its last real activity was and leave it out of 更新あり.

Where a parent's timestamp moved because a subtask changed, the interesting content
is in the subtask.

## Call budget

Fixed per run: `get_project` ×1, `search_tasks` ×1, `get_tasks` ×(classified lanes).

Everything else scales, and two terms dominate:

- `get_task_stories` over the changed set — priced in **pages**, not tasks, since an
  old ticket takes several. The two-phase walk and the sweep-cluster shortcut above
  are what keep this from running away.
- `get_task` for wait-reason relief — one per wait-lane task at 5+ business days.
  Tier C tasks are explicitly excluded from this, and that exclusion is most of the
  saving, since a healthy board keeps the bulk of its wait lanes under five days.

On a quiet day the whole run is a handful of calls; after a long weekend, or the day
after a housekeeping sweep, the changed set can be dozens of tasks. Say so up front
and work through it in batches rather than starting a fan-out that cannot finish.
