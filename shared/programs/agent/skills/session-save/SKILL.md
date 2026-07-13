---
name: session-save
description: Save current session summary to Logseq (if available) or as a local markdown file
user-invocable: true
version: 2.7.0
---

Create a comprehensive summary of the current session and save it.

## Step 0: Check Logseq Availability

```bash
USE_LOGSEQ=false
_CFG="$HOME/.agent/logseq.json"
if [ -f "$_CFG" ]; then
  resolve_val() {
    local KEY="$1"
    local TYPE=$(jq -r "$KEY | type" "$_CFG")
    case "$TYPE" in
      string) jq -r "$KEY" "$_CFG" ;;
      object)
        case "$(jq -r "$KEY | keys[0]" "$_CFG")" in
          file)    cat "$(jq -r "$KEY.file" "$_CFG" | sed "s|~|$HOME|")" 2>/dev/null ;;
          command) eval "$(jq -r "$KEY.command" "$_CFG")" 2>/dev/null ;;
        esac ;;
    esac
  }
  _URL=$(resolve_val '.url')
  _TOK=$(resolve_val '.token')
  if curl -sf --max-time 3 \
       -H "Authorization: Bearer $_TOK" \
       -H "Content-Type: application/json" \
       -d '{"method":"logseq.App.getUserConfigs","args":[]}' \
       "$_URL/api" > /dev/null 2>&1; then
    USE_LOGSEQ=true
  fi
fi
```

## Session ID Detection

Source the bundled adapter, which resolves the current session's identity and
transcript across agent types (Claude Code, Vibe). All agent-specific branching
lives in that script, so this skill stays orchestration-only.

```bash
source "$HOME/.agent/skills/session-save/detect-session.sh"
# Sets, best-effort (empty when undetected):
#   AGENT_TYPE       claude-code | vibe | unknown
#   SESSION_ID       session UUID (or trailing hash for Vibe fallback)
#   WORKDIR_ENCODED  $(pwd) with '/' → '-'
#   TRANSCRIPT_PATH  absolute path to the full raw transcript (.jsonl)
```

`~/.claude/skills` and `~/.vibe/skills` both point at `~/.agent/skills`, so the
`~/.agent/...` path resolves regardless of which agent runs this skill.

## Identify Topics (split decision)

Before summarizing, decide whether the session covered **one** coherent topic or
**several distinct** ones, and split into one Logseq page per topic accordingly.

- **Default to a single page.** Most sessions are one topic even when they wander.
- **Split only when the session clearly contains separate workstreams** that a
  reader would look up independently — different repos/deliverables, unrelated
  goals, or a hard pivot mid-session. Example from this skill's own history: an
  Asana spec write-up **and** an unrelated dotfiles skill refactor → two pages.
- **Do not over-split.** Sub-tasks of one goal, a fix plus its test, or
  investigation-then-implementation of the same feature stay on **one** page.
- Produce a list `TOPICS` of `{ slug, objective }`. One entry → one page (normal
  case); two or more → one page each. When unsure, prefer fewer pages.

All resulting pages belong to the same session, so they share `session-id` and the
same `raw-transcript` asset; only the per-topic content, `slug`, `objective`, and
`status` differ. See the Save step for cross-linking.

## Summary Template

Generate a summary **per topic in `TOPICS`** (one per page) using these sections:

1. **Overview** — What was done and why (2-4 sentences)
2. **What Was Done** — Actions taken (bullet points)
3. **Files Changed** — `git diff --stat` output; "No git repository" if not applicable
4. **Decisions Made** — Key decisions and their reasons. When a decision came from a
   design/architecture discussion (e.g. "why this layer and not that one", a
   trade-off the user asked about explicitly), keep the reasoning in full rather
   than compressing it to a one-line bullet — write it as it was explained
   (principles, examples, the test used to judge it), not just the conclusion.
   The conclusion without the reasoning isn't reusable next time a similar call
   comes up.
5. **Problems & Solutions** — Issues encountered and how they were resolved
6. **Learnings & Insights** — Key concepts explored, useful patterns or techniques
7. **Open Items** — Pending tasks and known issues
8. **Next Session** — Tasks for the next session (cold-start ready)
9. **References** — Relevant commands, URLs, and code snippets

Format: Use clear headings, bullet points, and code blocks where appropriate.
Tone: Technical but readable, focusing on "what" and "why" over "how". Exception:
substantial design-rationale explanations (section 4 above) should be preserved in
their explained depth, not trimmed to match this terse default.

## Attach Raw Transcript as a Logseq Asset (Logseq only)

When `USE_LOGSEQ=true` and `TRANSCRIPT_PATH` was resolved (by the adapter above),
copy the full session transcript into the Logseq graph's `assets/` directory so the
page can link to the complete raw log. Best-effort: skip silently when there is no
transcript. (Agent-type branching already happened in `detect-session.sh`.)

