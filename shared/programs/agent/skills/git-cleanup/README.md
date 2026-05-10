# Git Cleanup Skill for Mistral Vibe

This skill helps AI agents clean up and reorganize git commits for cleaner PR history.

## Installation

This skill is already installed in your `.vibe/skills/` directory.

## Usage with Mistral Vibe

### Invoke the Skill

```bash
vibe
> /git-cleanup
```

Or reference it in your prompt:
```
Using the git-cleanup skill, help me reorganize commits in my current branch.
```

### Best Practices for Mistral Vibe

**✅ Good Approach - Explicit Step-by-Step:**

```
I need to clean up my PR commits. Please execute these commands one by one:

1. git log --oneline main..HEAD

Show me the output, then I'll tell you what to do next.
```

**After seeing output:**
```
Now execute:
git branch backup/my-feature
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main

Then show me the result with:
git log --oneline main..HEAD
```

**❌ Avoid - Too Abstract:**
```
Clean up my commits
```

### Example Session

```
You: I have 6 commits in my PR but they're messy. Help me organize them.

Mistral Vibe: Let me analyze your commits first.

You: Execute: git log --oneline main..HEAD

Mistral Vibe: [shows output]

You: I want to squash commits 2, 3, 4 into commit 1. Keep 5 and 6 separate.
     Use the git-cleanup skill commands.

Mistral Vibe: I'll create a backup and then squash commits 2-4.
              Executing:
              1. git branch backup/my-feature
              2. GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main

You: Good! Now show me the result.

Mistral Vibe: git log --oneline main..HEAD
              [shows 3 commits]

You: Perfect! Now push it.

Mistral Vibe: git push --force-with-lease origin my-feature
```

## Directory Structure

```
.vibe/skills/git-cleanup/
├── SKILL.md                    # Main skill file (user-invocable)
├── README.md                   # This file
├── QUICKSTART.md               # Quick start for Mistral Vibe
├── MISTRAL_VIBE_GUIDE.md       # ⚠️ CRITICAL: Avoiding state confusion
├── git-cleanup-commits.sh      # Interactive helper script
└── examples/
    └── pr73.md                 # Real-world example
```

## ⚠️ CRITICAL for Mistral Vibe Users

**READ THIS FIRST:** `MISTRAL_VIBE_GUIDE.md`

Common problem: AI agents plan based on initial commit count, but commit positions change after each operation.

**Example of what goes wrong:**
```
Initial: 6 commits
Plan: "Squash 2-4, then edit 5"
After squash: 3 commits (positions changed!)
Try to edit 5: ERROR - only 3 commits exist now
```

**Solution:** Read `MISTRAL_VIBE_GUIDE.md` for proper state tracking.

## Files

### SKILL.md
- Quick reference for AI agents
- Common scenarios with commands
- sed pattern examples
- Safety checklists
- ⚠️ State tracking warnings

### MISTRAL_VIBE_GUIDE.md (NEW)
- Complete walkthrough for Mistral Vibe
- Avoiding state confusion
- Checkpoint system
- Real execution examples

### git-cleanup-commits.sh
- Interactive helper for humans
- Automatic backup creation
- Guided cleanup workflows

### examples/pr73.md
- Real-world example from VisionPipe
- Shows actual cleanup of 6 commits → 3 commits
- Step-by-step execution log

## Quick Command Reference

### Analyze
```bash
git log --oneline main..HEAD
git log --stat main..HEAD
```

### Backup
```bash
git branch backup/$(git rev-parse --abbrev-ref HEAD)
```

### Squash All
```bash
GIT_SEQUENCE_EDITOR="sed -i '2,$s/^pick/fixup/'" git rebase -i main
```

### Squash Specific Range (commits 2-4)
```bash
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i main
```

### Remove File from Last Commit
```bash
git reset --soft HEAD~1
git reset HEAD unwanted.log
git commit -C ORIG_HEAD
```

### Split Last Commit
```bash
git reset --soft HEAD~1
git reset HEAD file-to-separate.kt
git commit -m "First part"
git add file-to-separate.kt
git commit -m "Second part"
```

### Push Changes
```bash
git push --force-with-lease origin branch-name
```

## Integration with Other Tools

### Use with Helper Script

For complex cleanups, use the interactive script:

```bash
~/.vibe/skills/git-cleanup/git-cleanup-commits.sh
```

Or from any git repository:

```bash
$HOME/.vibe/skills/git-cleanup/git-cleanup-commits.sh squash-all
```

### Use in Prompts

```bash
# From project root
cd .vibe/prompts
cat project-rules.md

# Add reference:
"When cleaning up commits, follow the procedures in
.vibe/skills/git-cleanup/SKILL.md"
```

## Troubleshooting

### "Not a git repository"
Make sure you're in a git repository:
```bash
git rev-parse --git-dir
```

### "Uncommitted changes"
Commit or stash your changes first:
```bash
git stash
# or
git add . && git commit -m "WIP"
```

### "Rebase failed"
Abort and restore from backup:
```bash
git rebase --abort
git reset --hard backup/branch-name
```

### "Lost commits"
Use reflog to find them:
```bash
git reflog
git reset --hard HEAD@{N}
```

## Safety Features

1. **Always creates backup branch** before any operation
2. **Uses --force-with-lease** instead of --force for safer pushes
3. **Verifies clean working directory** before starting
4. **Shows diff before and after** for verification

## Contributing

To improve this skill:

1. Edit files in `.agent/skills/git-cleanup/` (canonical location; `.vibe/skills` and `.claude/skills` are directory-level symlinks to `.agent/skills`)
2. Test your changes on a test repository
3. Update version in SKILL.md frontmatter
4. Document changes in this README

## Support

For issues or questions:
- Read `SKILL.md` for comprehensive documentation
- Read `MISTRAL_VIBE_GUIDE.md` for state tracking details
- Check `examples/pr73.md` for a real-world example
- Use the helper script's interactive mode

---

**Version:** 1.0.0
**Last Updated:** 2026-02-20
