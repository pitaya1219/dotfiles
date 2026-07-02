---
name: update-neovim-plugins
description: Check for updates to custom Neovim plugins in plugins.nix and create individual PRs for each updated plugin.
user-invocable: true
autonomous: false
---

# Neovim Custom Plugin Auto-Update Workflow

This skill automates the process of checking for updates to custom Neovim plugins defined in `shared/programs/neovim/plugins.nix` and creating individual PRs for each plugin that has a new commit available.

## Overview

The workflow:
1. Parses the `customPlugins` list from `shared/programs/neovim/plugins.nix`
2. For each plugin, checks if a newer commit exists on its tracking branch
3. Computes the new sha256 hash for the updated plugin
4. Updates the plugin entry in `plugins.nix`
5. Creates a feature branch and PR for each updated plugin
6. Outputs a summary of all updates performed

## Prerequisites

- GitHub API access (for fetching latest commit SHAs)
- `nix-prefetch-url` available in PATH, or `nix develop -c nix-prefetch-url`
- Gitea MCP tool access (`mcp__gitea__pull_request_write`)
- Repository: `pitaya1219/dotfiles` at `git.pitaya.f5.si`

## Step 0: Setup and Configuration

Set the working directory:
```bash
cd /home/lepetitprince/agent-sessions/vibe-subagents/session-issue-179
```

Ensure you're on the main branch with a clean working tree:
```bash
git checkout main
git pull origin main
git status
```

Set environment variables for GitHub API (if needed):
```bash
GITHUB_TOKEN="$(pass show otp/github.com | head -1)"  # Or use your preferred method
export GITHUB_TOKEN
```

## Step 1: Parse plugins.nix

Read the current `customPlugins` list from `shared/programs/neovim/plugins.nix`:

```bash
PLUGINS_FILE="shared/programs/neovim/plugins.nix"
cat "$PLUGINS_FILE"
```

Extract the plugin information (name, owner, repo, rev, sha256) into a structured format. Identify:
- **SHA-pinned plugins**: `rev` is a 40-character commit SHA (e.g., `d5c4816717e5136278a9148bd19268fcaf514fe9`)
- **Branch-tracking plugins**: `rev` is a branch name (e.g., `master`, `main`, `develop`)

Current plugins (as of this skill creation):
| Name | Owner | Repo | Rev | SHA Format |
|------|-------|------|-----|------------|
| aquarium-vim | FrenzyExists | aquarium-vim | SHA | base32 |
| base2tone-nvim | atelierbram | Base2Tone-nvim | SHA | base32 |
| evangelion | xero | evangelion.nvim | SHA | base32 |
| burgundy | elliothatch | burgundy.vim | master | base32 |
| nvim-colorizer | norcalli | nvim-colorizer.lua | master | base32 |
| spaceduck | spaceduck-theme | nvim | master | base32 |
| oldworld-nvim | dgox16 | oldworld.nvim | main | SRI |

## Step 2: Process Each Plugin

For each plugin in `customPlugins`, follow these sub-steps:

### Step 2a: Determine the branch to check

For each plugin:
- If `rev` is a branch name (master/main/develop/etc): use that branch
- If `rev` is a SHA: first get the plugin's default branch from GitHub API, then use that

```bash
# For a given plugin with owner, repo, and rev:
if [[ "$rev" =~ ^[0-9a-f]{40}$ ]]; then
  # rev is a SHA - get the default branch
  DEFAULT_BRANCH=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/${owner}/${repo}" | \
    jq -r '.default_branch')
  BRANCH_TO_CHECK="$DEFAULT_BRANCH"
else
  # rev is a branch name
  BRANCH_TO_CHECK="$rev"
fi
```

### Step 2b: Get the latest commit SHA

Use the GitHub API to fetch the latest commit SHA for the determined branch:

```bash
LATEST_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/${owner}/${repo}/commits/${BRANCH_TO_CHECK}" | \
  jq -r '.sha')
```

