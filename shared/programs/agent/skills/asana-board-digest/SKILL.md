---
name: asana-board-digest
description: Summarises an Asana kanban board into what actually moved since a cutoff, which tasks changed lane, and which active tasks have gone quiet, bucketed by business days and tiered by lane. Use when asked what has been happening on the Asana board, which tickets are stuck or stalled, or for a standup or weekly board review.
when_to_use: Trigger phrases include "Asanaの動き", "ボードの棚卸し", "止まっているタスク", "動きがないもの", "朝会用にまとめて", "what moved on the board", "what is stalled". Not for creating or editing a task — that is asana-create-task.
argument-hint: "[YYYY-MM-DD | Nd] [--html]"
user-invocable: true
version: 1.0.0
---

Produce a board digest for the Asana project configured in `~/.agent/asana.json`: what
moved, what changed lane, and what has gone quiet. Paths below (`references/`,
`assets/`) are relative to this skill's own directory.

`references/asana-queries.md` holds the MCP call recipes and the pitfalls that make
this expensive or wrong if ignored. **Read it before the first API call.**

Asana calls a board column a *section*; this skill calls a classified one a **lane**.

Track progress with this checklist — a busy board takes more than one context to get
through, so being able to see where the run stopped matters:

```
- [ ] Step 1: cutoff resolved, projectGid loaded
- [ ] Step 2: lanes classified, unclassified sections noted
- [ ] Step 3: pass 1 + pass 2 collected, stories read, notes written to scratch file
- [ ] Step 4: buckets and tiers assigned
- [ ] Step 5: report written
```

## Arguments

`$ARGUMENTS` sets the "updated" window: nothing for the previous business day, a
`YYYY-MM-DD` date, or `Nd` for N business days ago. Resolve it to the **cutoff** —
the instant everything below is measured against — with the script, which also
converts to the UTC that Asana's filters expect:

```bash
scripts/bizdays.py cutoff "$ARGUMENTS"   # e.g. 3d -> 2026-08-26T15:00:00Z
```

`--html` additionally writes the report as a standalone page for circulating to
people who do not have this conversation. Strip it from `$ARGUMENTS` before passing
the rest to the script.

## Step 1: Config

```bash
cat ~/.agent/asana.json
```

`projectGid` is required; stop with an error if the file or the key is missing.

Business days exclude Saturday and Sunday only. Japanese public holidays are **not**
modelled — if a run lands after a long weekend, say so in the report header.

## Step 2: Resolve the board's lanes

Fetch the project's sections once (`get_project` with `include_sections=true`) and
classify each by name. **work and wait are allowlists; every other section is
ignored** — a real board carries a long tail of archival sections that no
enumeration will keep up with.

| Class    | Matches                                      | Role in the digest                |
|----------|----------------------------------------------|-----------------------------------|
| **work** | `Doing`, `Code Review`                       | Someone is actively holding this  |
| **wait** | `Checking with`, `In develop`, `Waiting for` | Blocked on someone else by design |

Match a distinctive substring of the section name, case-insensitively and after
normalising width and punctuation — lane names carry inconsistent parens and dashes,
so a full-string comparison fails on names that are otherwise obviously the same lane.

Only work and wait lanes are scanned for staleness. `ToDo` is deliberately outside
both: a task sitting untouched in ToDo is the backlog working as intended, not a
signal. Tasks in ignored lanes still appear in 更新あり when they moved.

An allowlist cannot tell "nothing is stale there" apart from "never looked", so
**name every unclassified section in the report header**. A lane renamed past the
match strings then shows up as a line the reader can act on instead of quietly
dropping out of the scan.

## Step 3: Collect

Two passes, both described in detail in `references/asana-queries.md`. They do not
depend on each other, and neither do the per-lane inventory calls — issue them
together rather than one at a time.

1. **Changed since cutoff** — one `search_tasks` over the project filtered by
   `modified_at_after`.
2. **Board inventory** — one `get_tasks` per work/wait lane. This is the input to
   the staleness buckets. It must be `get_tasks(section=…)`, **not**
   `search_tasks(sections_any=…)`, which returns tasks from other lanes; the
   reference file shows the case that proves it.

The changed set is the **union** of the two: pass 1, plus every pass-2 task whose
`modified_at` is at or after the cutoff. Pass 1 has been measured dropping tasks it
matched, and pass 2 has already paid for the timestamps that catch them, so the union
costs nothing. It only covers the work and wait lanes, though — a task that moved in
an ignored lane still depends on pass 1 alone.

For every task in the changed set, read its stories and keep only those at or after the
cutoff. **Classify each task as substantive or not** — a bulk custom-field sweep is
not an update, and reporting it as one is the main way this digest goes stale-blind.
The reference has the rules, the cheap tells, and the way to spot a sweep from pass 1
alone so that most of its tasks never need a story read.

Resolve the lane in this order: the pass-2 inventory that returned the task, then the
pass-1 `memberships` entry for the configured project, then レーン未設定. Pass 2 is
authoritative because `memberships` comes back empty for some tasks; the fallback
exists because pass 2 only covers work and wait lanes.

