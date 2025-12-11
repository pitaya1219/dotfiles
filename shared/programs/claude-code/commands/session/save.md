---
allowed-tools: Write(*), Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*)
argument-hint: [output-path]
description: Save current session summary as markdown
---

Create a comprehensive summary of the current Claude Code session and save it as a markdown file.

Output path: $ARGUMENTS (if empty, use `.claude/sessions/YYYY-MM-DD-HHmmss.md`)

The summary should include:

1. **Session Overview**
   - Date and time
   - Main objectives and goals
   - Brief summary of what was accomplished

2. **Git Context** (if in a git repository)
   - Repository name (from remote URL if available)
   - Current branch name
   - Working tree status (clean/dirty)
   - Recent commits related to this session
   - Files changed (from git status/diff)

3. **Key Points and Decisions**
   - Important design decisions made
   - Trade-offs considered
   - Rationale behind key choices

4. **Work Flow**
   - Sequence of tasks completed
   - How tasks evolved during the session
   - Context and reasoning for each major step

5. **Technical Details**
   - Files created, modified, or deleted
   - Configuration changes
   - Commands executed
   - Code patterns or approaches used

6. **Outcomes and Results**
   - What was achieved
   - Any issues encountered and how they were resolved
   - Remaining tasks or follow-ups (if any)

7. **Learnings and Insights**
   - Key concepts explored
   - Best practices identified
   - Useful patterns or techniques

Format: Use clear headings, bullet points, and code blocks where appropriate.
Tone: Technical but readable, focusing on "what" and "why" over "how".
