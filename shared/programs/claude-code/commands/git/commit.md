---
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*)
description: Analyze changes and create commits in logical groups
---

Analyze the current git changes and create commits ONLY for work completed in this session.

IMPORTANT: Only commit changes that were explicitly worked on during this Claude Code session. Exclude any unrelated changes that may exist in the working directory.

Steps:
1. Run `git status` and `git diff` to see all changes
2. Review the session conversation to identify which files were modified during this session
3. ONLY stage and commit files that were part of this session's work
4. Exclude any files that were:
   - Modified outside this session
   - Untracked files not created in this session
   - Changes unrelated to the session's tasks
5. Group session-related changes into logical commits based on:
   - Conversation flow and task progression
   - Feature or functionality groupings
   - File relationships and dependencies
6. For each commit, stage only relevant session files and write a clear message

Commit message guidelines (from CLAUDE.md):
- Start with a capital letter
- End with a period
- Be descriptive and concise
- NEVER include Claude-related content in messages
- Focus on what changed and why