If the API rate limit is hit (403 error), try without authentication:
```bash
LATEST_SHA=$(curl -s "https://api.github.com/repos/${owner}/${repo}/commits/${BRANCH_TO_CHECK}" | \
  jq -r '.sha')
```

### Step 2c: Compare with current rev

Compare the latest SHA with the current `rev`:

```bash
CURRENT_REV="$rev"

# If current rev is a branch name, always consider it outdated
if [[ ! "$CURRENT_REV" =~ ^[0-9a-f]{40}$ ]]; then
  NEEDS_UPDATE=true
# If current rev is a SHA, compare
elif [[ "$CURRENT_REV" != "$LATEST_SHA" ]]; then
  NEEDS_UPDATE=true
else
  NEEDS_UPDATE=false
fi
```

If `NEEDS_UPDATE` is false, skip to the next plugin.

### Step 2d: Compute new sha256

Use `nix-prefetch-url` to compute the sha256 hash. Try the following approaches in order:

**Method 1: Using nix-prefetch-url directly**
```bash
NEW_SHA256=$(nix-prefetch-url --unpack "https://github.com/${owner}/${repo}/archive/${LATEST_SHA}.tar.gz" 2>/dev/null)
```

**Method 2: Using nix-prefetch-url with nix develop**
```bash
NEW_SHA256=$(nix develop -c nix-prefetch-url --unpack "https://github.com/${owner}/${repo}/archive/${LATEST_SHA}.tar.gz" 2>/dev/null)
```

**Method 3: Fallback using nix hash to-sri**
```bash
# First get the tarball
TARBALL_URL="https://github.com/${owner}/${repo}/archive/${LATEST_SHA}.tar.gz"
HASH_OUTPUT=$(nix-prefetch-fetchFromGitHub --owner "${owner}" --repo "${repo}" --rev "${LATEST_SHA}" --sha256 "0000000000000000000000000000000000000000000000000000" 2>&1 || true)
SRI_HASH=$(echo "$HASH_OUTPUT" | grep -oE 'sha256-[a-zA-Z0-9+/=]+' || true)

if [[ -n "$SRI_HASH" ]]; then
  NEW_SHA256="$SRI_HASH"
else
  # Try with nix hash to-sri
  TEMP_FILE=$(mktemp)
  curl -sL "$TARBALL_URL" -o "$TEMP_FILE"
  NEW_SHA256=$(nix hash to-sri --hash-type sha256 "$TEMP_FILE" 2>/dev/null || true)
  rm -f "$TEMP_FILE"
fi
```

**Preserve existing format:**
- If the current `sha256` uses **SRI format** (`sha256-...`), convert `NEW_SHA256` to SRI format if it isn't already
- If the current `sha256` uses **base32 format**, convert `NEW_SHA256` to base32 format

**Convert base32 to SRI:**
```bash
# If NEW_SHA256 is in base32 format (nix-prefetch-url default)
if [[ "$NEW_SHA256" =~ ^[0-9a-z]+$ && ${#NEW_SHA256} -ge 50 ]]; then
  # Convert base32 to hex, then to SRI
  BASE32_HASH="$NEW_SHA256"
  # Use nix to convert
  HEX_HASH=$(nix eval --raw "(builtins.base32ToBase16 \"${BASE32_HASH}\"):0:32" 2>/dev/null || echo "")
  if [[ -n "$HEX_HASH" ]]; then
    NEW_SHA256="sha256-$(echo -n "$HEX_HASH" | base64 -w0)"
  fi
fi
```

**Convert SRI to base32:**
```bash
# If NEW_SHA256 is in SRI format and current is base32
if [[ "$NEW_SHA256" =~ ^sha256- && "$current_sha256" !~ ^sha256- ]]; then
  # Extract base64 part
  BASE64_HASH=${NEW_SHA256#sha256-}
  # Convert to hex, then to base32
  HEX_HASH=$(echo -n "$BASE64_HASH" | base64 -d | xxd -p -c256 2>/dev/null || echo "")
  if [[ -n "$HEX_HASH" ]]; then
    NEW_SHA256=$(nix eval --raw "builtins.base16ToBase32 \"${HEX_HASH}\"" 2>/dev/null || echo "$NEW_SHA256")
  fi
fi
```

