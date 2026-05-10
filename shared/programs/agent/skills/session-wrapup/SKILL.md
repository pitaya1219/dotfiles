---
name: session-wrapup
description: Archive session summary
user-invocable: true
version: 1.0.0
---

# Session Wrapup Skill (Global Version)

## What This Skill Does

1. Provides a template for creating session summary markdown files
2. Guides branch cleanup operations using the project's default branch

## Summary MD Template

- **Overview** — Purpose and results (2-4 sentences)
- **What Was Done** — Actions taken (bullet points)
- **Files Changed** — `git diff --stat` summary
- **Decisions Made** — Decisions and reasons
- **Problems & Solutions** — Issues encountered and solutions
- **Open Items** — TODO + known issues
- **Next Session** — Tasks for next session (cold-start ready)
- **References** — Commands, URLs, snippets

## Usage

Create a summary file manually using the template. Example:

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

**Note**: Global version does NOT manage session directories.

---

```bash
cat > session-summary-$(date +%Y-%m-%d).md << 'EOF'
# Session Summary

## Overview
[Brief description of the session]

## What Was Done
- [Action 1]
- [Action 2]

## Files Changed
[List of changed files]

## Decisions Made
[Key decisions]

## Problems & Solutions
- Problem: [description]
- Solution: [solution]

## Open Items
[Pending tasks]

## Next Session
[Tasks for next session]

## References
[Relevant links]
EOF
```
