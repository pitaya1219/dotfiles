---
name: logseq-write
description: Append content to a Logseq page (or create a new page) via HTTP API, with optional Markdown-to-blocks conversion
user-invocable: true
version: 4.0.0
---

Append content to a Logseq page, or create a new page with properties.

All config resolution, Markdown-to-block conversion, Nextcloud asset uploads,
and Logseq API calls are handled by the bundled `logseq_write.py` script —
do not hand-write curl/jq for this skill. The script is the single source of
truth for this logic; if something about the API call sequence seems
ambiguous, read the script rather than improvising shell around it.

`$ARGUMENTS` format: `<page> [--format markdown|logseq] [--title "..."] [--tag tag-name] [--create-page] [--prop key=value]... [--asset path[:name]]...`

- `page` — Logseq page name (e.g. `2026-06-08` for today's journal, or `Session/2026-06-08 fix-bug` for a new page)
- `--format` — `markdown` (default) converts Markdown; `logseq` uses native outline as-is (2-space indent = 1 level)
- `--title` — parent block heading; all content becomes its children (append mode only)
- `--tag` — adds `tags:: #<tag>` property on the title block (requires `--title`, append mode only)
- `--create-page` — create a new page instead of appending to an existing one; `<page>` becomes the page title
- `--prop key=value` — set a page property (repeatable, requires `--create-page`)
- `--asset path[:name]` — upload a local file to Nextcloud and append a link block to the content (repeatable). Optional `:name` overrides the on-disk filename (defaults to the source basename). Image extensions render inline (`![]`), everything else as a download link (`[]`). Linked via Nextcloud's internal (login-required) URL.

## Usage

Write the content to append (Markdown or native Logseq outline, per
`--format`) to the script's stdin via a heredoc, and pass the flags above
straight through:

```bash
python3 "$HOME/.agent/skills/logseq-write/logseq_write.py" "<page>" \
  --format markdown \
  [--title "..."] [--tag tag-name] [--create-page] \
  [--prop key=value] [--prop key2=value2] \
  [--asset path[:name]] \
  <<'EOF'
<content here — the Markdown or native-outline block content>
EOF
```

`--prop` and `--asset` are each repeatable — pass one flag per value, not a
combined string.

### Markdown conversion rules (`--format markdown`, the default)

| Markdown input | Logseq block content |
|---|---|
| `# H1` | skipped — used only as page/parent title, never emitted as a block |
| `## Section` | `**Section**` — nested by heading depth |
| `### Subsection` | `**Subsection**` — child of the nearest preceding `##` |
| `- item` / `* item` | `item` — nested by list indentation, always inside the current heading context |
| `- [ ] task` | `TODO task` |
| `- [x] task` | `DONE task` |
| plain paragraph | leaf block under the current context |
| blank line | ignored |
| inline `**bold**`, `[[link]]`, `` `code` `` | passed through unchanged |

### Result

On success the script prints `Page: <name>, N block(s) inserted` and exits
0. On failure it prints the HTTP status and response body (or the specific
validation error) to stderr and exits non-zero — surface that message to the
user; do not retry blindly or fall back to hand-rolled curl.

## Config

Reads connection config from `~/.agent/logseq.json`. `url` and `token` each
accept a plain string, `{ "file": "..." }`, or `{ "command": "..." }` — the
script resolves all three forms itself. If the file is missing, it prints:

> No config at ~/.agent/logseq.json. Set dotfiles.agent.logseq in your Nix profile.

Nextcloud asset credentials (used only by `--asset`) come from `passage`
(`logseq-assets/nextcloud/...`), not from `logseq.json`.

## Availability check

To check reachability without writing anything (e.g. before deciding whether
to fall back to a local file), run:

```bash
python3 "$HOME/.agent/skills/logseq-write/logseq_write.py" --check
```

Exit 0 means Logseq is reachable; exit 1 means it isn't (including "no
config file" — that's a normal "not set up here" case, not an error to
surface). `session-save` uses this same check via the bundled
`logseq_status.py`.