Record per task: gid, name, `permalink_url`, lane, assignee, `modified_at`, whether it
closed, whether it moved lane (and from → to), and a one-to-three line summary of what
happened.

## Step 4: Bucket and tier

Count the business days with the script rather than by hand, once per task:

```bash
scripts/bizdays.py elapsed 2026-08-28T02:55:29.078Z   # -> 2
```

Staleness is business days since the last update, and the rule that matters is that
**a non-substantive change never resets the clock**. Inside the changed set you can
enforce that, because you read the stories: a task whose only activity in the window
was a bulk sweep is bucketed by its previous substantive update, not by today.

Outside the changed set you only have `modified_at`, which also moves for board
reordering and subtask edits, so the clock there is an approximation that reads
*fresher* than reality. It fails in one direction and one situation: a board-wide
sweep just before the cutoff makes everything look recently touched and empties the
report. When a lane's tasks share a suspiciously uniform `modified_at`, read one of
them to find out, and say in the header that pre-cutoff timestamps are unverified.

| 停滞（営業日） | work lane | wait lane |
|----------------|-----------|-----------|
| 0 (更新あり)   | —         | —         |
| 1–2            | Tier C    | Tier C    |
| 3–4            | Tier B    | Tier C    |
| 5–19           | Tier A    | Tier B    |
| 20+            | 長期滞留  | 長期滞留  |

- **Tier A — 要対応**: nobody is moving it and nobody is waiting on anyone
- **Tier B — 要確認**: worth raising at the next standup
- **Tier C — 様子見**: consistent with how the lane normally behaves
- **長期滞留**: not a tier at all — see below

The wait column is the same ladder one step gentler, because five quiet days in
`Waiting for Production Deploy` mean something very different from five quiet days in
`Doing`.

**長期滞留** leaves the ladder above it, in both lane classes. Past about a month a
task has stopped being something anyone forgot about and become part of the board's
furniture, and a board that keeps a dozen of them fills Tier A with items nobody was
ever going to act on this morning — which is how the one genuinely stuck ticket gets
buried. These belong to a periodic clear-out, not to a standup, so the report gives
them a section that carries counts and the worst offender per lane rather than a row
each. They are also exempt from the comment reads below: nothing a month-old comment
says will change where they land.

**Wait-reason relief** applies to the one cell where it can change anything — a wait
lane at 5–19 days, i.e. Tier B. Read that task's newest comments and look for an
explicit reason the wait is legitimate: a named blocker, another ticket, a scheduled
test or release date, a 回答待ち addressed to someone. If one is there, drop the task
to Tier C and quote the reason. If the lane says "waiting" but no comment says what
for, leave it at Tier B — an unexplained wait is exactly what this digest exists to
surface. Do not read comments for tasks already at Tier C; nothing you find there can
move them.

## Step 5: Output

Fill in `assets/report-template.md`. Rules that keep it readable:

- Group 更新あり by the task's **current** lane, in the board's own section order, and
  note a move as `旧 → 現` on the task's own line rather than in a section of its own. The reader has the board in
  front of them, so the useful question is what is sitting in each column now — not
  what kind of event put it there.
- Order the stale sections by tier (A → B → C), not by lane.
- One line per task in the stale tables; the summary prose belongs in 更新あり. The
  stale tables carry the last-modified date, which pass 2 already returned — do not
  spend story reads to narrate a task that is in the report precisely because nothing
  happened to it.
- Name the assignee on every row — "誰が持っているか" is the first question asked.
- Where a task carries a PR, ticket, or account number that identifies the work, keep
  it. Where a comment thread has a conclusion, report the conclusion, not the thread.
- 参考 gets **one line per cause, not per task**: a sweep that touched forty tasks is
  one line naming the field, the count, and an example.
- 長期滞留 gets **one line per lane**: the count, the assignees behind it, and the
  longest-running example. Never a row per task — the point of the section is that
  these are not read individually.
- Keep 更新あり, the three tier headings, and 長期滞留 even at zero — their counts are how the
  reader tells "nothing was stuck" from "the digest never looked". The lane groups
  inside 更新あり are the opposite: list only the lanes that have something, since an
  empty column is the board's normal state and not a finding. Drop 参考 when it holds
  nothing.

Print the report to the conversation, and save it to a file only if the user asks.

With `--html`, also fill in `assets/report-template.html` and write it to
`board-digest-<RUN_DATE>.html` in the working directory, then say where it landed. It
carries the same report as the markdown one and the same placeholder names; what it
adds is that **every task name links to its `permalink_url`**, because the audience for
a circulated page is people who will want to open the ticket rather than ask you to.
The template ships its own stylesheet — fill it in rather than restyling per run, so a
reader who sees this page weekly recognises it. Keep the page self-contained: no CDN,
no external fonts.

The story reads in Step 3 dominate the cost of a run; `references/asana-queries.md`
has the budget and how to keep it bounded.
