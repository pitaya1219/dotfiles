---
name: session-wrapup
description: Archive session summary and clean up branches
user-invocable: true
version: 2.0.0
---

# Session Wrapup Skill

## What This Skill Does

1. Saves a session summary via `Skill(session-save)`
2. Guides branch cleanup operations using the project's default branch

## Step 1: Save Session Summary

Compute the output path for the local file fallback:

```
~/agent-sessions/.agent/sessions/session-{SESSION_UUID}-{short-description}-{YYYY-MM-DD}.md
```

- `SESSION_UUID`: full UUID of the current Claude Code session (use Session ID Detection from `Skill(session-save)`)
- `short-description`: kebab-case summary of the session topic (e.g. `nvim-dir-completion`, `fix-home-manager-warnings`)
- `YYYY-MM-DD`: today's date

Then invoke:

```
Skill(session-save) $ARGUMENTS="<computed-output-path>"
```

`Skill(session-save)` will automatically check Logseq availability:
- If Logseq is reachable → saves to today's journal page in Logseq (ignores the path argument)
- If not → saves to the provided local file path

## Step 2: Branch Cleanup

After saving, clean up branches:

```bash
# 1. Detect and switch to default branch
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
git checkout $DEFAULT_BRANCH

# 2. Delete feature branch
git branch -D feat/your-feature

# 3. Pull latest changes
git pull origin $DEFAULT_BRANCH
```
