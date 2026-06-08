---
name: dive-pr
description: Set up a local workspace for reviewing a PR — clone branch, install deps, open nvim in tmux
user-invocable: true
version: 1.2.3
---

# Dive PR Skill

## What This Skill Does

Automates the workspace setup required to review a pull request:
1. **Auto-detects** repos/PRs already present in the current session directory (when called with no argument)
2. Detects the Git platform (GitHub or Gitea) from the PR URL or repo remote
3. Fetches the PR head branch name via the appropriate API/CLI/MCP tool
4. Creates a session directory and clones (or updates) the branch
5. Auto-detects and installs dependencies
6. Opens nvim in a new tmux window named after the session ID

## Usage

```
/dive-pr                                               # auto-detect from session dir
/dive-pr https://github.com/org/repo/pull/500
/dive-pr https://git.example.com/org/repo/pulls/500
/dive-pr --pr 500   # infers repo from the current git remote
```

`$ARGUMENTS` contains the raw argument string passed by the user.

---

## Phase 0: Auto-detect (when `$ARGUMENTS` is empty)

If `$ARGUMENTS` is empty, scan the current session directory for existing git repositories and their associated PRs before asking the user for input.

### Step 0-1: Locate the session directory

```bash
_BASE=~/.claude/projects/$(echo "$HOME/agent-sessions" | sed 's|/|-|g')
SESSION_ID=$(ls -dt \
    "${_BASE}"/????????-????-????-????-????????????/ \
    "${_BASE}"/????????-????-????-????-????????????.jsonl \
    2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.jsonl$//')
SESSION_DIR="$HOME/agent-sessions/session-${SESSION_ID}"
```

### Step 0-2: Find git repositories in the session directory

```bash
find "$SESSION_DIR" -maxdepth 2 -name ".git" -type d | sed 's|/.git$||'
```

For each found repo directory, collect:
- **Current branch:** `git -C <dir> rev-parse --abbrev-ref HEAD`
- **Remote URL:** `git -C <dir> remote get-url origin`

Skip repos whose current branch is `main`, `master`, or `develop` (not a PR branch).

### Step 0-3: Look up the associated PR for each candidate

Determine the platform from the remote URL (same logic as Phase 1).

**GitHub:**
```bash
gh pr view --repo <owner>/<repo> --head <branch> --json number,title,headRefName,baseRefName 2>/dev/null
```

**Gitea:**
Use `mcp__gitea__list_pull_requests` (or `mcp__gitea__pull_request_read` if the PR number is known) to find an open PR whose `head.ref` matches the current branch.

### Step 0-4: Decide

| Candidates found | Action |
|---|---|
| **0** | Ask the user for a PR URL or `--pr <number>` and proceed to Phase 1 |
| **1** | Use it automatically — skip Phase 1 and jump to Phase 4 (clone/update is already done) |
| **2+** | List them and ask the user to choose, then jump to Phase 4 |

When jumping directly to Phase 4 with an already-cloned repo, skip the clone step and go straight to the dependency install (Phase 5).

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

nvim is opened with `exe` to wrap `CocCommand explorer` so the surrounding `|` separators are not passed as arguments to CocCommand:

```
nvim +'try | exe "CocCommand explorer" | catch | Explore | endtry'
```

Note: **do not** split this into multiple `-c` flags — each `-c` runs in an independent context, breaking the `try/catch/endtry` block.

**Quoting rule for the tmux context:** the outer shell uses `bash -c '...'` (single-quoted), so the `NVIM_CMD` variable must use single quotes on the outside and `\"` for the Vimscript string literal — this avoids single quotes inside the `bash -c` argument, which would break the shell string.

### If inside a tmux session (`$TMUX` is set)

```bash
WINDOW_NAME="${SESSION_ID:0:8}"

ACTIVATE=""
[ -f "$REPO_DIR/.venv/bin/activate" ] && \
  ACTIVATE="source '$REPO_DIR/.venv/bin/activate' && "

NVIM_CMD='nvim +"try | exe \"CocCommand explorer\" | catch | Explore | endtry"'

tmux new-window -c "$REPO_DIR" -n "$WINDOW_NAME" \
  "bash -c '${ACTIVATE}${NVIM_CMD}'"
```

### If NOT in a tmux session (`$TMUX` is unset)

Output the commands for the user to run manually and do not attempt to open tmux:

```
# Workspace ready — open manually:
cd <REPO_DIR>
source .venv/bin/activate   # (if .venv exists)
nvim +'try | exe "CocCommand explorer" | catch | Explore | endtry'
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