### Step 2e: Update plugins.nix

Create a backup of the original file:
```bash
cp "$PLUGINS_FILE" "${PLUGINS_FILE}.backup"
```

Use a Python or awk script to update the specific plugin entry:

```bash
# Python script to update a specific plugin
python3 << EOF
import re
import json

plugins_file = "$PLUGINS_FILE"
plugin_name = "$name"
new_rev = "$LATEST_SHA"
new_sha256 = "$NEW_SHA256"

with open(plugins_file, 'r') as f:
    content = f.read()

# Find and update the plugin entry
# Match the plugin block with name matching
pattern = rf'(\s*\{{\s*\n\s*name\s*=\s*"{plugin_name}"[^}}]*rev\s*=\s*")[^"]*("[^}]*sha256\s*=\s*")[^"]*("[^}]*\}\s*)'

def replace_plugin(match):
    prefix = match.group(1)
    middle = match.group(2)
    suffix = match.group(4)
    # Update rev and sha256
    updated = f'{prefix}{new_rev}{middle}{new_sha256}{suffix}'
    return updated

content = re.sub(pattern, replace_plugin, content)

with open(plugins_file, 'w') as f:
    f.write(content)

print(f"Updated {plugin_name} to rev={new_rev}, sha256={new_sha256}")
EOF
```

Alternatively, use a more robust approach with explicit parsing:

```bash
# Create a temporary Python script
temp_script=$(mktemp)
cat > "$temp_script" << 'PYEOF'
import sys
import re

def update_plugin(filepath, plugin_name, new_rev, new_sha256):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    in_target_plugin = False
    plugin_start = -1
    plugin_end = -1
    
    for i, line in enumerate(lines):
        if 'name = "' + plugin_name + '"' in line:
            # Find the start of this plugin entry
            for j in range(i, -1, -1):
                if '{' in lines[j] and j > 0:
                    # Check if this is a top-level brace
                    if lines[j].strip() == '{' or '{' in lines[j].split('#')[0] if '#' in lines[j] else False:
                        plugin_start = j
                        break
        if in_target_plugin and '}' in line:
            plugin_end = i
            break
    
    # Extract the plugin block
    plugin_block = ''.join(lines[plugin_start:plugin_end+1])
    
    # Update rev and sha256
    plugin_block = re.sub(
        r'(rev\s*=\s*")[^"]*(")',
        rf'\1{new_rev}\2',
        plugin_block
    )
    plugin_block = re.sub(
        r'(sha256\s*=\s*")[^"]*(")',
        rf'\1{new_sha256}\2',
        plugin_block
    )
    
    # Replace the lines
    new_lines = lines[:plugin_start] + [plugin_block] + lines[plugin_end+1:]
    
    with open(filepath, 'w') as f:
        f.writelines(new_lines)
    
    print(f"Updated {plugin_name}: rev={new_rev}, sha256={new_sha256}")

if __name__ == "__main__":
    update_plugin(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
PYEOF

python3 "$temp_script" "$PLUGINS_FILE" "$name" "$LATEST_SHA" "$NEW_SHA256"
rm "$temp_script"
```

### Step 2e (Alternative): Use sed for simpler cases

For branch-tracking plugins where we're updating from a branch name to a SHA:

```bash
# For a plugin entry, find and replace the rev and sha256 lines
sed -i "/name = \"${name}\"/,/}/ s/rev = \"[^\"]*\"/rev = \"${LATEST_SHA}\"/" "$PLUGINS_FILE"
sed -i "/name = \"${name}\"/,/}/ s/sha256 = \"[^\"]*\"/sha256 = \"${NEW_SHA256}\"/" "$PLUGINS_FILE"
```