```bash
RAW_TRANSCRIPT_REF=""
if [ "$USE_LOGSEQ" = true ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Resolve the current graph's on-disk path, then its assets/ dir
  _GRAPH_PATH=$(curl -sf \
    -H "Authorization: Bearer $_TOK" -H "Content-Type: application/json" \
    -d '{"method":"logseq.App.getCurrentGraph","args":[]}' \
    "$_URL/api" | jq -r '.path // empty')
  if [ -n "$_GRAPH_PATH" ] && [ -d "$_GRAPH_PATH/assets" ]; then
    _ASSET_NAME="session-${SESSION_ID}.jsonl"
    cp "$TRANSCRIPT_PATH" "$_GRAPH_PATH/assets/$_ASSET_NAME"
    # Logseq asset links are graph-relative: ../assets/<name>
    RAW_TRANSCRIPT_REF="[session.jsonl](../assets/${_ASSET_NAME})"
  fi
fi
```

If `RAW_TRANSCRIPT_REF` is non-empty, pass it as the `raw-transcript` page property
in the Save step below. Re-running for the same `SESSION_ID` overwrites the asset,
keeping it in sync with the latest transcript.

## Save

### If Logseq is available (`USE_LOGSEQ=true`)

Create **one page per topic in `TOPICS`** (usually just one). For each topic invoke
`Skill(logseq-write)` with `--create-page`, using that topic's `slug` and `objective`
and its own generated summary. Across a multi-topic session:

- Keep `session-id`, `date`, `model`, and `raw-transcript` **identical** on every
  page (one session, one transcript asset shared by all pages).
- Set `objective`, `status`, and the page content **per topic**.
- In each page's **References** section, cross-link the sibling topic pages with
  `[[Session/<YYYY-MM-DD> <other-slug>]]` so the split session stays navigable.

Per-topic create-page invocation:

```
$ARGUMENTS: "Session/<YYYY-MM-DD> <topic-slug>" --create-page --format markdown \
  --prop "tags=#<agent-type>-session" \
  --prop "date=[[<YYYY-MM-DD>]]" \
  --prop "repository=<repo-name-or-empty>" \
  --prop "git-branch=<branch-name-or-empty>" \
  --prop "objective=<one-sentence-objective>" \
  --prop "session-id=<SESSION_ID>" \
  --prop "status=<wip-or-completed>" \
  --prop "model=<model-name>" \
  --prop "pr=<pr-url-or-empty>" \
  --prop "called-by=<caller-or-empty>" \
  --prop "raw-transcript=<RAW_TRANSCRIPT_REF-or-empty>"
```

Field values:
- `<topic-slug>`: the topic's concise kebab-case title (e.g. `session-save-logseq-integration`). For a single-topic session this is just the session's one-line summary.
- `<agent-type>`: use `$AGENT_TYPE` from the adapter (`claude-code`, `vibe`, or `unknown`); default `claude-code` when `unknown`
- `[[<YYYY-MM-DD>]]`: today's date as a Logseq journal page link (e.g. `[[2026-06-09]]`)
- `<repo-name>`: from `git remote get-url origin` if in a git repo, else omit
- `<branch-name>`: from `git branch --show-current` if in a git repo, else omit
- `<objective>`: the topic's `objective` from `TOPICS` (one sentence). For a single-topic session, the session goal.
- `<wip-or-completed>`: `wip` if the session still has unfinished work / Open Items to resume; `completed` only when everything is done. Default to `wip` when in doubt — the user looks up `status` to find sessions to resume.
- `<model-name>`: the Claude/AI model in use (e.g. `claude-sonnet-4-6`)
- `<pr-url>`: PR URL if one was created during the session, else omit
- `<caller>`: the orchestrator that delegated this session, when it was run as a sub-agent (e.g. `claude` when delegated via the `vibe-delegate` skill). Omit the property entirely for normal, directly-run sessions.
- `<RAW_TRANSCRIPT_REF>`: the value computed in "Attach Raw Transcript as a Logseq Asset" (e.g. `[session.jsonl](../assets/session-<uuid>.jsonl)`). Omit the property entirely when empty (asset was not attached).

The generated summary (without a top-level `#` heading — the page title serves that role) is the content to write.

### If Logseq is unavailable (`USE_LOGSEQ=false`)

Write **one file per topic** in `TOPICS` (usually one):

- Single topic, and `$ARGUMENTS` is provided: use it as the output path directly.
- Otherwise, per topic: `.ai/sessions/YYYY-MM-DD-${SESSION_ID}-<topic-slug>.md`
  - Fallback (no SESSION_ID): `.ai/sessions/YYYY-MM-DD-HHmmss-<topic-slug>.md`
- When splitting, cross-reference sibling files by relative filename at the top of each.

Create parent directories if needed, then write each topic's generated summary to its path.
