---
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*)
description: Analyze changes and create commits in logical groups
---

Analyze the current git changes and create commits in meaningful, logical units.

Review the conversation history in this Claude Code session to understand:
- What tasks were accomplished
- The sequence and context of changes
- Natural groupings based on the work flow

Steps:
1. Run `git status` and `git diff` to see all changes
2. Consider the session conversation to understand the work context
3. Group related changes into logical commits based on:
   - Conversation flow and task progression
   - Feature or functionality groupings
   - File relationships and dependencies
4. Create separate commits for each logical group
5. For each commit, stage only relevant files and write a clear message

Commit message guidelines (from CLAUDE.md):
- Start with a capital letter
- End with a period
- Be descriptive and concise
- NEVER include Claude-related content in messages
- Focus on what changed and why
