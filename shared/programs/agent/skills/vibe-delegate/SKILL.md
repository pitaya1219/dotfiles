---
name: vibe-delegate
description: Delegate a coding task (e.g. a Gitea issue) to Mistral Vibe via `vibe -p`, then independently verify the result and open a PR. Orchestrator-side skill. Invoked ONLY on explicit user request (e.g. `/vibe-delegate`); never auto-triggered by the agent.
user-invocable: true
autonomous: false
version: 1.2.0
---

# Vibe Delegate

Delegate an implementation task to **Mistral Vibe** (`vibe -p` programmatic mode) as a worker, while *you* (the orchestrator) keep ownership of isolation, verification, and PR creation.

This is the inverse of an enforcement rule: it is a **procedure you run**, so a skill is the right vehicle. The hard-won invariant is **step 4: never trust Vibe's self-report — verify independently.**

## When to use

- The user asks to delegate an issue/task to Vibe (e.g. "vibe-delegate #21", "have Vibe implement X").
- Good for: self-contained, verifiable coding tasks on a repo you can clone (branch → implement → test → push).

## Inputs

```
vibe-delegate <issue#|task-description> [--repo <owner/name>] [--max-price 20] [--max-turns 200]
```

- Default budget is generous because Mistral runs on a subscription (per-task cost is not the concern). Bound runaway with `--max-turns`, not a tight price. `--max-price` is only a safety stop.

## Isolation model (important)

Isolation is handled **by you**, not by Vibe: you clone the target repo into a dedicated sub-agent worktree and point Vibe at it. Vibe is invoked as a delegated **sub-agent** (the worker); you stay the orchestrator.

- **The agent-sessions workspace matters — keep work there when you are inside it.** Place the worktree under `<agent-sessions>/vibe-subagents/session-<slug>`. **Exception:** if you are NOT inside `~/agent-sessions`, fall back to `~/vibe-subagents/session-<slug>`. (See step 2.)
- **Do NOT propagate the agent-sessions `session-<id>` initialization ritual to Vibe** — that is specific to the agent-sessions workspace and is meaningless inside a project clone. Vibe gets **task-scoped rules only** (branch, clean commits, push-not-merge, verify). The dedicated worktree *is* the isolation.

## Steps

### 1. Resolve the task

If given an issue number, fetch its body (Gitea MCP `issue_read` / `get`) and use it as the spec. Otherwise use the provided description.

### 2. Fresh, isolated sub-agent worktree

Pick the worktree base by location, then clone. Do NOT hardcode a Gitea host — take the repo's clone URL from the issue/context (or `git remote get-url origin` of an existing checkout).

```bash
REPO_URL="<clone url of the target repo>"   # whatever Gitea host the repo lives on
SLUG="<short-task-slug>"                      # e.g. issue-21, lib-bin-split

# agent-sessions is the primary workspace: keep work there when we're inside it.
case "$PWD/" in
  "$HOME/agent-sessions/"*) BASE="$HOME/agent-sessions/vibe-subagents" ;;   # keep inside the workspace
  *)                        BASE="$HOME/vibe-subagents" ;;                   # exception: outside agent-sessions
esac

CLONE="$BASE/session-$SLUG"
rm -rf "$CLONE"
git clone "$REPO_URL" "$CLONE"
# ensure clean main
git -C "$CLONE" checkout main && git -C "$CLONE" reset --hard origin/main && git -C "$CLONE" clean -fd
```

### 3. Build the task prompt (embed project rules)

Write a self-contained prompt to `/tmp/vibe_task.md`. It MUST state:

- The clone path; "work entirely inside this directory; do NOT create session subdirectories."
- Create a feature branch (`feat/...`, `fix/...`, `chore/...`).
- **Commit messages: clean and professional. NEVER mention AI / Mistral / Vibe / Claude / Anthropic; NO `Co-Authored-By` line.**
- **Do NOT open a PR, do NOT merge. Only push the branch.**
- Verify: `cargo fmt --all`, `cargo build`, `cargo test`, `cargo clippy --all-targets -- -D warnings`. If `cargo` is not on PATH, prefix with `nix develop -c`.
- **On completion (after pushing), ALWAYS run the `session-save` skill** — this is mandatory, not optional. Pass `caller = claude` so the page gets a `called-by:: claude` property. If Logseq is unreachable (network/port error), `session-save` should fall back to writing a markdown file under `~/.agent/sessions/` rather than skipping silently.
- Final report: branch name, exact `cargo test` line, clippy result, files changed, any blocker. If a check fails and it cannot fix it, report verbatim and do NOT push broken code.