**Verify the edit succeeded:**
```bash
# Show the updated plugin entry
grep -A 5 "name = \"${name}\"" "$PLUGINS_FILE"
```

### Step 2f: Verify Nix syntax

After each edit, verify the file is still valid Nix:

```bash
nix-instantiate --parse "$PLUGINS_FILE" 2>&1
```

If there are errors, restore from backup and try again:
```bash
cp "${PLUGINS_FILE}.backup" "$PLUGINS_FILE"
```

### Step 2g: Create feature branch and commit

Create a unique branch name for this plugin update:

```bash
SHORT_SHA="${LATEST_SHA:0:7}"
BRANCH_NAME="chore/update-${name}-${SHORT_SHA}"
git checkout -b "$BRANCH_NAME"
```

Add and commit the changes:

```bash
git add "$PLUGINS_FILE"
git commit -m "chore: Update ${name} to ${SHORT_SHA}."
```

Note: Commit messages must NOT mention AI tools. Use the format: `chore: Update <plugin-name> to <short-sha>.`

### Step 2h: Push and create PR

Push the branch to the remote:

```bash
git push origin "$BRANCH_NAME"
```

Create a PR using the Gitea MCP tool:

```bash
PR_TITLE="chore: Update ${name} to ${SHORT_SHA}"
PR_BODY="Update ${name} plugin from ${CURRENT_REV} to ${SHORT_SHA}.\n\n- Owner: ${owner}\n- Repo: ${repo}\n- Old SHA: ${CURRENT_REV}\n- New SHA: ${LATEST_SHA}\n- New sha256: ${NEW_SHA256}"

# Use Gitea MCP tool
# mcp__gitea__pull_request_write requires: title, description, base, head, draft
# For pitaya1219/dotfiles on git.pitaya.f5.si

# First, ensure we have the Gitea MCP configured
# The tool should use user's own identity (NOT bot token)
```

**MCP Tool Invocation:**
```
mcp__gitea__pull_request_write({
  "title": "$PR_TITLE",
  "description": "$PR_BODY",
  "base": "main",
  "head": "$BRANCH_NAME",
  "draft": false
})
```

If MCP is not available, use the Gitea REST API directly:

```bash
# Get the repository info
GITEA_HOST="git.pitaya.f5.si"
GITEA_OWNER="pitaya1219"
GITEA_REPO="dotfiles"

# Get the base branch SHA
BASE_SHA=$(curl -s -H "Authorization: token $GITEA_TOKEN" \
  "https://${GITEA_HOST}/api/v1/repos/${GITEA_OWNER}/${GITEA_REPO}/branches/main" | \
  jq -r '.commit.sha')

# Get the head branch SHA
HEAD_SHA=$(curl -s -H "Authorization: token $GITEA_TOKEN" \
  "https://${GITEA_HOST}/api/v1/repos/${GITEA_OWNER}/${GITEA_REPO}/branches/${BRANCH_NAME}" | \
  jq -r '.commit.sha')

# Create the PR
PR_JSON=$(jq -n \
  --arg title "$PR_TITLE" \
  --arg body "$PR_BODY" \
  --arg base "main" \
  --arg head "$BRANCH_NAME" \
  '{
    "title": $title,
    "body": $body,
    "base": $base,
    "head": $head,
    "draft": false
  }')

PR_RESPONSE=$(curl -s -X POST \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PR_JSON" \
  "https://${GITEA_HOST}/api/v1/repos/${GITEA_OWNER}/${GITEA_REPO}/pulls")

PR_NUMBER=$(echo "$PR_RESPONSE" | jq -r '.number')
echo "Created PR #${PR_NUMBER}: ${PR_TITLE}"
```

### Step 2i: Cleanup and reset

After the PR is created, return to the main branch and clean up:

```bash
git checkout main
git branch -D "$BRANCH_NAME"
# The remote branch stays for the PR
```

**Important:** Reset the plugins.nix to its original state before processing the next plugin:
```bash
cp "${PLUGINS_FILE}.backup" "$PLUGINS_FILE"
git checkout "$PLUGINS_FILE"
```

