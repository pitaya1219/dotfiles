---
name: vibe-delegate
description: Delegate a coding task (e.g. a Gitea issue) to a headless Mistral Vibe worker confined to its own clone, then independently verify the result and open a PR. Orchestrator-side skill, usable from Claude or from Vibe. Invoked ONLY on explicit user request (e.g. `/vibe-delegate`); never auto-triggered by the agent.
user-invocable: true
autonomous: false
version: 2.0.0
---

# Vibe Delegate

Delegate an implementation task to a **headless Mistral Vibe worker** while *you* (the orchestrator) keep ownership of isolation, verification, and PR creation. The orchestrator can be Claude or Vibe itself; nothing below depends on which.

The hard-won invariant is **step 5: never trust the worker's self-report — verify independently.**

## When to use

- The user asks to delegate an issue/task to Vibe (e.g. "vibe-delegate #21", "have Vibe implement X").
- Good for: self-contained, verifiable coding tasks on a repo you can clone (branch → implement → test → push).

## Inputs

```
vibe-delegate <issue#|task-description> [--repo <owner/name>] [--max-price 20] [--max-turns 200]
```

Mistral runs on a subscription, so the default budget is generous. Bound runaway with `--max-turns` and `--time-limit`; `--max-price` is only a safety stop.

## How the worker is confined

Never call `vibe -p` yourself. Start the worker through the workspace launcher, `~/agent-sessions/.agent/bin/vibe_subagent.py`:

- The clone lives at `<your session dir>/vibe-subagents/<slug>/`. The launcher confines the worker to **exactly that directory** (plus `/tmp` and `~/.agent/sessions`) and fails closed: a bad setup, unparseable hook input or a write without a path is denied. Inside the clone, `.vibe/`, `.git/hooks` and `.git/config` are read-only for the worker.
- Vibe reads project hooks and prompts only from `<workdir>/.vibe/`. A bare `vibe -p` in a clone therefore runs with **no boundary at all** and can die at startup on the workspace's system prompt. The launcher generates a git-excluded `.vibe/` with the `subagent-rules` prompt and the boundary hooks.
- The worker's environment lacks the PR token (`GITEA_VIBE_BOT_TOKEN`) and the parent harness's markers. You open the PR, not the worker.
- Success is read from `export.json`, not from the exit code.
- A repository that tracks files under `.vibe/` (the agent-sessions repo itself) is refused.

Check `test -f ~/agent-sessions/.agent/bin/vibe_subagent.py` first; if it is missing, the workspace checkout is older than the launcher and needs a `git pull` by the user.

## Steps

### 1. Resolve the task

If given an issue number, fetch its body (Gitea MCP `issue_read`, or the REST API) and use it as the spec. Otherwise use the description.

Before writing a spec that depends on the shape of an external response (an API, a config, a log format), look at a real one. A wrong assumption in the spec becomes a plausible, tested, wrong implementation.

### 2. Fresh clone inside your session directory

Your session directory is the `session-<id>` directory announced at session start; do not derive it.

```bash
SESSION_DIR="$HOME/agent-sessions/session-<your id>"
PARENT_ID="${SESSION_DIR##*/session-}"
SLUG="<short-unique-slug>"                 # e.g. issue-21-a; a retry gets a new slug
CLONE="$SESSION_DIR/vibe-subagents/$SLUG"

mkdir -p "$SESSION_DIR/vibe-subagents"
git clone "<clone url of the target repo>" "$CLONE"
git -C "$CLONE" checkout main && git -C "$CLONE" reset --hard origin/main
```

Take the clone URL from the issue/context or `git remote get-url origin` of an existing checkout; do not hardcode a host. Use a fresh slug instead of deleting an old clone: Claude's shell refuses `rm -rf` on directories inside the workspace.

### 3. Write the task prompt

