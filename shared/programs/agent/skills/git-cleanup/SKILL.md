---
name: git-cleanup
description: Clean up and reorganize git commits for cleaner PR history
user-invocable: true
version: 1.0.0
---

# Git Commit Cleanup Skill

AI-executable skill for cleaning up and reorganizing git commits into a logical, reviewable structure.

## What This Skill Does

Helps AI agents (and humans) reorganize messy git commit history by:
- Squashing multiple bug fixes into feature commits
- Splitting mixed commits into logical units
- Removing accidentally committed files (logs, temp files)
- Rewriting commit messages for clarity
- Creating clean, reviewable PR history

## ⚠️ CRITICAL WARNING for AI Agents

**Commit positions change after each operation!**

```
Before: 6 commits (positions 1,2,3,4,5,6)
After squashing 2-4: 3 commits (positions 1,2,3)

Old position 5 → NOW position 2
Old position 6 → NOW position 3
```

**Always re-count commits after EVERY operation:**
```bash
git log --oneline main..HEAD | wc -l
```

**DO NOT use original positions after state changes!**

See `MISTRAL_VIBE_GUIDE.md` for detailed examples.

## When to Use

Use this skill when:
- PR has too many small "fix" commits
- Commits need logical reorganization before review
- Unwanted files were accidentally committed
- Commit messages need improvement
- History is messy and hard to review

## Quick Start

### For AI Agents (Mistral Vibe, etc.)

**Analyze commits:**
```bash
git log --oneline main..HEAD
```

**Squash all commits into one:**
```bash
# 1. Create backup
git branch backup/$(git rev-parse --abbrev-ref HEAD)

# 2. Squash
GIT_SEQUENCE_EDITOR="sed -i '2,$s/^pick/fixup/'" git rebase -i main

# 3. Verify
git log --oneline main..HEAD
```

**Remove unwanted file:**
```bash
# For the last commit
git reset --soft HEAD~1
git reset HEAD unwanted.log
git commit -C ORIG_HEAD
```

**Split last commit:**
```bash
git reset --soft HEAD~1
git reset HEAD file-to-separate.kt
git commit -m "First part"
git add file-to-separate.kt
git commit -m "Second part"
```

### For Humans

Use the interactive helper script:
```bash
cd your-repo
~/.vibe/skills/git-cleanup/git-cleanup-commits.sh
```

## Common Scenarios

### Scenario 1: "Feature + Multiple Fixes" → "Clean Feature"

**Before:**
```
feat: Add feature
fix: Fix bug 1
fix: Fix bug 2
fix: Fix bug 3
```

**After:**
```
feat: Add feature (includes all fixes)
```

**Commands:**
```bash
git branch backup/my-branch
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main
git push --force-with-lease origin my-branch
```

### Scenario 2: "Messy History" → "3 Logical Commits"

**Before:** 6 commits (1 feature + 3 fixes + 1 new feature + 1 UI fix)

**After:** 3 commits
1. Feature + all its fixes
2. New feature
3. UI fix

**Commands:**
```bash
git branch backup/my-branch

# Squash first 4 commits
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main

# Result: 3 commits
git log --oneline main..HEAD

# If commit 2 needs splitting:
git reset --soft HEAD~1
git reset HEAD ui-file.kt
git commit -m "New feature"
git add ui-file.kt
git commit -m "UI fix"
```

### Scenario 3: Remove Accidentally Committed File

**Problem:** `parallel.log` was committed in last commit

**Solution:**
```bash
git branch backup/my-branch
git reset --soft HEAD~1
git reset HEAD parallel.log
git commit -C ORIG_HEAD  # Reuse original message
git push --force-with-lease origin my-branch
```

## AI Agent Workflow

### Step-by-Step Template

**CRITICAL**: After EACH operation, re-count commits and verify state before proceeding.

