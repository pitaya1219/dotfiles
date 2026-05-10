# Complete Guide for Mistral Vibe: Avoiding State Confusion

## The Problem

When cleaning up commits, **the commit positions change after each operation**.

**Example that goes wrong:**

```
Initial: 6 commits
Plan: "Squash 2-4, keep 5-6 separate" → 3 commits

❌ Wrong execution:
1. Squash commits 2-4 (now have 3 commits)
2. Try to "edit commit 5" → ERROR! Only 3 commits exist now
3. Result: Confusion and wrong final state
```

## The Solution

**Re-verify state after EVERY operation.**

## Complete Example: 6 Commits → 3 Commits

### Initial State

```bash
git log --oneline main..HEAD
```

Output:
```
commit6 fix: Display all processing items in queue UI
commit5 feat: Add dynamic memory-based concurrency control
commit4 fix: Start multiple jobs in single startProcessing call
commit3 fix: Address critical bugs in queue-level parallelism
commit2 test: Fix ImageQueueManagerTest
commit1 feat: Implement queue-level parallelism
```

**Count: 6 commits**

### Goal

- Commit 1: Core + fixes (merge 1,2,3,4)
- Commit 2: Memory feature (keep 5)
- Commit 3: UI fix (keep 6)

**Target: 3 commits**

### Step-by-Step Execution

#### Step 1: Initial Analysis

**Prompt to Mistral Vibe:**
```
Show me current commits and count:

git log --oneline main..HEAD
echo "Count:"
git log --oneline main..HEAD | wc -l
```

**Expected output:**
```
[6 commits shown]
Count: 6
```

#### Step 2: Create Backup

**Prompt:**
```
Create backup:

git branch backup/my-feature
```

**Verify:**
```
git branch | grep backup
```

#### Step 3: First Operation - Squash Commits 2-4 into 1

**Prompt:**
```
Squash commits 2, 3, 4 into commit 1.

Current count: 6 commits
After this: Should have 4 commits (1+2-4 merged, 5, 6)

Execute:
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main
```

**After execution, IMMEDIATELY verify:**
```
git log --oneline main..HEAD
echo "New count:"
git log --oneline main..HEAD | wc -l
```

**Expected output:**
```
[4 commits - positions are NOW: 1, 2, 3, 4]
New count: 4
```

**CRITICAL**: The old commit 5 is NOW at position 2!

#### Step 4: Verify New State

**Current state after squash:**
```
Position 1: feat: Core (includes fixes 2,3,4)  ← Was 1, still 1
Position 2: feat: Memory                        ← Was 5, NOW 2 ⚠️
Position 3: fix: UI                             ← Was 6, NOW 3 ⚠️
```

**Count: 4 commits (not 6!)**

#### Step 5: Check If We Need More Operations

**Original goal:** 3 commits
**Current state:** 4 commits

**Problem?** We have 4 commits but want 3.

**Wait!** Let's re-verify the actual state:

**Prompt:**
```
Show me the current commits to see what we actually have:

git log --oneline main..HEAD
```

**Analyze the output:**
- If we have 3 commits: ✅ Done!
- If we have 4 commits: Need one more operation

**In our case (if we squashed correctly), we should have 3 commits:**
```
commit_c fix: Display all processing items in queue UI
commit_b feat: Add dynamic memory-based concurrency control
commit_a feat: Implement queue-level parallelism (with fixes)
```

#### Step 6: Final Verification

**Prompt:**
```
Verify final state:

echo "Final commits:"
git log --oneline main..HEAD
echo "Final count:"
git log --oneline main..HEAD | wc -l
echo "Expected: 3"
```

**Expected:**
```
Final count: 3
Expected: 3
✓ Matches!
```

#### Step 7: Push (if verified)

**Only if count matches target:**

```
git push --force-with-lease origin my-feature
```

## Common Mistake Pattern

### ❌ Wrong Approach

