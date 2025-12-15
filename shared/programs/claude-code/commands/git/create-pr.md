---
allowed-tools: Bash(git *), Read(*), Write(*), Edit(*), Glob(*), Grep(*), TodoWrite(*), mcp__gitea__create_pull_request(*)
argument-hint: [requirement or --file <path>]
description: Create a pull request by implementing changes from scratch
---

Create a pull request by implementing requested changes from scratch, including code editing, committing, and PR creation as `claude-bot` user.

## Command Syntax

```bash
/git:create-pr [requirement]                    # Direct requirement
/git:create-pr --file <path/to/requirement.md>  # From file
/git:create-pr                                   # Interactive mode
```

## Input Patterns

### Pattern 1: Direct Requirement
```bash
/git:create-pr Add Prometheus monitoring with Grafana dashboard
```
Implement the requirement specified directly in the command.

### Pattern 2: Requirement File
```bash
/git:create-pr --file docs/requirements/monitoring.md
```
Read requirement from specified markdown file.

### Pattern 3: Interactive Mode
```bash
/git:create-pr
```
Prompt user for detailed requirements interactively.

## Execution Flow

### Phase 1: Preparation

1. **Parse Input**
   - Extract requirement from command argument, file, or interactive input
   - Confirm understanding with user

2. **Verify Environment**
   - Check current branch
   - If not on `main`, switch to `main`
   - Pull latest changes: `git pull origin main --rebase`
   - Handle rebase conflicts: abort and notify user if conflicts occur

3. **Generate Branch Name**
   - Analyze requirement and determine appropriate branch name
   - Use conventional prefixes:
     - `feat/` - New features
     - `fix/` - Bug fixes
     - `docs/` - Documentation
     - `refactor/` - Code refactoring
     - `chore/` - Maintenance tasks
   - Examples:
     - `feat/add-prometheus-monitoring`
     - `fix/cors-headers-in-gateway`
     - `docs/update-deployment-guide`

4. **Create Branch**
   ```bash
   git checkout -b {generated-branch-name}
   ```
   Confirm branch creation to user.

### Phase 2: Implementation

1. **Analyze Requirements**
   - Break down requirements into implementation steps
   - Use TodoWrite tool to track progress
   - Identify files to create/modify

2. **Implement Changes**
   - Follow project conventions (check CLAUDE.md, README.md)
   - Edit existing files
   - Create new files
   - Modify configurations
   - Update documentation as needed

3. **Verify Changes**
   - Review changes for completeness
   - Ensure consistency with existing codebase
   - Check for common issues

### Phase 3: Commit

**Strategy:** Create multiple logical commits, grouped by feature/component (Pattern A)

**Commit Guidelines:**
- Use conventional commit format: `<type>: <description>.`
- NEVER include AI or Claude Code references in commit messages
- Start description with lowercase
- End with period
- Be descriptive and concise

**Example Commit Sequence:**
```bash
# Feature implementation
git add prometheus/config.yml
git commit -m "feat: Add Prometheus server configuration."

git add grafana/dashboards/
git commit -m "feat: Add Grafana monitoring dashboard."

git add docker-compose.yml
git commit -m "chore: Add Prometheus and Grafana services to compose."

# Documentation
git add README.md docs/monitoring.md
git commit -m "docs: Add monitoring setup instructions."
```

**Commit Grouping Rules:**
- Group by feature/component (preferred)
- Each commit should be self-contained
- Order by dependency when applicable
- Separate infrastructure, implementation, and documentation commits

### Phase 4: Push

```bash
git push -u origin {branch-name}
```

Confirm push success before proceeding to PR creation.

### Phase 5: PR Creation

**Use Gitea MCP Server** (`mcp__gitea__create_pull_request`) as `claude-bot` user.

**PR Components:**

1. **Title**
   - Clear, action-oriented summary
   - Include conventional commit type prefix
   - Example: `feat: Add Prometheus and Grafana monitoring stack`

