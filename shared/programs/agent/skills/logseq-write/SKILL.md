---
name: logseq-write
description: Append content to a Logseq page (or create a new page) in the Logseq DB graph, with optional Markdown-to-blocks conversion
user-invocable: true
version: 5.0.0
---

Append content to a Logseq page, or create a new page with properties.

Markdown-to-block conversion and Nextcloud asset uploads are handled by the
bundled `logseq_write.py` script, which writes through the `logseq-db` command
(the Logseq CLI underneath) — do not call the Logseq CLI by hand for this
skill. The script is the single source of
truth for this logic; if something about the API call sequence seems
ambiguous, read the script rather than improvising shell around it.

`$ARGUMENTS` format: `<page> [--format markdown|logseq] [--title "..."] [--tag tag-name] [--create-page] [--prop key=value]... [--asset path[:name]]...`

- `page` — Logseq page name (e.g. `2026-06-08` for today's journal, or `2026-06-08 fix-bug` for a new page). A DB graph page name cannot contain `/`, so there are no `Namespace/` pages
- `--format` — `markdown` (default) converts Markdown; `logseq` uses native outline as-is (2-space indent = 1 level)
- `--title` — parent block heading; all content becomes its children (append mode only)
- `--tag` — tags the title block with `#<tag>` (requires `--title`, append mode only)
- `--create-page` — create a new page instead of appending to an existing one; `<page>` becomes the page title
- `--prop key=value` — set a page property (repeatable, requires `--create-page`). Applied whether or not the page already exists, and existing properties are updated key by key rather than replaced, so re-running to flip one property (e.g. `status`) keeps the rest. `tags=#a #b` sets the page's tags; a date property takes `[[YYYY-MM-DD]]` and links the journal; any other value is matched to the graph's existing property of that name and its type.
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
| `#400` (a number after `#`, outside code) | `\#400` — still shows `#400`, but stays text instead of becoming a page "400" |

Tags and properties are metadata, never content: give them with `--tag` or
`--prop tags=…` / `--prop key=value`, and do not write `#tag` or `key:: value`
into the content to tag or describe a block.

### Result

On success the script prints `Page: <name>, N block(s) inserted` and exits
0. On failure it prints the Logseq CLI's error (or the specific validation
error) to stderr and exits non-zero — surface that message to the user; do not
retry blindly or call the CLI by hand.

## Config

`logseq-db` reads `~/.agent/logseq.json`, written by `programs.logseq-db`
(the graph, the CLI, and on a CLI-only machine the sync settings). If the file
is missing, it prints:

> No config at ~/.agent/logseq.json. Set programs.logseq-db in your Nix profile.

Nextcloud asset credentials (used only by `--asset`) come from `passage`
(`logseq-assets/nextcloud/...`), not from `logseq.json`.

`--asset` uploads whatever bytes it's given — no format is required or
assumed. When bundling multiple files into one asset, prefer `tar` +
`zstd` (`.tar.zst`) over `.zip`: it compresses better and `zstd` is already
on this machine.

## Availability check

To check reachability without writing anything (e.g. before deciding whether
to fall back to a local file), run:

```bash
python3 "$HOME/.agent/skills/logseq-write/logseq_write.py" --check
```

Exit 0 means the graph can be written here; exit 1 means it can't
(including "no config file" — that's a normal "not set up here" case, not an
error to surface). `session-save` uses this same check via the bundled
`logseq_status.py`.