This ensures each plugin gets its own independent update and PR.

## Step 3: Process All Plugins

The main workflow loop:

```bash
# Initialize
PLUGINS_FILE="shared/programs/neovim/plugins.nix"
SKIPPED_PLUGINS=()
UPDATED_PLUGINS=()
TOTAL_PLUGINS=0
UPDATE_COUNT=0
SKIP_COUNT=0

# Get Gitea token for PR creation
GITEA_TOKEN="$(pass show otp/git.pitaya.f5.si | head -1)"  # Or use your preferred method
GITEA_HOST="git.pitaya.f5.si"
GITEA_OWNER="pitaya1219"
GITEA_REPO="dotfiles"

# Ensure we're on main with clean tree
git checkout main
git pull origin main

# Make a master backup
cp "$PLUGINS_FILE" "${PLUGINS_FILE}.master-backup"

# Extract plugins from the file
# This is a simplified parser - for production use, consider a more robust Nix parser
PLUGIN_NAMES=()
PLUGIN_OWNERS=()
PLUGIN_REPOS=()
PLUGIN_REVS=()
PLUGIN_SHA256S=()

# Parse the file using awk
# Each plugin is a block starting with { and containing name, owner, repo, rev, sha256
# This is fragile but works for the known format
awk '
BEGIN { in_plugin=0; plugin_count=0 }
/\{/ {
  if (in_plugin == 0) {
    in_plugin = 1
    plugin_count++
    plugin_name[plugin_count] = ""
    plugin_owner[plugin_count] = ""
    plugin_repo[plugin_count] = ""
    plugin_rev[plugin_count] = ""
    plugin_sha256[plugin_count] = ""
  }
}
/name = / { gsub(/.*name = "/, ""); gsub(/\"$/, ""); plugin_name[plugin_count] = $0 }
/owner = / { gsub(/.*owner = "/, ""); gsub(/\"$/, ""); plugin_owner[plugin_count] = $0 }
/repo = / { gsub(/.*repo = "/, ""); gsub(/\"$/, ""); plugin_repo[plugin_count] = $0 }
/rev = / { gsub(/.*rev = "/, ""); gsub(/\"$/, ""); plugin_rev[plugin_count] = $0 }
/sha256 = / { gsub(/.*sha256 = "/, ""); gsub(/\"$/, ""); plugin_sha256[plugin_count] = $0 }
/\}/ {
  if (in_plugin == 1) {
    in_plugin = 0
  }
}
END {
  for (i = 1; i <= plugin_count; i++) {
    print plugin_name[i] "|" plugin_owner[i] "|" plugin_repo[i] "|" plugin_rev[i] "|" plugin_sha256[i]
  }
}
' "$PLUGINS_FILE" | while IFS='|' read -r name owner repo rev sha256; do

  TOTAL_PLUGINS=$((TOTAL_PLUGINS + 1))
  echo "Processing plugin ${TOTAL_PLUGINS}: ${name}"

  # Determine branch to check
  if [[ "$rev" =~ ^[0-9a-f]{40}$ ]]; then
    echo "  Current rev is SHA: ${rev}"
    # Get default branch
    DEFAULT_BRANCH=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/${owner}/${repo}" | \
      jq -r '.default_branch' 2>/dev/null || echo "main")
    BRANCH_TO_CHECK="$DEFAULT_BRANCH"
    echo "  Checking default branch: ${BRANCH_TO_CHECK}"
  else
    echo "  Current rev is branch: ${rev}"
    BRANCH_TO_CHECK="$rev"
  fi

  # Get latest SHA
  LATEST_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/${owner}/${repo}/commits/${BRANCH_TO_CHECK}" | \
    jq -r '.sha' 2>/dev/null || echo "")

  if [[ -z "$LATEST_SHA" ]]; then
    echo "  ERROR: Could not fetch latest SHA for ${owner}/${repo}@${BRANCH_TO_CHECK}"
    SKIPPED_PLUGINS+=("${name} (API error)")
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  echo "  Latest SHA on ${BRANCH_TO_CHECK}: ${LATEST_SHA}"

  # Check if update needed
  if [[ "$rev" == "$LATEST_SHA" ]]; then
    echo "  Already up to date"
    SKIPPED_PLUGINS+=("${name}")
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Update needed
  echo "  Update needed: ${rev} -> ${LATEST_SHA}"

  # Compute new sha256
  echo "  Computing new sha256..."
  NEW_SHA256=$(nix-prefetch-url --unpack "https://github.com/${owner}/${repo}/archive/${LATEST_SHA}.tar.gz" 2>/dev/null || echo "")

  if [[ -z "$NEW_SHA256" ]]; then
    # Try with nix develop
    NEW_SHA256=$(nix develop -c nix-prefetch-url --unpack "https://github.com/${owner}/${repo}/archive/${LATEST_SHA}.tar.gz" 2>/dev/null || echo "")
  fi

  if [[ -z "$NEW_SHA256" ]]; then
    echo "  ERROR: Could not compute sha256 for ${LATEST_SHA}"
    SKIPPED_PLUGINS+=("${name} (sha256 error)")
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Check format consistency
  if [[ "$sha256" =~ ^sha256- && ! "$NEW_SHA256" =~ ^sha256- ]]; then
    # Current is SRI, new is base32 - convert
    echo "  Converting sha256 from base32 to SRI format"
    BASE32_HASH="$NEW_SHA256"
    HEX_HASH=$(nix eval --raw "(builtins.base32ToBase16 \"${BASE32_HASH}\"):0:32" 2>/dev/null || echo "")
    if [[ -n "$HEX_HASH" ]]; then
      NEW_SHA256="sha256-$(echo -n "$HEX_HASH" | base64 -w0)"
    fi
  fi

  if [[ ! "$sha256" =~ ^sha256- && "$NEW_SHA256" =~ ^sha256- ]]; then
    # Current is base32, new is SRI - convert to base32
    echo "  Converting sha256 from SRI to base32 format"
    SRI_HASH="${NEW_SHA256#sha256-}"
    HEX_HASH=$(echo -n "$SRI_HASH" | base64 -d | xxd -p -c256 2>/dev/null || echo "")
    if [[ -n "$HEX_HASH" ]]; then
      NEW_SHA256=$(nix eval --raw "builtins.base16ToBase32 \"${HEX_HASH}\"" 2>/dev/null || echo "$NEW_SHA256")
    fi
  fi

  echo "  New sha256: ${NEW_SHA256}"

  # Create backup of current state
  cp "$PLUGINS_FILE" "${PLUGINS_FILE}.backup"

  # Update the plugin entry
  # Method: Use a Python script for reliable editing
  python3 -c "
import re
import sys

filepath = sys.argv[1]
plugin_name = sys.argv[2]
new_rev = sys.argv[3]
new_sha256 = sys.argv[4]

with open(filepath, 'r') as f:
    content = f.read()

# Find the plugin block
pattern = rf'(\s*{{\s*\n\s*name\s*=\s*\"{plugin_name}\"[^}}]*?rev\s*=\s*\"[^\"]*\")[^}}]*?(sha256\s*=\s*\"[^\"]*\")[^}}]*?(\s*}})'

def replacer(match):
    prefix = match.group(1)
    sha_part = match.group(2)
    suffix = match.group(3)
    # Replace rev line
    prefix = re.sub(r'rev\s*=\s*\"[^\"]*\"', f'rev = \"{new_rev}\"', prefix)
    # Replace sha256 line
    sha_part = re.sub(r'sha256\s*=\s*\"[^\"]*\"', f'sha256 = \"{new_sha256}\"', sha_part)
    return prefix + sha_part + suffix

content = re.sub(pattern, replacer, content, flags=re.DOTALL)

with open(filepath, 'w') as f:
    f.write(content)

print('Updated successfully')
" "$PLUGINS_FILE" "$name" "$LATEST_SHA" "$NEW_SHA256"

  # Verify the change
  echo "  Verifying Nix syntax..."
  if nix-instantiate --parse "$PLUGINS_FILE" 2>&1; then
    echo "  Nix syntax OK"

    # Create branch and commit
    SHORT_SHA="${LATEST_SHA:0:7}"
    BRANCH_NAME="chore/update-${name}-${SHORT_SHA}"

    echo "  Creating branch: ${BRANCH_NAME}"
    git checkout -b "$BRANCH_NAME"

    git add "$PLUGINS_FILE"
    git commit -m "chore: Update ${name} to ${SHORT_SHA}."

    echo "  Pushing to remote..."
    git push origin "$BRANCH_NAME"

    # Create PR
    PR_TITLE="chore: Update ${name} to ${SHORT_SHA}"
    PR_BODY="Update ${name} plugin from ${rev} to ${SHORT_SHA}.\n\n- Owner: ${owner}\n- Repo: ${repo}\n- Old SHA: ${rev}\n- New SHA: ${LATEST_SHA}\n- New sha256: ${NEW_SHA256}"

    echo "  Creating PR..."
    PR_JSON=$(jq -n \
      --arg title "$PR_TITLE" \
      --arg body "$PR_BODY" \
      --arg base "main" \
      --arg head "$BRANCH_NAME" \
      '{
        "title": $title,
        "body": $body,
        "base": $base,
        "head": $head,
        "draft": false
      }')

    PR_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token $GITEA_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$PR_JSON" \
      "https://${GITEA_HOST}/api/v1/repos/${GITEA_OWNER}/${GITEA_REPO}/pulls")

    PR_NUMBER=$(echo "$PR_RESPONSE" | jq -r '.number' 2>/dev/null || echo "unknown")
    echo "  Created PR #${PR_NUMBER}: ${PR_TITLE}"

    UPDATED_PLUGINS+=("${name}: ${rev} -> ${SHORT_SHA}")
    UPDATE_COUNT=$((UPDATE_COUNT + 1))

    # Return to main and clean up
    git checkout main
    git branch -D "$BRANCH_NAME"
    git checkout "$PLUGINS_FILE"  # Reset to original

  else
    echo "  ERROR: Nix syntax error after update, restoring backup"
    cp "${PLUGINS_FILE}.backup" "$PLUGINS_FILE"
    SKIPPED_PLUGINS+=("${name} (syntax error)")
    SKIP_COUNT=$((SKIP_COUNT + 1))
  fi

  # Clean up backup
  rm -f "${PLUGINS_FILE}.backup"

  echo ""
done
```