```
User: "Squash commits 2-4, then split commit 5"

Mistral Vibe executes:
1. Squash 2-4 → Now have 4 commits
2. Try to split "commit 5" → ERROR! Only 4 commits exist
   (Old commit 5 is now at position 2)
```

### ✅ Correct Approach

```
User: "Squash commits 2-4, then verify the new count,
      then split the second-to-last commit"

Mistral Vibe executes:
1. Squash 2-4
2. Count commits → 4 commits (verified)
3. Identify "second-to-last" = position 3 (in current state)
4. Split position 3

Or better, use relative positions:
"Split the commit before the last one" → HEAD~1
```

## Template for Mistral Vibe

### Safe Execution Template

```
INITIAL STATE:
Execute: git log --oneline main..HEAD | wc -l
Note count: [X] commits

OPERATION 1:
Execute: [command]
Verify: git log --oneline main..HEAD | wc -l
Expected: [Y] commits
Actual: [verify matches]

OPERATION 2 (if needed):
Execute: [command based on CURRENT count Y, not original X]
Verify: git log --oneline main..HEAD | wc -l
Expected: [Z] commits
Actual: [verify matches]

FINAL:
Execute: git log --oneline main..HEAD
Verify final count matches target
```

## Using Relative References

**Instead of positions, use relative references:**

```bash
# ✅ Good - relative to HEAD
git reset --soft HEAD~1          # Last commit
git reset --soft HEAD~2          # Second-to-last commit

# ✅ Good - describe by content
git log --oneline main..HEAD | grep "Memory"  # Find the commit
git rebase -i <hash>^            # Rebase from that point

# ❌ Bad - absolute positions after state change
git rebase -i main               # Then use "position 5"
# Position 5 might not exist anymore!
```

## Checkpoint System

**After each operation, create a checkpoint:**

```bash
# After operation
CHECKPOINT=$(git rev-parse HEAD)
git log --oneline main..HEAD | wc -l

# If something goes wrong
git reset --hard $CHECKPOINT
```

## Example Session with Mistral Vibe

```
You: I have 6 commits. I want to squash commits 2-4 into commit 1,
     keep commit 5 as-is, and keep commit 6 as-is.
     This should give me 3 commits total.

Mistral Vibe: I'll help you with that. Let me start by verifying
              the current state.

              Executing:
              git log --oneline main..HEAD | wc -l

              Result: 6 commits

              Creating backup:
              git branch backup/my-feature

You: Good. Now proceed with squashing.

Mistral Vibe: I'll squash commits 2, 3, 4 into commit 1.

              Executing:
              GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main

              Verifying new state:
              git log --oneline main..HEAD | wc -l

              Result: 4 commits ⚠️

You: Wait, why 4 commits? We should have 3.

Mistral Vibe: Let me check the commits:
              git log --oneline main..HEAD

              [Shows 4 commits]

              I see the issue. After squashing 2-4, we have:
              - 1 (merged)
              - 2 (was originally 5)
              - 3 (was originally 6)

              But I may have made an error in the sed pattern.
              Let me check what happened.

You: Actually, show me the actual commit messages.

Mistral Vibe: git log --oneline main..HEAD

              Output:
              abc123 fix: Display all processing items
              def456 feat: Add memory-based concurrency
              ghi789 fix: Start multiple jobs            ← This shouldn't be here
              jkl012 feat: Implement queue-level (+ fixes)

              I see - commit "Start multiple jobs" wasn't squashed.
              The sed pattern was wrong.

You: Let's restore and try again.

Mistral Vibe: Restoring from backup:
              git reset --hard backup/my-feature

              [Start over with correct pattern]
```

## Key Principles for Mistral Vibe

1. **Count after every operation**
2. **Use current positions, not original**
3. **Verify expected vs actual**
4. **Use relative references when possible**
5. **Create checkpoints**
6. **Show full log, not just count**

---

**Use this guide to ensure successful commit cleanup with Mistral Vibe!**
