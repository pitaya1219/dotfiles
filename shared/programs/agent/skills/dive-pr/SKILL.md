---
name: dive-pr
description: Set up a local workspace for reviewing a PR — clone branch, install deps, open nvim in tmux
user-invocable: true
version: 1.0.0
---

# Review Setup Skill

## What This Skill Does

Automates the workspace setup required to review a pull request:
1. Detects the Git platform (GitHub or Gitea) from the PR URL or current repo remote
2. Fetches the PR head branch name via the appropriate API/CLI/MCP tool
3. Creates a session directory and clones (or updates) the branch
4. Auto-detects and installs dependencies
5. Opens nvim in a new tmux window named after the session ID

## Usage

```
/review-setup https://github.com/org/repo/pull/500
/review-setup https://git.example.com/org/repo/pulls/500
/review-setup --pr 500   # infers repo from the current git remote
```

`$ARGUMENTS` contains the raw argument string passed by the user.

---

## Phase 1: Parse the Argument

Parse `$ARGUMENTS` to extract the PR reference.

### URL form (`https://...`)

Extract `host`, `owner`, `repo`, `pr_number` from the URL path.

- **GitHub** pattern: `https://github.com/<owner>/<repo>/pull/<number>`
- **Gitea** pattern: `https://<host>/<owner>/<repo>/pulls/<number>`

Determine platform:
- `host == "github.com"` → **GitHub**
- any other host → **Gitea**

### `--pr <number>` form

Get the current repo's remote URL:

```bash
git remote get-url origin
```

Parse `host`, `owner`, `repo` from that URL (supports both HTTPS and SSH formats).
Determine platform the same way as above.

---

## Phase 2: Get the PR Head Branch

### GitHub

```bash
gh pr view <pr_number> --repo <owner>/<repo> \
  --json headRefName,baseRefName \
  -q '{branch: .headRefName, base: .baseRefName}'
```

### Gitea

Use the `mcp__gitea__pull_request_read` MCP tool with:
- `method`: `get`
- `owner`: extracted owner
- `repo`: extracted repo
- `pull_number`: PR number (integer)

Extract:
- Branch to clone: `head.label` or `head.ref`
- Base branch: `base.label` or `base.ref`

---

## Phase 3: Determine Session Directory

Look up the current session ID from the Claude projects directory:

```bash
_BASE=~/.claude/projects/$(echo "$HOME/agent-sessions" | sed 's|/|-|g')
SESSION_ID=$(ls -dt \
    "${_BASE}"/????????-????-????-????-????????????/ \
    "${_BASE}"/????????-????-????-????-????????????.jsonl \
    2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.jsonl$//')
SESSION_ID="${SESSION_ID:-$(python3 -c 'import uuid; print(uuid.uuid4())')}"
SESSION_DIR="$HOME/agent-sessions/session-${SESSION_ID}"
mkdir -p "$SESSION_DIR"
```

The **first 8 characters** of `SESSION_ID` will be used as the tmux window name.

---

## Phase 4: Clone or Update the Branch

Compute the clone URL:
- **GitHub:** `https://github.com/<owner>/<repo>.git`
- **Gitea:** `https://<host>/<owner>/<repo>.git`

Target directory: `$SESSION_DIR/<repo>/`

```bash
REPO_DIR="$SESSION_DIR/<repo>"

if [ -d "$REPO_DIR/.git" ]; then
  # Already cloned — update to latest
  git -C "$REPO_DIR" fetch origin "<branch>"
  git -C "$REPO_DIR" checkout "<branch>"
  git -C "$REPO_DIR" pull --ff-only
else
  # Fresh clone — only the target branch
  git clone --single-branch --branch "<branch>" "<clone_url>" "$REPO_DIR"
fi
```

---

## Phase 5: Detect and Install Dependencies

Inspect `$REPO_DIR` for the files below and run **all** matching install commands.
Multiple package managers can coexist in one repo — run every one that matches.

| Detection file(s) | Tool | Install command (run from `$REPO_DIR`) |
|---|---|---|
| `pyproject.toml` or `poetry.lock` | Poetry | `poetry config virtualenvs.in-project true --local && poetry install` |
| `requirements.txt` | pip | `python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt` |
| `package.json` + `yarn.lock` | Yarn | `yarn install` |
| `package.json` + `pnpm-lock.yaml` | pnpm | `pnpm install` |
| `package.json` (no yarn/pnpm lock) | npm | `npm install` |
| `Gemfile` | Bundler | `bundle install` |
| `go.mod` | Go modules | `go mod download` |
| `Cargo.toml` | Cargo | `cargo fetch` |

If no files match, skip installation and proceed to Phase 6.

---

## Phase 6: Open nvim in tmux

### If inside a tmux session (`$TMUX` is set)

```bash
WINDOW_NAME="${SESSION_ID:0:8}"

ACTIVATE=""
[ -f "$REPO_DIR/.venv/bin/activate" ] && \
  ACTIVATE="source '$REPO_DIR/.venv/bin/activate' && "

tmux new-window -c "$REPO_DIR" -n "$WINDOW_NAME" \
  "bash -c '${ACTIVATE}nvim'"
```

### If NOT in a tmux session (`$TMUX` is unset)

Output the commands for the user to run manually and do not attempt to open tmux:

```
# Workspace ready — open manually:
cd <REPO_DIR>
source .venv/bin/activate   # (if .venv exists)
nvim
```

---

## Phase 7: Report

Output a concise summary:

```
Review workspace ready

  Platform : GitHub | Gitea (<host>)
  PR       : <owner>/<repo>#<pr_number>  [<branch>]
  Directory: <REPO_DIR>
  Deps     : <comma-separated list of tools run, or "none detected">
  tmux     : window "<WINDOW_NAME>" opened  |  (not in tmux — run manually)
```