## Step 4: Output Summary

After processing all plugins, output a comprehensive summary:

```
## Update Summary

**Repository:** pitaya1219/dotfiles
**Total Plugins Checked:** ${TOTAL_PLUGINS}
**Date:** $(date +%Y-%m-%d)

### Updated Plugins (${UPDATE_COUNT})

$(for plugin in "${UPDATED_PLUGINS[@]}"; do
  echo "- ${plugin}"
done)

### Skipped Plugins (${SKIP_COUNT})

$(for plugin in "${SKIPPED_PLUGINS[@]}"; do
  echo "- ${plugin}"
done)

### Commands Used

- GitHub API: GET https://api.github.com/repos/{owner}/{repo}/commits/{branch}
- Nix: nix-prefetch-url --unpack https://github.com/{owner}/{repo}/archive/{sha}.tar.gz
- Git: git checkout, git add, git commit, git push
- Gitea API: POST https://git.pitaya.f5.si/api/v1/repos/pitaya1219/dotfiles/pulls
```

## Error Handling

### GitHub API Rate Limits
If you hit GitHub API rate limits (403 Forbidden):
- Without authentication: 60 requests per hour per IP
- With authentication: 5000 requests per hour per token

**Solutions:**
1. Add `GITHUB_TOKEN` environment variable with a personal access token
2. Wait for the rate limit to reset (check `X-RateLimit-Reset` header)
3. Use conditional requests with `If-None-Match` header for caching

