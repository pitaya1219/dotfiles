---
name: session-wrapup
description: Archive session summary
user-invocable: true
version: 1.1.0
---

# Session Wrapup Skill (Global Version)

## What This Skill Does

1. Creates a session summary markdown file in the correct location
2. Guides branch cleanup operations using the project's default branch

## Summary File Location

Always save to: `~/agent-sessions/.agent/sessions/`

## Naming Convention

```
session-{SESSION_UUID}-{short-description}-{YYYY-MM-DD}.md
```

- `SESSION_UUID`: full UUID of the current Claude Code session
- `short-description`: kebab-case summary of the session topic (e.g. `nvim-dir-completion`, `fix-home-manager-warnings`)
- `YYYY-MM-DD`: today's date

Examples:
```
session-65410f8b-31e4-4489-88bc-c96b1a9e6538-nvim-dir-completion-claude-vibe-2026-06-02.md
session-1d88e9e8-c9a2-451b-a932-122cffbed8ae-enable-nvim-providers-2026-06-01.md
```

## Summary MD Template

- **Overview** — Purpose and results (2-4 sentences)
- **What Was Done** — Actions taken (bullet points)
- **Files Changed** — `git diff --stat` summary
- **Decisions Made** — Decisions and reasons
- **Problems & Solutions** — Issues encountered and solutions
- **Open Items** — TODO + known issues
- **Next Session** — Tasks for next session (cold-start ready)
- **References** — Commands, URLs, snippets

## Branch Cleanup Flow (Global)

After completing work, clean up branches:

```bash
# 1. Detect and switch to default branch
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
git checkout $DEFAULT_BRANCH

# 2. Delete feature branch
git branch -D feat/your-feature

# 3. Pull latest changes
git pull origin $DEFAULT_BRANCH
```

---

```markdown
# Session Summary

## Overview
[Brief description of the session]

## What Was Done
- [Action 1]
- [Action 2]

## Files Changed
[git diff --stat output]

## Decisions Made
[Key decisions and reasons]

## Problems & Solutions
- Problem: [description]
- Solution: [solution]

## Open Items
[Pending tasks]

## Next Session
[Tasks for next session]

## References
[Relevant links, commands, snippets]
```