2. **Description**
   ```markdown
   ## Summary

   Brief overview of changes (2-3 sentences explaining what and why).

   ## Changes

   - **Component 1** (`path/to/files`) - Description of changes
   - **Component 2** (`path/to/files`) - Description of changes
   - **Configuration** - Configuration changes made
   - **Documentation** - Documentation updates

   ## Implementation Details

   Key technical decisions, approaches used, and rationale for major choices.

   ## Test Plan

   - [ ] Test step 1
   - [ ] Test step 2
   - [ ] Verify behavior 3
   - [ ] Manual verification steps

   ## Related Issues

   Closes #123 (if applicable)
   ```

3. **Parameters**
   ```
   owner: "pitaya1219"
   repo: "homelab"
   title: Generated PR title
   body: Generated PR description
   head: branch-name
   base: "main"
   ```

### Phase 6: Completion

1. Display PR URL to user
2. Summarize implemented changes
3. Provide next steps:
   ```
   ✅ PR #X created: https://git.pitaya.f5.si/pitaya1219/homelab/pulls/X

   Summary:
   - Implemented: [brief summary]
   - Files changed: X files
   - Commits: Y commits

   Next: Review and merge when ready
   ```

## Error Handling

### Implementation Error Flow

If an error occurs during implementation (Phase 2-4):

#### Step 1: Rename Branch
```bash
git branch -m error/{original-branch-name}
```
Example: `feat/add-monitoring` → `error/add-monitoring`

#### Step 2: Create ERROR.md
Generate comprehensive error report in project root:

```markdown
# Implementation Error Report

**Branch:** error/{branch-name}
**Original Branch:** {original-branch-name}
**Timestamp:** {ISO 8601 timestamp}
**Original Requirement:**

{Full text of user requirement}

## Error Summary

Brief, non-technical summary of what went wrong.

## Error Details

\`\`\`
{Full error message, stack trace, or command output}
\`\`\`

## Context

- **Operation:** What was being attempted
- **Location:** Which file or component
- **State:** Current state of the implementation

## Progress Made

Successfully completed steps:

1. ✅ Step 1 description
2. ✅ Step 2 description
3. ❌ Step 3 description <- Error occurred here

## Affected Files

- `path/to/file1` - Status/description
- `path/to/file2` - Status/description

## Next Steps

Suggested approaches for resolution:

1. Manual fix suggestion 1
2. Alternative approach 2
3. Things to investigate

## Useful Commands

\`\`\`bash
# Commands for debugging/continuing work
git checkout error/{branch-name}
# ... other relevant commands
\`\`\`
```

#### Step 3: Commit Error Report
```bash
git add ERROR.md
git commit -m "chore: Add error report for failed implementation."
```

#### Step 4: Push Error Branch
```bash
git push -u origin error/{branch-name}
```

#### Step 5: Create Draft PR with Error Labels

**Use Gitea MCP Server** to create a DRAFT pull request:

**Title Format:**
```
[ERROR] {original-title}
```
Example: `[ERROR] feat: Add Redis caching layer`

**Description:**
```markdown
## ⚠️ Implementation Error

This is a **Draft PR** for a failed implementation attempt. Human intervention required.

---

{Contents of ERROR.md}

---

## Branch Information

- **Error Branch:** `error/{branch-name}`
- **Checkout:** `git checkout error/{branch-name}`

## Resolution Options

1. **Continue Implementation:** Checkout branch and complete manually
2. **Retry:** Close this PR and re-run `/create-pr` with refined requirements
3. **Investigate:** Use error details above to diagnose issue
```

**Labels:** Add `error` and `needs-manual-fix` labels if possible via MCP

**Draft Status:** Create as draft PR (if MCP supports draft flag)

#### Step 6: Return to Main
```bash
git checkout main
```

