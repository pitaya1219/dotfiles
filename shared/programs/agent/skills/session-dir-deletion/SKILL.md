---
name: session-dir-deletion
description: Delete the current session directory after session-wrapup completes in ~/agent-sessions
user-invocable: true
trigger: After session-wrapup completes when working in ~/agent-sessions
version: 1.0.0
---

# Session Directory Deletion Skill

## When to Invoke

Run this skill after `session-wrapup` completes when working inside a session directory under `~/agent-sessions`.

## Background

In `~/agent-sessions`, each agent session works inside a dedicated directory named after the session's UUID:

```
~/agent-sessions/session-{SESSION_UUID}/
```

This skill deletes that directory once the session is complete.

## What This Skill Does

Deletes the current session directory (`session-{SESSION_UUID}`) after user confirmation.

## Safety Check

The session directory name must match `session-{UUID}`. Any other directory name causes an immediate abort.

```bash
# Determine session directory name (run from within the session directory)
cd ..
SESSION_DIR=$(basename "$(pwd)")

[[ "$SESSION_DIR" =~ ^session-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || {
  echo "ERROR: Not a valid session directory: $SESSION_DIR"
  exit 1
}

# Confirm with user before deleting
read -p "Delete session directory $SESSION_DIR? [y/N]: " ans
[[ "$ans" != "y" && "$ans" != "Y" ]] && echo "Skipped." && exit 0

rm -rf "$SESSION_DIR"
echo "Deleted: $SESSION_DIR"
```