### nix-prefetch-url Not Found
If `nix-prefetch-url` is not in PATH:
1. Use `nix develop -c nix-prefetch-url` as a prefix
2. Use `nix-prefetch-fetchFromGitHub` as a fallback
3. Manually download and hash the tarball

### Gitea MCP Not Available
If the Gitea MCP tool is unavailable, use the REST API directly as shown above.

## Usage Notes

### For SHA-pinned plugins
Plugins that are already pinned to a SHA will:
1. Look up the plugin's default branch
2. Compare the current SHA with the latest commit on that branch
3. Update if different

### For branch-tracking plugins
Plugins using branch names (master/main/develop) will:
1. Use the specified branch
2. Always update to the latest commit on that branch
3. Change the `rev` field from a branch name to a SHA

### Format Preservation
The skill preserves the existing sha256 format:
- If the current sha256 uses base32 (e.g., `07z656b5ravc9k39nai6j2732d569nmd9fp3dpyqph684sqg1qx3`), the new sha256 will use base32
- If the current sha256 uses SRI format (e.g., `sha256-yO5XKSMwDu0/QYnoMbxWs+h0tfjftAYJYPrKO2XYfNQ=`), the new sha256 will use SRI format
- For new pins (branch -> SHA transitions), prefer SRI format

## Example Session

