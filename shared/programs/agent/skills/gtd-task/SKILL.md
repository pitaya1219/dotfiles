---
name: gtd-task
description: Record a task (a TODO, a follow-up, work for another session) in the user's Logseq graph the way their GTD setup expects: the right template, priority, area, context, status and explanatory sub-blocks, written through logseq-write. Use when the user asks to put something on their task list, or to leave work for a later session.
user-invocable: true
version: 1.0.0
---

Write a task to the Logseq graph so that it is already organised and so that a
session that has never seen this conversation can pick it up.

The conventions live in the graph, not here. `Task Management Rules` is the
authority and the six GTD templates are real blocks in it. This skill says how
to read them and how to write a task; it does not copy them, because a copy
drifts. When something below disagrees with the graph, the graph is right.

## When to use it

- The user asks to record a TODO, a follow-up, or "something for the next session".
- Do **not** create tasks on your own: session summaries and meeting minutes
  deliberately do not turn their action items into tasks, because tasks show up
  among the user's own.
- This skill only **adds** a task. It cannot edit, complete or move an existing one.

## Steps

The helper commands are read-only and take from a few seconds to half a minute
(each opens one graph session). In this file, `gtd_graph.py <command>` means:

```bash
python3 "$HOME/.agent/skills/gtd-task/gtd_graph.py" <command>
```

1. **Check Logseq is reachable:** `python3 "$HOME/.agent/skills/logseq-write/logseq_write.py" --check`.
   If it is not, write the same markdown to
   `~/.agent/sessions/<YYYY-MM-DD>-logseq-todo-draft-<slug>.md` and tell the user
   it has not been recorded.
2. **Read what is valid now:** `gtd_graph.py choices` lists the statuses,
   priorities, areas, contexts and the `project` / `team` / `place` pages that
   exist. Read `gtd_graph.py rules` once if you are unsure what a value means.
3. **Pick a template** (below) and print its body: `gtd_graph.py template 'GTD'`.
   It comes out as markdown with the properties as `key:: value` lines.
4. **Fill it in and write it** with `logseq-write` into today's journal
   (page name `YYYY-MM-DD`, append mode, no `--create-page`):

   ```bash
   python3 "$HOME/.agent/skills/logseq-write/logseq_write.py" "2026-11-21" --format markdown <<'EOF'
   - [ ] Re-run the benchmark three times and see whether the hang still happens
     priority:: Medium
     area:: personal
     context:: @agent, @computer
     - background: what happened and why this is worth doing
     - steps: what to do, in order, with the commands
     - done when: how a later session knows it is finished
   EOF
   ```
5. **Tell the user** what was written, and say which properties you chose and
   why, so they can correct them.

## Which template

`gtd_graph.py templates` shows what each one sets.

| Template | Use it for |
|---|---|
| `GTD` | The default. Only a Task with status Backlog; you set everything else |
| `GTD<Learning>` | Something to read or study. Tags it `#Learning`, area personal |
| `GTD<Chore>` | A one-off chore that serves no project (paperwork, errands). Tags it `#Chore` |
| `GTD<KrakenPJ>` | Work in the KrakenPJ project. Sets area work, `@computer, @online`, project KrakenPJ |
| `GTD<SDI>` | Work in the `sdi-cms` project. Same, with the nine section blocks |
| `GTD<Minimum>` | A bare `{{content}}`. It was made for tools that write a task from one line, and its body carries **priority High** and **area family, personal**. Use it only when the user asks for it |

A template's body is a starting point: replace every `{{placeholder}}` and
example text, and change any default that does not fit. Do not take a project
template for a task that is not in that project.

## Properties

Chosen from `gtd_graph.py choices`; a value that is not listed becomes a new
choice, which nobody asked for.

| Property | How to choose |
|---|---|
| status | `Todo` when the task is fully specified and ready to be done. `Backlog` when it cannot be organised yet. `Waiting` when it waits on someone or something: put what in `waiting-for:: text`, and who in `with::`. `#Someday` (a tag, no status) for "not now, review weekly" |
| priority | `Urgent` today, `High` this week, `Medium` this month, `Low` when there is time. When unsure, `Medium` |
| area | `work`, `personal` or `family`, one or more. Learning and chores are not areas; they are the `#Learning` / `#Chore` tags |
| context | Where or how it can be done. **`@agent` when an agent session can do it**, which is the case for most of what you leave for a later session. Add `@computer` for work at a machine. Waiting on others is the Waiting status, not a context |
| project | Only a page that exists as a project (listed by `choices`), written `[[name]]`. Do not invent one |
| deadline, scheduled | `YYYY-MM-DD`. Only when the user gave a date |
| remind-on | `[[YYYY-MM-DD]]` links |

Not defined in the graph yet, although the rules page names them: `effort` and
`next-action`. Writing them would create new text properties, so leave them out
unless the user asks.

## Sub-blocks: write for the session that was not here

Whoever picks the task up has none of this conversation. The sub-blocks are
where the task is explained. Put, as separate blocks:

- **background**: what happened and why the task exists, with links to the
  session pages or PRs ([[...]] or URLs)
- **goal**: what should be true afterwards
- **conditions**: what must hold before starting, and what to check first
- **steps**: what to do, in order, with the real commands and paths (say which
  paths survive a reboot and which do not)
- **how to judge**: what each outcome means and what to do next
- **if it goes wrong**: what to look at, and the risks
- **done when**: the criterion that lets a later session close it, and where to record the result

Two shapes exist in this graph, and both are fine:

- **Labelled lines** directly under the task (`background: ...`, `steps: ...`),
  as above. Light, and right for most tasks on the plain `GTD` template.
- **Section headers with the detail one level down**, as `GTD<SDI>` has
  (`**目的 / Purpose**` and so on). Use it when the template has the sections;
  keep the headers and their emoji (🔴 🟡) as the template has them. The graph
  does not say what the emoji mean, so do not give them a meaning.

Keep each sub-block to one idea, and nest steps under `steps:` rather than
writing a long paragraph.

## Writing it

- `logseq-write` in `--format markdown`: `- [ ] title` is the task, `key:: value`
  lines indented under it are its properties, nested list items are its
  sub-blocks. Its `SKILL.md` has the full syntax and the accepted values.
- A bad status, priority or date stops the write before anything is written.
- Property names are matched to the graph's existing ones; a name that does not
  exist is **created**, so a typo adds a property. `choices` prints the names
  that exist.
- `#400` in text is escaped for you. A literal `key:: value` that is not meant
  as a property must not be indented directly under a list item.
- Do not put secrets or personal data in a task. The graph syncs to a server.

## Checking what was written

A task is the block with the `Task` tag. To read it back:

```bash
logseq-db query '[:find ?s ?p :where [?b :block/title ?t] [(clojure.string/starts-with? ?t "Re-run the benchmark")] [?b :logseq.property/status ?sv] [?sv :block/title ?s] [?b :logseq.property/priority ?pv] [?pv :block/title ?p]]'
```

Do not leave test blocks in the user's journal. If you try something, delete it
and read back that it is gone.
