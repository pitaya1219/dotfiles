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

> Gotcha: this query can return messages that don't actually contain the mention token — e.g. context messages surrounding a real hit, including ones authored by the user themself. Before attributing a result to "X mentioned you", check that `<@<user_id>>` literally appears in its `Text`. If it doesn't, label it by what it actually is (e.g. "your own message in #channel") rather than as a mention.

For each result, summarize the actual message content per channel — who said what, not just a channel name and a count. "Note channels active in" is not enough on its own; write one line per distinct message (or thread) covering the substance (e.g. "10:48 <name> — invite email never arrived for <person>"), grouping consecutive messages in the same channel as sub-bullets. If a message is truncated in the search result, summarize what's visible rather than guessing the rest.
