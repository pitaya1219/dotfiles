---
name: commands-session-save
description: Save current session summary as markdown
user-invocable: true
version: 1.1.0
---

Create a comprehensive summary of the current session and save it as a markdown file.

## Session ID Detection

Before writing the file, obtain the current session UUID using the following priority:

```bash
WORKDIR_ENCODED=$(pwd | sed 's|/|-|g')

# 1. Claude Code: ~/.claude/projects/<workdir>/<uuid>.jsonl (most reliable)
SESSION_ID=$(ls -t "$HOME/.claude/projects/${WORKDIR_ENCODED}"/*.jsonl 2>/dev/null | \
  head -1 | xargs -r basename -s .jsonl 2>/dev/null)

# 2. Claude Code: /tmp tasks dir filtered by workdir
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(find /tmp -maxdepth 7 -type d -name "tasks" 2>/dev/null | \
    grep "${WORKDIR_ENCODED}" | \
    while read d; do echo "$(stat -c %Y "$d") $d"; done | \
    sort -rn | head -1 | \
    awk '{print $2}' | \
    grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
fi

# 3. Claude Code: /tmp tasks dir across all workdirs
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(find /tmp -maxdepth 7 -type d -name "tasks" -path "*/claude-*" 2>/dev/null | \
    while read d; do echo "$(stat -c %Y "$d") $d"; done | \
    sort -rn | head -1 | \
    awk '{print $2}' | \
    grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
fi

# 4. Vibe: meta.json in cwd-local → ~/agent-sessions → $VIBE_HOME (global)
if [ -z "$SESSION_ID" ]; then
  _META=$(ls -dt \
    "$(pwd)/.vibe/logs/session"/session_*/meta.json \
    "$HOME/agent-sessions/.vibe/logs/session"/session_*/meta.json \
    "${VIBE_HOME:-$HOME/.vibe}/logs/session"/session_*/meta.json \
    2>/dev/null | head -1)
  if [ -n "$_META" ]; then
    SESSION_ID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['session_id'])" "$_META" 2>/dev/null)
    # Fallback: 8-char prefix from dirname (session_<ts>_<ts>_<hex>)
    [ -z "$SESSION_ID" ] && SESSION_ID=$(echo "$_META" | grep -oE 'session_[0-9]+_[0-9]+_([0-9a-f]+)' | grep -oE '[0-9a-f]+$')
  fi
fi
```

## Output Path

- If `$ARGUMENTS` is provided: use it as the output path directly
- Otherwise: `.ai/sessions/YYYY-MM-DD-${SESSION_ID}-${summary}.md`
  - If `SESSION_ID` could not be obtained: fall back to `.ai/sessions/YYYY-MM-DD-HHmmss-${summary}.md`

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