```bash
# 1. ANALYZE - Count and show commits
echo "Current commits:"
git log --oneline main..HEAD
COMMIT_COUNT=$(git log --oneline main..HEAD | wc -l)
echo "Total: $COMMIT_COUNT commits"

# 2. SAFETY - Create backup
git branch backup/$(git rev-parse --abbrev-ref HEAD)

# 3. PLAN
# Based on CURRENT commit count, decide:
#   - Which commits to squash (use positions: 2,3,4)
#   - Which to keep separate
#   - Target final count

# 4. EXECUTE FIRST OPERATION
# Use GIT_SEQUENCE_EDITOR with sed patterns
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main

# 5. VERIFY STATE AFTER OPERATION ⚠️ CRITICAL
echo "After squash:"
git log --oneline main..HEAD
NEW_COUNT=$(git log --oneline main..HEAD | wc -l)
echo "Now have: $NEW_COUNT commits"

# 6. IF MORE OPERATIONS NEEDED
# Re-count and use NEW positions based on CURRENT state
# DO NOT use original positions!

# Example: If you now have 3 commits and want to split commit 2:
# The commit numbers are NOW 1, 2, 3 (not the original numbers)

# 7. FINAL VERIFY
git log --oneline main..HEAD
git log --stat main..HEAD

# 8. PUSH
git push --force-with-lease origin $(git rev-parse --abbrev-ref HEAD)
```

### ⚠️ CRITICAL: State Tracking

**ALWAYS re-count commits after each operation:**

```bash
# After ANY git operation (rebase, reset, commit):
git log --oneline main..HEAD | wc -l
```

**Use relative positions, not absolute numbers:**

- ✅ Good: "Split the last commit" → `git reset --soft HEAD~1`
- ✅ Good: "Squash commits 2-3 into 1" (based on CURRENT count)
- ❌ Bad: Using original commit positions after state changed

## sed Patterns Reference

### Squashing Commits

```bash
# Squash all into first
GIT_SEQUENCE_EDITOR="sed -i '2,$s/^pick/fixup/'" git rebase -i main

# Squash specific range (commits 2-4)
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main

# Squash last N commits (example: last 3)
# If you have 5 commits total, squash commits 3,4,5 into 1,2
GIT_SEQUENCE_EDITOR="sed -i '3,5s/^pick/fixup/'" git rebase -i main
```

### Other Operations

```bash
# Reword commit message
GIT_SEQUENCE_EDITOR="sed -i '1s/^pick/reword/'" git rebase -i main

# Edit commit (to split or modify)
GIT_SEQUENCE_EDITOR="sed -i '2s/^pick/edit/'" git rebase -i main

# Drop (delete) commit
GIT_SEQUENCE_EDITOR="sed -i '3s/^pick/drop/'" git rebase -i main
```

## Safety Checklist

Before cleanup:
- [ ] No uncommitted changes (`git status` clean)
- [ ] Backup branch created
- [ ] Know base branch (usually `main`)

After cleanup:
- [ ] Commit count correct (`git log --oneline main..HEAD | wc -l`)
- [ ] No unwanted files (`git log --name-status main..HEAD`)
- [ ] Code unchanged (if only reorganizing)

Before push:
- [ ] Use `--force-with-lease` (NEVER plain `--force`)
- [ ] Verify final history looks clean

## Error Recovery

```bash
# Abort ongoing rebase
git rebase --abort

# Restore from backup
git reset --hard backup/branch-name

# Find lost commits
git reflog
git reset --hard HEAD@{N}
```

## For Mistral Vibe Users

This skill works best when given **explicit, step-by-step commands**:

**Good Prompt:**
```
Using the git-cleanup skill, execute these commands one by one:

1. git branch backup/my-feature
2. git log --oneline main..HEAD

(Show me the output, then I'll give you the next command)
```

**After seeing output:**
```
Now execute:
3. GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main
4. git log --oneline main..HEAD

(Verify the result)
```

## Advanced: Multiple Operations

**Squash + Remove File + Reword:**

```bash
# 1. Backup
git branch backup/my-branch

# 2. Squash commits 2-4
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main

# 3. Remove unwanted file from last commit
git reset --soft HEAD~1
git reset HEAD unwanted.log
git commit -m "New detailed message here"

# 4. Verify and push
git log --stat main..HEAD
git push --force-with-lease origin my-branch
```

## Related Files

- `guide.md` - Comprehensive technical guide (407 lines)
- `git-cleanup-commits.sh` - Interactive helper script
- `examples/pr73.md` - Real-world example from VisionPipe PR #73

## Tips for Success

1. **Work incrementally** - Verify after each step
2. **Always backup** - Create backup branch before ANY rebase
3. **Use --stat** - Easier to parse than full diffs
4. **Test on small changes first** - Practice on simple cases
5. **Keep it simple** - Don't try to do everything in one command

---

**Version:** 1.0.0
**Last Updated:** 2026-02-20
**Tested With:** Git 2.x, Mistral Vibe, Claude Code
