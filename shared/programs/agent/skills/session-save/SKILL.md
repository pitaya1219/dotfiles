---
name: session-save
description: Save current session summary to Logseq (if available) or as a local markdown file
user-invocable: true
version: 3.0.0
---

Create a comprehensive summary of the current session and save it.

## Step 0: Check Logseq Availability

```bash
if python3 "$HOME/.agent/skills/logseq-write/logseq_status.py"; then
  USE_LOGSEQ=true
else
  USE_LOGSEQ=false
fi
```

This delegates config resolution and the reachability probe to the same
script `logseq-write` uses — see `Skill(logseq-write)` for what it checks.
Exit 0/1 only; no output to parse.

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
upload the full session transcript to Nextcloud so the page can link to the
complete raw log. Best-effort: skip silently when there is no transcript.
(Agent-type branching already happened in `detect-session.sh`.)

The bundled `attach_transcript.py` handles this end-to-end: it compresses the
transcript with zstandard (`zstd`, provided globally via `shared/programs/bare.nix`
— jsonl logs are highly compressible) to `session-<uuid>.jsonl.zst`, uploads it to
Nextcloud via the same mechanism as `logseq-write`'s `--asset` (credentials from
passage, not `~/.agent/logseq.json`), and prints the markdown link. Decompress the
asset with `zstd -d` (or `zstdcat`) to read it.

```bash
RAW_TRANSCRIPT_REF=""
if [ "$USE_LOGSEQ" = true ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  RAW_TRANSCRIPT_REF=$(python3 "$HOME/.agent/skills/session-save/attach_transcript.py" \
    "$SESSION_ID" "$TRANSCRIPT_PATH")
fi
```

If `RAW_TRANSCRIPT_REF` is non-empty, pass it as the `raw-transcript` page property
in the Save step below. Re-running for the same `SESSION_ID` overwrites the asset,
keeping it in sync with the latest transcript.

## Save

### If Logseq is available (`USE_LOGSEQ=true`)

Create **one page per topic in `TOPICS`** (usually just one). For each topic, call
`logseq-write`'s bundled script directly (see `Skill(logseq-write)` for the full
option reference) with `--create-page`, using that topic's `slug` and `objective`,
piping its generated summary in via stdin. Across a multi-topic session:

- Keep `session-id`, `date`, `model`, and `raw-transcript` **identical** on every
  page (one session, one transcript asset shared by all pages).
- Set `objective`, `status`, and the page content **per topic**.
- In each page's **References** section, cross-link the sibling topic pages with
  `[[Session/<YYYY-MM-DD> <other-slug>]]` so the split session stays navigable.

Per-topic create-page invocation:

```bash
python3 "$HOME/.agent/skills/logseq-write/logseq_write.py" \
  "Session/<YYYY-MM-DD> <topic-slug>" --create-page --format markdown \
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
  --prop "raw-transcript=<RAW_TRANSCRIPT_REF-or-empty>" \
  <<'EOF'
<the topic's generated summary>
EOF
```

Omit any `--prop` whose value is empty entirely (don't pass `--prop key=`) — this
matches `logseq_write.py`'s own validation and keeps empty properties out of the
page. If the script exits non-zero, its stderr has the reason (bad config, HTTP
failure, etc.); surface it rather than retrying blindly.

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
- `<RAW_TRANSCRIPT_REF>`: the value computed in "Attach Raw Transcript as a Logseq Asset" (e.g. `[session.jsonl.zst](../assets/session-<uuid>.jsonl.zst)`). Omit the property entirely when empty (asset was not attached).

The generated summary (without a top-level `#` heading — the page title serves that role) is the content to write.

### If Logseq is unavailable (`USE_LOGSEQ=false`)

Write **one file per topic** in `TOPICS` (usually one):

- Single topic, and `$ARGUMENTS` is provided: use it as the output path directly.
- Otherwise, per topic: `.ai/sessions/YYYY-MM-DD-${SESSION_ID}-<topic-slug>.md`
  - Fallback (no SESSION_ID): `.ai/sessions/YYYY-MM-DD-HHmmss-<topic-slug>.md`
- When splitting, cross-reference sibling files by relative filename at the top of each.

Create parent directories if needed, then write each topic's generated summary to its path.