#### Step 7: Notify User
```
❌ Implementation failed. Draft PR created for review.

Error Summary: {brief error description}

Draft PR: https://git.pitaya.f5.si/pitaya1219/homelab/pulls/X
Branch: error/{branch-name}

You can:
1. Review the error details in the PR description
2. Checkout the branch to continue manually: git checkout error/{branch-name}
3. Refine requirements and retry with /create-pr
```

### Other Errors

**Main Branch Not Up-to-Date:**
- Automatically run: `git pull origin main --rebase`
- If conflicts: abort rebase and inform user to resolve manually

**Push Rejected:**
- Check for force-push protection
- Inform user and provide resolution steps

**MCP API Errors:**
- Check token validity and permissions
- Provide clear error message and resolution steps

## Best Practices

### Branch Naming
- Keep concise but descriptive (max ~50 chars)
- Use kebab-case for readability
- Include context: `feat/add-redis-caching` not just `redis`

### Commit Strategy
- **Multiple commits preferred** over single monolithic commit
- Group by feature/component (Pattern A)
- Typical sequence:
  1. Dependencies/infrastructure
  2. Core implementation
  3. Configuration
  4. Documentation
- Each commit should pass tests if possible

### PR Quality
- Clear, specific title
- Comprehensive description with rationale
- Actionable test plan
- Link related issues/PRs

### Code Quality
- Follow project conventions and style
- Maintain consistency with existing code
- Add comments for complex logic
- Update all relevant documentation

### Communication
- Use TodoWrite tool to track implementation progress
- Keep user informed at key milestones
- Provide clear next steps upon completion

## Implementation Notes

### MCP Integration

**Check MCP Server Availability:**
```
Available MCP servers: gitea
Required functions:
- mcp__gitea__create_pull_request
- mcp__gitea__add_issue_labels (optional, for error labels)
```

**Authentication:**
- Uses `claude-bot` credentials via GITEA_ACCESS_TOKEN
- Loaded from .envrc via direnv

### Git Configuration

**Assumed Setup:**
- Repository: `pitaya1219/homelab`
- Main branch: `main`
- Remote: `origin`
- Git user configured properly for commits

### File Operations

**Always Use Appropriate Tools:**
- Read: `Read` tool
- Edit: `Edit` tool
- Write: `Write` tool (for new files)
- Never use bash commands for file operations

## Example Scenarios

### Scenario 1: Simple Feature Addition

**Command:**
```
/git:create-pr Add Redis service with connection pooling to docker-compose
```

**Execution:**
1. Generate branch: `feat/add-redis-service`
2. Create `apps/cache/redis/docker-compose.yml`
3. Update main `docker-compose.yml` to include Redis
4. Add `.env` example for Redis configuration
5. Update `README.md` with Redis setup instructions
6. Commits:
   - `feat: Add Redis service configuration.`
   - `chore: Integrate Redis into main compose file.`
   - `docs: Add Redis setup instructions.`
7. Push and create PR

### Scenario 2: From Requirement File

**Command:**
```
/git:create-pr --file docs/requirements/monitoring-stack.md
```

**File Content:**
```markdown
# Monitoring Stack Requirements

## Overview
Add comprehensive monitoring with Prometheus, Grafana, and Alertmanager.

## Components
- Prometheus for metrics collection
- Grafana for visualization
- Alertmanager for notifications
- Node exporter for system metrics

## Configuration
- Prometheus scrape interval: 15s
- Grafana admin configured via environment
- Alert rules for disk space and CPU usage
```

**Execution:**
1. Read and parse requirements file
2. Generate branch: `feat/add-monitoring-stack`
3. Implement all components
4. Create multiple logical commits
5. Generate comprehensive PR description

### Scenario 3: Interactive Mode

**Command:**
```
/git:create-pr
```

**Interaction:**
```
Assistant: I'll help you create a PR. What would you like to implement?

User: I need to add CORS headers to the nginx gateway for the API endpoints