```
$ /update-neovim-plugins
Processing plugin 1: aquarium-vim
  Current rev is SHA: d5c4816717e5136278a9148bd19268fcaf514fe9
  Checking default branch: main
  Latest SHA on main: d5c4816717e5136278a9148bd19268fcaf514fe9
  Already up to date

Processing plugin 2: base2tone-nvim
  Current rev is SHA: c32c1d3dfdc8fb6e91cbf6078c078d6c3eaaa673
  Checking default branch: main
  Latest SHA on main: c32c1d3dfdc8fb6e91cbf6078c078d6c3eaaa673
  Already up to date

Processing plugin 3: burgundy
  Current rev is branch: master
  Latest SHA on master: abc123def456...
  Update needed: master -> abc123d
  Computing new sha256...
  New sha256: 0xy05k9m8xqwv3l6r0x9k2s5z7qvj9n4m2p5r8v2l3q7w
  Nix syntax OK
  Creating branch: chore/update-burgundy-abc123d
  Pushed to remote
  Created PR #123: chore: Update burgundy to abc123d

... (more plugins)

## Update Summary

**Repository:** pitaya1219/dotfiles
**Total Plugins Checked:** 7
**Date:** 2026-07-02

### Updated Plugins (2)
- burgundy: master -> abc123d
- nvim-colorizer: master -> def456a

### Skipped Plugins (5)
- aquarium-vim
- base2tone-nvim
- evangelion
- spaceduck
- oldworld-nvim
```

## Best Practices

1. **Run on a clean working tree**: Always start from main with no uncommitted changes
2. **Process one plugin at a time**: Each plugin gets its own branch and PR
3. **Preserve formats**: Maintain the existing sha256 format (base32 vs SRI)
4. **Verify Nix syntax**: Always run `nix-instantiate --parse` after edits
5. **Clean up**: Remove local branches after pushing and creating PRs
6. **Error handling**: Skip plugins with errors, don't block the entire workflow
7. **Rate limiting**: Be mindful of GitHub API rate limits

## Files Modified

- `shared/programs/neovim/plugins.nix` - Updated for each plugin

## Dependencies

- `curl` - For GitHub/Gitea API calls
- `jq` - For JSON parsing
- `nix` - For sha256 computation and Nix syntax validation
- `git` - For version control operations
- `base64`, `xxd` - For hash format conversions (optional)

---

**Version:** 1.0.0
**Created:** 2026-07-02
**Target Repository:** pitaya1219/dotfiles
