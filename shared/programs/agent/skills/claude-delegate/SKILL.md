---
name: claude-delegate
description: Delegate a coding task (e.g. a Gitea issue) to a Claude subagent (Haiku or Sonnet), then independently verify the result and open a PR. Orchestrator-side skill. Invoked ONLY on explicit user request (e.g. `/claude-delegate`); never auto-triggered by the agent.
user-invocable: true
autonomous: false
version: 1.0.0
---

# Claude Delegate

Delegate an implementation task to a **Claude subagent** (Haiku or Sonnet) as a worker, while *you* (the orchestrator) keep ownership of isolation, verification, and PR creation.

The hard-won invariant is **step 5: never trust the subagent's self-report — verify independently.**

## When to use

- The user asks to delegate an issue/task to a Claude subagent (e.g. "claude-delegate #21", "have Claude Haiku implement X").
- Good for: self-contained, verifiable coding tasks on a repo you can clone (branch → implement → test → push).
- Prefer this over `vibe-delegate` when you want a Claude-family model, structured output, or tighter orchestrator integration.

## Inputs

```
claude-delegate <issue#|task-description> [--repo <owner/name>] [--model haiku|sonnet]
```

- `--model haiku`: Force Claude Haiku (fast, cheap; good for focused, well-specified tasks).
- `--model sonnet`: Force Claude Sonnet (capable; good for complex, multi-file, or underspecified tasks).
- Omit `--model` to let the orchestrator decide (see **Model selection** below).

## Model selection

When `--model` is not specified, assess task complexity and choose:

| Choose **Haiku** when | Choose **Sonnet** when |
|---|---|
| Task touches 1–2 files | Task spans multiple files or packages |
| Spec is concrete and complete | Spec requires judgment or design decisions |
| Change is additive / mechanical (add field, rename, small fix) | Change involves architecture, refactoring, or debugging complex logic |
| Expected diff < ~100 lines | Expected diff > ~100 lines or scope is unclear |
| Tests are already written or trivially added | New test suites or integration work needed |

State your model choice and brief rationale to the user before proceeding.

## Isolation model

Isolation is handled **by you**, not by the subagent: you clone the target repo into a dedicated worktree and spawn the subagent with that path as its workspace. The subagent is the worker; you are the orchestrator.

- Keep the worktree under `<agent-sessions>/claude-subagents/session-<slug>` when inside `~/agent-sessions`.
- **Exception:** if you are NOT inside `~/agent-sessions`, fall back to `~/claude-subagents/session-<slug>`.
- **Do NOT propagate the agent-sessions `session-<id>` initialization ritual** to the subagent — that is specific to the orchestrator workspace. The dedicated worktree *is* the isolation.

## Steps

### 1. Resolve the task

If given an issue number, fetch its body (Gitea MCP `issue_read`) and use it as the spec. Otherwise use the provided description.

### 2. Choose the model

If `--model` was given, use it. Otherwise, apply the heuristics above and state your choice.

### 3. Fresh, isolated worktree

Do NOT hardcode a Gitea host — take the repo's clone URL from the issue/context or `git remote get-url origin`.

```bash
REPO_URL="<clone url of the target repo>"
SLUG="<short-task-slug>"   # e.g. issue-21, add-timeout-field

case "$PWD/" in
  "$HOME/agent-sessions/"*) BASE="$HOME/agent-sessions/claude-subagents" ;;
  *)                        BASE="$HOME/claude-subagents" ;;
esac

CLONE="$BASE/session-$SLUG"
rm -rf "$CLONE"
git clone "$REPO_URL" "$CLONE"
git -C "$CLONE" checkout main && git -C "$CLONE" reset --hard origin/main && git -C "$CLONE" clean -fd
```

### 4. Build the task prompt

Write a self-contained prompt for the subagent. It MUST state:

- The exact clone path; "work entirely inside this directory; do NOT create session subdirectories."
- Create a feature branch (`feat/...`, `fix/...`, `chore/...`).
- **Commit messages: clean and professional. NEVER mention AI / Claude / Anthropic / Haiku / Sonnet; NO `Co-Authored-By` line.**
- **Do NOT open a PR, do NOT merge. Only push the branch.**
- Run verification checks appropriate to the project (e.g. `cargo fmt --all`, `cargo build`, `cargo test`, `cargo clippy --all-targets -- -D warnings`; prefix with `nix develop -c` if cargo is not on PATH).
- Final report: branch name, exact test output line, lint result, files changed, any blocker. If a check fails and it cannot fix it, report verbatim and do NOT push broken code.

### 5. Spawn the subagent

Use the `Agent` tool with the chosen model override and `isolation: "worktree"` is NOT needed here — you already prepared the clone manually. Pass the task prompt directly:

```
Agent({
  description: "claude-delegate worker: <task slug>",
  model: "<haiku|sonnet>",
  prompt: "<full task prompt referencing CLONE path>"
})
```

Wait for the subagent to complete. Its return value is a text report — treat it as a self-report (possibly optimistic) and verify independently in the next step.

### 6. Independent verification (critical — do not skip)

Do NOT trust the subagent's self-report. Run checks yourself:

```bash
# Did it commit anything?
git -C "$CLONE" log --oneline -5 --pretty='%h %an %s'

# Did it push the branch?
git -C "$CLONE" ls-remote --heads origin

# Any uncommitted leftovers?
git -C "$CLONE" status --short

# Run tests yourself
cd "$CLONE" && cargo test 2>&1 | grep 'test result'          # or: nix develop -c cargo test
cd "$CLONE" && cargo clippy --all-targets -- -D warnings
cd "$CLONE" && cargo fmt --all -- --check
```

**Known failure modes:**
- Subagent's self-report is optimistic — may claim success while leaving uncommitted work or a broken build.
- If tests fail or the branch was not pushed: either finish/fix it yourself as the orchestrator, or re-delegate with a corrected prompt, and say so in your report.

### 7. Open the PR (after verification passes)

Use the Gitea MCP `pull_request_write` or the REST API under your orchestrator identity:

```bash
ORIGIN=$(git -C "$CLONE" remote get-url origin)
HOST=$(printf '%s' "$ORIGIN" | sed -E 's#^(https?://[^/]+).*#\1#')
REPO_SLUG=$(printf '%s' "$ORIGIN" | sed -E 's#^https?://[^/]+/(.+)\.git$#\1#')
BRANCH=$(git -C "$CLONE" rev-parse --abbrev-ref HEAD)

curl -fsS -X POST \
  -H "Authorization: token ${GITEA_CLAUDE_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg t '<title>' --arg b '<body incl. Closes #<issue>>' \
        --arg h "$BRANCH" '{head:$h, base:"main", title:$t, body:$b}')" \
  "$HOST/api/v1/repos/$REPO_SLUG/pulls"
```

**Push-not-merge** — never merge. Post your independent verification summary as a PR comment so the review trail is clear.

### 8. Cleanup

Remove the clone (`rm -rf "$CLONE"`) once the PR is up, unless the user asks to keep it.

## Notes

- Model override in the `Agent` tool call maps to: `haiku` → `claude-haiku-4-5-20251001`, `sonnet` → `claude-sonnet-4-6`.
- For the common case where you are already the orchestrator running as Sonnet and the task is simple, Haiku is a good default — it is 10–20× cheaper and fast enough for focused, well-scoped tasks.
- This skill complements `vibe-delegate`: use `vibe-delegate` when you specifically want the Mistral model or the `mistral-bot` git identity; use `claude-delegate` when you want a Claude-family model or tighter integration with Claude's tool ecosystem.
