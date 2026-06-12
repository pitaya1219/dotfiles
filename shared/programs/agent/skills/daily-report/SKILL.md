---
name: daily-report
description: Generate a personal daily activity report from configured sources (GitHub, Slack, Asana, session directories)
user-invocable: true
version: 3.0.0
---

Generate a daily activity report by reading `~/.agent/daily-report.json` to determine which sources to collect from. Paths below (`scripts/`, `references/`, `assets/`) are relative to this skill's own directory.

## Step 1: Load Config

```bash
cat ~/.agent/daily-report.json
```

If the file does not exist, print an error and stop:
> No config found at ~/.agent/daily-report.json. Set dotfiles.agent.dailyReport in your Nix profile.

Today's date: run `date +%Y-%m-%d`.

## Step 2: Collect Data

For each **enabled** source, run its collector. Skip any source whose config key is absent/false.

| Source   | Enabled when                  | Collector                              |
|----------|-------------------------------|----------------------------------------|
| GitHub   | `sources.github` present      | `bash scripts/collect-github.sh`       |
| Slack    | `sources.slack` present       | follow `references/slack.md`           |
| Asana    | `sources.asana` is true       | follow `references/asana.md`           |
| Sessions | `sources.sessions.dir` present| `bash scripts/collect-sessions.sh`     |

## Step 3: Output

Fill in the skeleton at `assets/report-template.md`. Omit sections for sources that were not collected.

## Step 4: Save

### Local (`output.local`)

If `output.local` is present in config (or `output` key is absent entirely):

```bash
LOCAL_DIR=$(cat ~/.agent/daily-report.json | jq -r '.output.local.dir // "~/agent-sessions"' | sed "s|~|$HOME|")
```

Save the report to `$LOCAL_DIR/daily-YYYY-MM-DD.md`.
If `$ARGUMENTS` is provided, use that path instead.

### Logseq (`output.logseq`)

If `output.logseq` is present and truthy in config, invoke the **logseq-write** skill with:
- **Page**: today's date (e.g. `2026-06-08`)
- **Format**: `markdown`
- **Title**: `Daily Report — YYYY-MM-DD`
- **Tag**: `daily-report`
- **Content**: the report generated in Step 3

Print all saved/posted locations when done.
