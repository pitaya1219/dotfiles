---
allowed-tools: Bash(git *), Read(*), Write(*), Edit(*), Glob(*), Grep(*), TodoWrite(*), mcp__gitea__create_pull_request(*), mcp__gitea__add_issue_labels(*), AskUserQuestion(*)
argument-hint: [requirement or --file <path>]
description: Create a pull request by implementing changes from scratch
---

Create a pull request by implementing requested changes from scratch, including code editing, committing, and PR creation.

## Argument Handling

The user's argument is provided after `ARGUMENTS:` in the command invocation.

**Parse the argument as follows:**
- If argument starts with `--file`: Read requirement from the specified file path
- If argument is empty: Ask user what they want to implement using AskUserQuestion tool
- Otherwise: The argument IS the requirement - implement it directly

**CRITICAL**: Start implementing immediately based on the argument. Do NOT output example text or ask unnecessary questions.

## Execution Flow

### Phase 1: Preparation

1. **Get Repository Info**
   ```bash
   git remote -v | head -1
   ```
   Extract owner and repo name from the remote URL.

2. **Switch to Main Branch**
   ```bash
   git checkout main
   git pull origin main --rebase
   ```
   If conflicts occur, abort and inform user.

3. **Create Feature Branch**
   Generate branch name from requirement:
   - `feat/` - New features
   - `fix/` - Bug fixes
   - `docs/` - Documentation
   - `refactor/` - Code refactoring
   - `chore/` - Maintenance tasks

   ```bash
   git checkout -b {prefix}/{descriptive-name}
   ```

### Phase 2: Implementation

1. Use TodoWrite to plan implementation steps
2. Implement the changes following project conventions
3. Verify changes for completeness

### Phase 3: Commit and Push

**Commit Guidelines:**
- Use conventional commit format: `<type>: <description>.`
- NEVER include AI or Claude references in commit messages
- End with period

```bash
git add <files>
git commit -m "<type>: <description>."
git push -u origin {branch-name}
```

### Phase 4: Create PR

Use `mcp__gitea__create_pull_request` with:
- `owner`: Extracted from git remote
- `repo`: Extracted from git remote
- `title`: Conventional commit style title
- `body`: Summary, changes, implementation details, test plan
- `head`: Branch name
- `base`: "main"

### Phase 5: Report

Output the PR URL and summary to user:
```
✅ PR #N created: {url}

Summary: {brief description}
Files changed: N files
```

## Error Handling

If implementation fails:
1. Rename branch to `error/{original-branch-name}`
2. Create ERROR.md with details
3. Commit and push error branch
4. Create draft PR with `[ERROR]` prefix in title
5. Return to main branch
6. Notify user with error summary and draft PR link
