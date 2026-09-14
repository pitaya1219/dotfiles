---
name: daily-report
description: Generate a personal daily activity report from configured sources (GitHub, Slack, Asana, session directories)
user-invocable: true
version: 3.2.0
---

Generate a daily activity report by reading `~/.agent/daily-report.json` to determine which sources to collect from. Paths below (`scripts/`, `references/`, `assets/`) are relative to this skill's own directory.

## Step 1: Load Config

```bash
cat ~/.agent/daily-report.json
```

If the file does not exist, print an error and stop:
> No config found at ~/.agent/daily-report.json. Set dotfiles.agent.dailyReport in your Nix profile.

**Report date.** `$ARGUMENTS` is an optional `YYYY-MM-DD` naming the day to report on; with no argument the report covers today. Export it before running anything, so every collector and every date filter below lands on the same day:

```bash
export DAILY_REPORT_DATE="$ARGUMENTS"   # empty is fine — that means today
REPORT_DATE=$(bash scripts/lib.sh report_date) || exit 1
```

`<report-date>` below means that value.

## Step 2: Collect Data

For each **enabled** source, run its collector. Skip any source whose config key is absent/false.

| Source          | Enabled when                   | Collector                                      |
|-----------------|--------------------------------|------------------------------------------------|
| GitHub          | `sources.github` present       | `bash scripts/collect-github.sh`               |
| Slack           | `sources.slack` present        | follow `references/slack.md`                   |
| Asana           | `sources.asana` is true        | follow `references/asana.md`                   |
| Sessions (local) | `sources.sessions.dir` present | `bash scripts/collect-sessions.sh`             |
| Sessions (Logseq)| `sources.logseq` is true       | `bash scripts/collect-logseq-sessions.sh`      |

**Sessions collection note:**
`collect-sessions.sh` lists local session directories whose mtime falls on the report date (requires `sources.sessions.dir`).
`collect-logseq-sessions.sh` queries Logseq for `Session/*` pages whose `date::` property is the report date (requires `sources.logseq = true`); exits silently if `~/.agent/logseq.json` is absent or Logseq is unreachable.
When both produce output, **prefer the Logseq data** for the session summary (it contains the full narrative written by `session-save`); use the local directory listing only to note any sessions not yet saved to Logseq.

**Past dates:** the collectors bound the day in local time, so they return that day rather than everything since. Two sources still degrade with distance:
- GitHub's events feed reaches back ~90 days and ~300 events, whichever ends first — an empty result for an older date is a retention limit, not a quiet day. Say so in the report rather than reporting no activity.
- Session directory mtimes drift if a directory is touched after the fact, so a past date can both miss and invent entries. Logseq's `date::` is the reliable side.

## Step 3: Output

Fill in the skeleton at `assets/report-template.md`. Omit sections for sources that were not collected.

## Step 4: Save

### Local (`output.local`)

If `output.local` is present in config (or `output` key is absent entirely):

```bash
LOCAL_DIR=$(cat ~/.agent/daily-report.json | jq -r '.output.local.dir // "~/agent-sessions"' | sed "s|~|$HOME|")
```

Save the report to `$LOCAL_DIR/daily-<report-date>.md`.

### Logseq (`output.logseq`)

If `output.logseq` is present and truthy in config, invoke the **logseq-write** skill with:
- **Page**: the report date (e.g. `2026-06-08`)
- **Format**: `markdown`
- **Title**: `Daily Report — <report-date>`
- **Tag**: `daily-report`
- **Content**: the report generated in Step 3

Print all saved/posted locations when done.