Write it to a file in your scratchpad or session directory with the editor tool, not a shell heredoc (the secret guard can reject a command that merely mentions a secrets file or `passage`, even in prose). The launcher's `subagent-rules` prompt already tells the worker to stay in the clone, use Conventional Commits without any AI mention, push but never open or merge a PR, and keep out of ADRs and config files. The task prompt only needs what is specific:

- The clone path ("work entirely inside this directory") and the feature branch name (`feat/...`, `fix/...`).
- Background, the files involved (absolute paths), the deliverable, how to choose when the spec is open, and what to leave alone.
- The verification commands the project uses (read its `CLAUDE.md`/tooling), and "report the real output".
- **On completion, ALWAYS run the `session-save` skill**, passing `caller = <claude or vibe: what you are>`. If Logseq is unreachable it falls back to a markdown file under `~/.agent/sessions/`.

### 4. Launch and read the outcome

```bash
python3 ~/agent-sessions/.agent/bin/vibe_subagent.py \
  --clone "$CLONE" --parent-session "$PARENT_ID" \
  --prompt-file "$PROMPT" --output-dir "$OUT" \
  --max-turns 200 --max-price 20 --time-limit 3600
```

It runs in the foreground until the worker stops and prints one line: `outcome=… stop_reason=… turns=… cost=…`. Exit 0 means `outcome=finished`, nothing else. If your harness can run commands in the background and notify you (Claude), do that; otherwise wait for it (the time limit bounds it). Use absolute paths in redirections: the boundary hook cannot resolve shell variables there.

`--dry-run` shows what would be written and run without launching.

### 5. Independently verify

```bash
cd "$CLONE"
tail -30 "$OUT/vibe.log"                # what it says, and any startup error
git status --short                      # uncommitted leftovers?
git log --format='%h %an %s' main..HEAD # did it commit?
git ls-remote --heads origin <branch>   # did it push?
git diff --stat main...HEAD             # only the files the task names?
# YOU run the project's verification suite; for security-sensitive code, read the diff.
```

**Known failure modes**
- The self-report is optimistic: it may claim success with a broken or uncommitted tree.
- `outcome=price_limit` (or another limit) stops it **mid-task**, typically with everything uncommitted. Inspect the clone, then either re-run with a higher budget on a new slug, or finish and fix it yourself, and say so in the PR.
- It may touch files outside the task (an accepted ADR, a docs line). Revert those.
- It implements the spec faithfully, including the spec's mistakes.

### 6. Open the PR (orchestrator, after verification)

```bash
ORIGIN=$(git -C "$CLONE" remote get-url origin)
BRANCH=$(git -C "$CLONE" rev-parse --abbrev-ref HEAD)
```

**GitHub** (`github.com` in the URL): `gh pr create --head "$BRANCH" --base main --title … --body …` under the user's own identity.

**Gitea** (any other host): the REST API with the Vibe bot token, so the PR is attributed to `mistral-bot`. Write the body to a file and load it with `jq --rawfile`:

```bash
curl -fsS -X POST -H "Authorization: token ${GITEA_VIBE_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg t "<title>" --rawfile b "$BODY" --arg h "$BRANCH" '{head:$h, base:"main", title:$t, body:$b}')" \
  "<host>/api/v1/repos/<owner>/<repo>/pulls"
```

**Never merge.** Post your verification summary as a PR **comment** under your own identity, opening with "Orchestrator's verification" and separating what the worker did from what you changed. When you are Vibe too, the comment and the PR share an author, so that opening line is what tells a reviewer which is which.

### 7. Cleanup

Leave the clone. It sits inside your session directory and goes away with it when the session is deleted (`session-dir-deletion`); trying to `rm -rf` it can be refused as a dangerous removal.

## Notes

- Skills are shared between Claude and Vibe (`~/.claude/skills` and `~/.vibe/skills` both resolve to the same files).
- For tight, parallel, low-friction delegation with structured reporting, the Claude `Agent` tool is smoother. Use Vibe when you want a different model, the `mistral-bot` identity, or a separate system.
- The worker inherits your other environment variables; only the PR token and the harness markers are removed.
