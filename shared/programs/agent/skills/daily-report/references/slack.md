# Slack collector (`sources.slack`)

Feeds the report's **Slack** section (Sent / Mentioned).

Compute today's midnight Unix timestamp (used as `after`):

```bash
bash scripts/lib.sh midnight_ts
```

> Gotcha: pass this Unix timestamp as the `after` parameter. Do NOT put `after:<date>` in the query string — it silently fails for non-current years.

Use `mcp__claude_ai_Slack__slack_search_public_and_private`:

**Sent messages**
- `query`: `from:<@<sources.slack.user_id>>`
- `after`: the timestamp above
- `limit`: 20, `sort`: `timestamp`

**Mentions**
- `query`: `<@<sources.slack.user_id>>`
- `after`: the timestamp above
- `limit`: 20

Note channels active in and key topics discussed.
