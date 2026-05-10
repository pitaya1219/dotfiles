# Git Cleanup Skill - Quick Start for Mistral Vibe

## 🚀 Using This Skill in Mistral Vibe

### Method 1: Invoke Directly (Slash Command)

```bash
vibe
> /git-cleanup
```

This loads the skill and shows the main documentation.

### Method 2: Reference in Prompt

```
I need to clean up my PR #73 commits. Using the git-cleanup skill, help me
reorganize 6 commits into 3 logical commits.
```

### Method 3: Step-by-Step Execution (Recommended)

**Best for Mistral Vibe** - Explicit, one-command-at-a-time approach with state verification:

```
Step 1: Show me the current commits AND count them

Execute:
git log --oneline main..HEAD
echo "---"
git log --oneline main..HEAD | wc -l
```

**After seeing output (e.g., 6 commits):**

```
Step 2: Create backup

Execute: git branch backup/my-feature
```

**After backup created:**

```
Step 3: Squash commits 2-4 into commit 1

Execute: GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main
```

**CRITICAL - After squash:**

```
Step 4: Re-count commits to verify new state

Execute:
git log --oneline main..HEAD
echo "---"
git log --oneline main..HEAD | wc -l

Expected: Should now show 3 commits (was 6, squashed 3 into 1)
```

**Only if count is correct, proceed to next operations based on NEW count**

## ⚠️ CRITICAL: State Tracking

**After EVERY git operation, re-verify the current state:**

```bash
# Always re-count after rebase, reset, or commit
git log --oneline main..HEAD | wc -l
```

**Why this matters:**
- Original state: 6 commits → positions 1,2,3,4,5,6
- After squashing 2-4: 4 commits → positions are NOW 1,2,3,4
- **Old position 5 is NOW position 2!**
- Using old positions will give wrong results

**Example of state change:**

```
Before squash (6 commits):
1. feat: Core
2. fix: Bug1      ← squash these
3. fix: Bug2      ← squash these
4. fix: Bug3      ← squash these
5. feat: Memory   ← This becomes position 2 after squash!
6. fix: UI        ← This becomes position 3 after squash!

After squash (3 commits):
1. feat: Core (includes bug fixes)
2. feat: Memory   ← Was position 5, NOW position 2
3. fix: UI        ← Was position 6, NOW position 3
```

## 📋 Common Tasks

### Task: Squash All Commits

**User says:**
```
Squash all my commits into one clean commit
```

**You execute:**
```bash
# 1. Backup
git branch backup/$(git rev-parse --abbrev-ref HEAD)

# 2. Check how many commits
git log --oneline main..HEAD | wc -l

# 3. Squash all (if 5 commits, squash 2-5 into 1)
GIT_SEQUENCE_EDITOR="sed -i '2,$s/^pick/fixup/'" git rebase -i main

# 4. Verify
git log --oneline main..HEAD
```

### Task: Remove Accidentally Committed File

**User says:**
```
Remove parallel.log from my last commit
```

**You execute:**
```bash
# 1. Backup
git branch backup/my-feature

# 2. Reset last commit
git reset --soft HEAD~1

# 3. Unstage the file
git reset HEAD parallel.log

# 4. Recommit without it
git commit -C ORIG_HEAD

# 5. Verify
git log --name-status -1
```

### Task: Split One Commit into Two

**User says:**
```
Split my last commit - put UI changes in one commit and logic changes in another
```

**You execute:**
```bash
# 1. Backup
git branch backup/my-feature

# 2. Reset last commit (keeps changes staged)
git reset --soft HEAD~1

# 3. See what's staged
git status --short

# 4. Unstage UI files
git reset HEAD ui-file.kt another-ui.kt

# 5. Commit logic changes
git commit -m "feat: Add business logic"

# 6. Stage and commit UI
git add ui-file.kt another-ui.kt
git commit -m "feat: Add UI components"

# 7. Verify
git log --oneline -2
```

## 🎯 Template Responses

### When asked to clean up commits

**Your response template:**

```
I'll help you clean up the commits. Let me first analyze the current state:

[Execute: git log --oneline main..HEAD]

Based on the output, here's my plan:
- Commit 1: [description]
- Commits 2-4: Will be squashed into Commit 1
- Commit 5: [description] - keeping separate
- Commit 6: [description] - keeping separate

This will result in 3 clean commits.

Shall I proceed? I'll create a backup first.

[Wait for confirmation, then execute step by step]
```

## ⚠️ Safety Checklist

Before ANY rebase operation:

```bash
# 1. Check working directory is clean
git status

# 2. Create backup
git branch backup/branch-name

# 3. Know your base branch
git branch --contains HEAD | grep -E 'main|master'
```

After cleanup:

```bash
# 4. Verify commit count
git log --oneline main..HEAD | wc -l

# 5. Check for unwanted files
git log --name-status main..HEAD

# 6. Compare with original
git diff origin/branch-name HEAD --stat
```

## 🔧 sed Pattern Examples

### Squash commits 2, 3, 4 into commit 1

```bash
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main
```

### Squash all except first

```bash
GIT_SEQUENCE_EDITOR="sed -i '2,$s/^pick/fixup/'" git rebase -i main
```

### Reword commit message

```bash
GIT_SEQUENCE_EDITOR="sed -i '1s/^pick/reword/'" git rebase -i main
# Then git will pause for you to edit the message
```

### Edit commit (to split or modify)

```bash
GIT_SEQUENCE_EDITOR="sed -i '2s/^pick/edit/'" git rebase -i main
# Git will pause at commit 2
# Make your changes, then:
git rebase --continue
```

## 📚 Full Documentation

For comprehensive information:

- **Quick reference:** `SKILL.md` (you are here)
- **Complete guide:** `guide.md` (407 lines, all scenarios)
- **Real example:** `examples/pr73.md` (actual cleanup of VisionPipe PR)
- **Helper script:** `git-cleanup-commits.sh` (interactive mode)

## 🆘 Emergency Recovery

If something goes wrong:

```bash
# Abort ongoing rebase
git rebase --abort

# Restore from backup
git reset --hard backup/branch-name

# Find lost commits
git reflog
git cherry-pick <commit-sha>
```

## 💡 Pro Tips

1. **One command at a time** - Wait for output before next command
2. **Verify frequently** - Run `git log --oneline main..HEAD` after each step
3. **Always backup** - Never skip creating backup branch
4. **Use --stat not --patch** - Easier to read for large changes
5. **Test first** - Practice on a test branch before real PR

## 🎓 Learn by Example

See `examples/pr73.md` for a complete walkthrough of reorganizing 6 commits into 3.

---

**Ready to use?** Just reference this skill in your prompts with Mistral Vibe!