### 4. Launch Vibe (background) + INDEPENDENTLY VERIFY

```bash
cd "$CLONE"
vibe -p "$(cat /tmp/vibe_task.md)" \
  --workdir "$CLONE" --yolo --trust \
  --max-price "${MAX_PRICE:-20}" --max-turns "${MAX_TURNS:-200}" \
  --output text > /tmp/vibe_run.log 2>&1
```

Run it in the background; on completion **do your own verification — do not rely on Vibe's summary:**

```bash
cd "$CLONE"
grep -iE 'vibe_stop|price|limit' /tmp/vibe_run.log   # did it stop early (budget/turns)?
git status --short                                   # uncommitted leftovers?
git log --oneline -3 --pretty='%h %an %s'            # did it commit? author?
git ls-remote --heads origin <branch>                # did it push?
cargo test 2>&1 | grep 'test result'                 # YOU run the tests
cargo clippy --all-targets -- -D warnings            # YOU run clippy
cargo fmt --all -- --check
```

**Known failure modes (from PoC):**
- Vibe's self-report is optimistic — it may claim success while leaving a broken file or uncommitted work.
- A too-low `--max-price` stops it **mid-task before it commits/verifies**, leaving WIP and possibly an unverified config bug (e.g. a malformed `clippy.toml`).
- If it stopped early or left broken/uncommitted work: either reset the clone and re-run with a higher budget, or finish/fix it yourself as the orchestrator (and say so in the report).

### 5. Open the PR as **mistral-bot** (orchestrator, after verification)

Only after your own independent checks pass. The PR must be attributed to **mistral-bot**, because the implementation is Vibe's work. Create it by calling the Gitea API with the Vibe bot token (`GITEA_VIBE_BOT_TOKEN`) — NOT the orchestrator's own MCP token:

```bash
# Derive the Gitea host + owner/repo from the clone's remote — never hardcode a server.
ORIGIN=$(git -C "$CLONE" remote get-url origin)                              # https://<host>/<owner>/<repo>.git
HOST=$(printf '%s' "$ORIGIN" | sed -E 's#^(https?://[^/]+).*#\1#')
REPO_SLUG=$(printf '%s' "$ORIGIN" | sed -E 's#^https?://[^/]+/(.+)\.git$#\1#')   # <owner>/<repo>

curl -fsS -X POST \
  -H "Authorization: token ${GITEA_VIBE_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg t '<title>' --arg b '<body incl. Closes #<issue>>' \
        --arg h '<branch>' '{head:$h, base:"main", title:$t, body:$b}')" \
  "$HOST/api/v1/repos/$REPO_SLUG/pulls"
```

**Push-not-merge** — never merge. Then post your independent-verification summary as a PR **comment** under your own (orchestrator) identity, so authorship (mistral-bot) and review (orchestrator) stay cleanly separated.

Alternative: let Vibe open the PR itself in step 3 (it has `create_pull_request` permission and authenticates as mistral-bot via `.vibe/gitea-mcp-wrapper.sh`). Simpler, but the PR is then opened on Vibe's *self-report* before your verification — so still verify and comment before any merge. Prefer the orchestrator-opens-after-verify flow above.

### 6. Cleanup

Remove the clone (`rm -rf "$CLONE"`) once the PR is up, unless asked to keep it.

## Notes

- Skills are shared between Claude and Vibe (`~/.claude/skills` and `~/.vibe/skills` both point at `~/.agent/skills`). This skill is intended for the orchestrator; Vibe is the worker.
- For tight, parallel, low-friction delegation with structured reporting, the Claude `Agent` tool (e.g. a Haiku subagent) is smoother. Use Vibe when you specifically want a different model / the mistral-bot identity / the separate system.
