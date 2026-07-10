---
name: session-save
description: Save current session summary to Logseq (if available) or as a local markdown file
user-invocable: true
version: 2.5.0
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

## Summary Template

Generate a session summary using these sections:

1. **Overview** — What was done and why (2-4 sentences)
2. **What Was Done** — Actions taken (bullet points)
3. **Files Changed** — `git diff --stat` output; "No git repository" if not applicable
4. **Decisions Made** — Key decisions and their reasons
5. **Problems & Solutions** — Issues encountered and how they were resolved
6. **Learnings & Insights** — Key concepts explored, useful patterns or techniques
7. **Open Items** — Pending tasks and known issues
8. **Next Session** — Tasks for the next session (cold-start ready)
9. **References** — Relevant commands, URLs, and code snippets

Format: Use clear headings, bullet points, and code blocks where appropriate.
Tone: Technical but readable, focusing on "what" and "why" over "how".

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

Invoke `Skill(logseq-write)` with `--create-page` to create a dedicated session page:

```
$ARGUMENTS: "Session/<YYYY-MM-DD> <oneline-summary>" --create-page --format markdown \
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
- `<oneline-summary>`: concise kebab-case title (e.g. `session-save-logseq-integration`)
- `<agent-type>`: use `$AGENT_TYPE` from the adapter (`claude-code`, `vibe`, or `unknown`); default `claude-code` when `unknown`
- `[[<YYYY-MM-DD>]]`: today's date as a Logseq journal page link (e.g. `[[2026-06-09]]`)
- `<repo-name>`: from `git remote get-url origin` if in a git repo, else omit
- `<branch-name>`: from `git branch --show-current` if in a git repo, else omit
- `<objective>`: one sentence summarizing the session goal, derived from the conversation
- `<wip-or-completed>`: `wip` if the session still has unfinished work / Open Items to resume; `completed` only when everything is done. Default to `wip` when in doubt — the user looks up `status` to find sessions to resume.
- `<model-name>`: the Claude/AI model in use (e.g. `claude-sonnet-4-6`)
- `<pr-url>`: PR URL if one was created during the session, else omit
- `<caller>`: the orchestrator that delegated this session, when it was run as a sub-agent (e.g. `claude` when delegated via the `vibe-delegate` skill). Omit the property entirely for normal, directly-run sessions.
- `<RAW_TRANSCRIPT_REF>`: the value computed in "Attach Raw Transcript as a Logseq Asset" (e.g. `[session.jsonl](../assets/session-<uuid>.jsonl)`). Omit the property entirely when empty (asset was not attached).

The generated summary (without a top-level `#` heading — the page title serves that role) is the content to write.

### If Logseq is unavailable (`USE_LOGSEQ=false`)

- If `$ARGUMENTS` is provided: use it as the output path directly
- Otherwise: `.ai/sessions/YYYY-MM-DD-${SESSION_ID}-${summary}.md`
  - Fallback (no SESSION_ID): `.ai/sessions/YYYY-MM-DD-HHmmss-${summary}.md`

Create parent directories if needed, then write the generated summary to the output path.
