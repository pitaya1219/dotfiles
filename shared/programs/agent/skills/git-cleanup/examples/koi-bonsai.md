# Example: homelab PR #170 — Squash, Then Split Back Apart

A real cleanup that started by squashing everything (the easy default), got
corrected by the user, and along the way hit a fixup off-by-one that had to
be caught and fixed. Also covers rewriting commit authors.

## Original State

4 commits on `feat/bonsai-27b-vision-model`, built up iteratively while
bringing up a new Ansible role and debugging it live against real hardware:

```
ba74512 fix: Don't let PowerShell treat llama-server's stderr as a terminating error
71595a3 fix: Open Windows Firewall for the llama-server port
5e1feea fix: Serve koi's llama-server on port 11434
ee8aa31 feat: Add llama_cpp_model role to serve Bonsai 27B on koi
```

The 3 "fix" commits weren't fixing a pre-existing bug — they were found
while first testing code introduced *in this same PR*. That similarity made
"just squash it all into one commit" look like the obvious move.

## First Attempt: Squash Everything (Wrong Call)

```bash
git branch backup/feat-bonsai-27b-vision-model
git reset --soft main
git commit -m "feat: Add llama_cpp_model role to serve Bonsai 27B on koi

Adds an infra/roles/llama_cpp_model Ansible role that downloads ...
...
Also opens the Windows Firewall for the server port (otherwise LAN
connections silently time out instead of being refused), and avoids
setting \$ErrorActionPreference = \"Stop\" in the launch script — Windows
PowerShell 5.1 treats llama-server's normal INFO/WARNING stderr output
as a terminating NativeCommandError under that setting ..."
```

This produced one commit with an "Also ..." paragraph bundling two
*unrelated, independently-diagnosed* bugs into the feature commit's message.
The user caught it:

> こういうcommitの整理の仕方、skillに反映できる？
> ("also" とかメッセージに入ってるとコミット分割したほうがいいのではって思うけど)

The tell: **"Also" in a commit message is a signal the commit is doing more
than one thing.** The firewall fix and the PowerShell fix each had their own
symptom → root-cause investigation (reproduced independently via ad-hoc WinRM
commands against the real host) — that's exactly the case the heuristic in
this skill's main doc calls out as worth its own commit.

## Second Attempt: Split Correctly

Goal: 3 commits — base feature (with the trivial port tweak folded in), then
the two root-caused fixes kept separate.

```bash
# Reset back to the original 4 commits
git reset --hard backup/feat-bonsai-27b-vision-model

# Print the REBASE TODO order (oldest-first) before writing any sed target —
# git log --oneline is newest-first, the rebase todo is the opposite
git log --oneline --reverse main..HEAD | nl
#      1  ee8aa31 feat: Add llama_cpp_model role to serve Bonsai 27B on koi
#      2  5e1feea fix: Serve koi's llama-server on port 11434
#      3  71595a3 fix: Open Windows Firewall for the llama-server port
#      4  ba74512 fix: Don't let PowerShell treat llama-server's stderr ...
```

The port commit (line 2) is a trivial one-line config value — no root cause,
just "the user asked for 11434 instead of the default." Fold it into the
base feature commit. The firewall and PowerShell fixes (lines 3, 4) each
have an independent story — keep them separate.

### The off-by-one mistake

```bash
# WRONG: targeted line 3 (firewall) instead of line 2 (port)
GIT_SEQUENCE_EDITOR="sed -i '3s/^pick/fixup/'" git rebase -i main
```

This "succeeded" with no error and produced a plausible-looking 3-commit
history — the firewall commit's *content* had silently been merged into the
port commit, still titled "fix: Serve koi's llama-server on port 11434".
Caught it only by checking the diff, not the message:

```bash
git show --stat a77eacf   # the "port" commit now touches tasks/main.yml too — wrong
```

### The fix

```bash
git reset --hard backup/feat-bonsai-27b-vision-model
GIT_SEQUENCE_EDITOR="sed -i '2s/^pick/fixup/'" git rebase -i main

git log --oneline main..HEAD
# fc51009 fix: Don't let PowerShell treat llama-server's stderr as a terminating error
# 9e3997e fix: Open Windows Firewall for the llama-server port
# eace3c4 feat: Add llama_cpp_model role to serve Bonsai 27B on koi

# Verify each commit's content, not just its message
git show --stat eace3c4   # feat commit now includes the port line — correct
git show --stat 9e3997e   # firewall-only diff — correct
git show --stat fc51009   # PowerShell template-only diff — correct

# Verify total content is unchanged from the original 4-commit backup
git diff backup/feat-bonsai-27b-vision-model HEAD --stat   # empty — nothing lost
```

## Rewriting the Author

The user wanted the commits authored as `pitaya1219`, but the PR itself
(already opened via the Gitea API) to stay attributed to `claude-bot`. Only
3 commits, so `git filter-branch` was overkill for the job (and prints its
own warning telling you to prefer something else) — a rebase with `exec`
would have been the cleaner tool:

```bash
GIT_SEQUENCE_EDITOR="sed -i -E 's/^pick ([a-f0-9]+)/pick \1\nexec git commit --amend --no-edit --author=\"pitaya1219 <runningryuya@proton.me>\"/'" \
  git rebase -i main

git log main..HEAD --format='%h %an <%ae> | %s'
git diff backup/feat-bonsai-27b-vision-model HEAD --stat   # still empty
```

(What was actually run in the session was `git filter-branch --env-filter`
over `main..HEAD`, which also worked at this scale — but `exec` is the
better default going forward since it doesn't need a separate rewrite pass
and folds naturally into the same rebase that did the fixup.)

## Result

```bash
git push --force-with-lease origin feat/bonsai-27b-vision-model
```

3 clean commits, each independently reviewable and revertible:

1. `feat: Add llama_cpp_model role to serve Bonsai 27B on koi` (includes the
   port 11434 config)
2. `fix: Open Windows Firewall for the llama-server port`
3. `fix: Don't let PowerShell treat llama-server's stderr as a terminating error`

## Lessons Learned

1. **"Also" in a commit message is a code smell** — it means the commit is
   doing more than one thing. If each thing has its own root-cause story,
   split it out.
2. **Not every fix belongs in its own commit** — a one-line config value
   change has no story to tell; fold it into the base commit instead of
   leaving a noise commit.
3. **The rebase todo list is oldest-first; `git log --oneline` is
   newest-first.** Always print `git log --oneline --reverse main..HEAD | nl`
   before writing a targeted (non-range) fixup line number.
4. **A wrong fixup target doesn't error — it just silently produces the
   wrong commit.** Verify with `git show --stat <commit>` and
   `git diff backup/<branch> HEAD --stat`, not just by reading commit
   messages.
5. **Prefer `rebase -i` with `exec` over `git filter-branch`** for rewriting
   authors on a short feature branch — filter-branch itself recommends
   against its own use at this scale.
