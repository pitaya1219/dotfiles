---
name: code-flow-html
description: Build a local HTML page that animates one code path at a time — pick a scenario, watch the route light up. For reading branchy control flow by hand, not for publishing.
user-invocable: true
version: 1.0.0
---

# Code Flow HTML Skill

## What This Skill Does

Turns a branchy function into a single local HTML file where each scenario
lights up its own path through the flow. Opened with `open`, never served and
never published.

The skill ships **the shell only**: CSS tokens, light/dark handling, the
node/stage layout, and the path-highlight JS — all of it in `template.html`,
runnable as-is with three dummy scenarios.

**What to draw is domain-specific and is deliberately not templated.** Deciding
which scenarios exist, which nodes each one passes through, and what stays
static is the actual work, and it comes from reading the code. Templating that
part would make this skill indistinguishable from asking for "a diagram in
HTML".

## Relationship to `artifact-diagramming`

`artifact-diagramming` (Anthropic-provided) is guidance and ships no template.
This skill ships the shell and adds the rules specific to animated control flow.
The two are complementary, not alternatives — read that one first.

- **Deciding what goes in the drawing is its subject, and it applies here too**:
  depict the mechanism rather than its name, label every arrow with the actual
  relationship, match the complexity to what the question turns on.
- **The static sections of this template are squarely its territory.** The
  overview and state-transition SVGs are hand-authored inline SVG and follow its
  mechanics.
- **What this skill adds** is the shell, the four-colour node vocabulary, and
  the discipline a diagram *of code* needs: one path per scenario, the commit
  stamp, the regeneration command.

Where they diverge is the output, and the divergence is a hard one:

| | this skill | `artifact-diagramming` |
|---|---|---|
| Output | local HTML file, opened with `open` | Artifact published on claude.ai |
| Reader | you, while reading the code | someone else, later |
| Interaction | scenario switching drives the page | none — it forbids `<script>` in the figure |

A published Artifact has to be self-contained and static, which the scenario
animation cannot be. So do not publish the output of this skill as an Artifact;
it is a working tool with a commit hash stamped on it, not a document. The pages
also quote source code and internal identifiers, so they stay on the machine that
made them.

## Design rules

These came out of repeated use and are the substance of the skill. Do not relax
them to fit an awkward flow — reshape the flow instead.

- **Animate branches only.** Anything that needs to be scanned at a glance — a
  state machine, a method/operation table, a legend — stays a static SVG or a
  plain table. Motion helps when the question is "which way does it go"; it
  hurts when the question is "what are all the values".
- **Node colors are fixed at four kinds**: plain (pure computation or a
  decision), `io` (external I/O), `term` (path ends here), `bad` (error path).
  A fifth color makes the page unreadable. If a node does not fit, the node is
  doing too much — split it.
- **One scenario = one path.** Never fork inside the drawing. A branch is
  expressed by switching scenarios, not by drawing both legs. Drawing every leg
  produces crossing lines and nothing is legible.
- **Always name the target commit, in both the header and the footer.** A
  diagram of code goes stale silently. A short hash (e.g. `856d88d`) plus the
  file paths lets the next reader tell at once whether it still describes
  reality.
- **Record how to regenerate it.** Put the commands used to extract the call
  relationships into the footer, e.g.
  `grep -n "def \|self\._repo\.\|self\._logger\." path/to/module.py`.
  Without them, updating the page means re-reading the source from zero.
- **Honor `prefers-reduced-motion`.** The template's `reduce` check collapses
  the step delay to 0 so the whole path resolves instantly rather than
  animating. Keep it.

## Procedure

1. **Fix the target.** Resolve the commit (`git rev-parse --short HEAD`) and the
   files in scope. Everything below describes that commit and nothing else.
2. **Extract the call relationships.** Read the entry function, then follow it.
   A `grep -n` over definitions and the collaborators the class holds is usually
   enough to get the skeleton; keep whatever command worked, it goes in the
   footer.
3. **Decide what does *not* animate.** Lifecycles, state transitions, and
   lookup tables go into the static section. Only the decision tree animates.
4. **Lay out stages.** A stage is one step in time, top to bottom; the nodes in
   a stage are the alternatives at that step. Give each stage a `data-s` and
   each node an `id` starting with `n-`.
5. **Write the scenarios.** One per distinct outcome, plus the error paths worth
   showing. See `reference.md` for the field-by-field conventions and the
   `path` / `stages` correspondence.
6. **Fill the header and footer** with the commit, the paths, and the
   regeneration command.
7. **Verify** (below), then `open` it.

Copy the template into the working directory rather than editing it in place:

```bash
cp ~/.agent/skills/code-flow-html/template.html ./<subject>-flow.html
```

Every spot needing domain content is marked `REPLACE` (or `OPTIONAL`) in an HTML
comment. Remove those comments once filled.

## Verification

Before handing the file over:

```bash
# Every id referenced from SCENARIOS.path must exist in the markup.
python3 -c "import re; h=open('<subject>-flow.html').read(); ids=set(re.findall(r'id=\"(n-[a-z-]+)\"',h)); used=set(re.findall(r'\"(n-[a-z-]+)\"',h))-ids; print(sorted(used-ids))"
```

An empty list is the pass condition — anything printed is a `path` entry with no
node behind it, which silently fails to light up.

Then `open` the file and confirm by eye:

- switching scenarios lights the nodes in order and dims the ones off the path
- 「もう一度」 replays, 「全体表示に戻す」 clears back to the full view
- both light and dark are readable — toggle the macOS system setting, or apply
  `data-theme="dark"` / `data-theme="light"` to `<html>` by hand
- every scenario's `stages` covers exactly the stages its `path` touches

## Files

- `template.html` — the shell. Runs as-is with three dummy scenarios.
- `reference.md` — `SCENARIOS` field conventions, `path` / `stages`
  correspondence, and the node-class decision table.
