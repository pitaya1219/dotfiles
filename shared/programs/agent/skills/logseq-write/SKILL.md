---
name: logseq-write
description: Append content to a Logseq page via HTTP API, with optional Markdown-to-blocks conversion
user-invocable: true
version: 1.0.0
---

Append content to a Logseq page. Reads connection config from `~/.agent/logseq.json`.

`$ARGUMENTS` format: `<page> [--format markdown|logseq] [--title "..."] [--tag tag-name]`

- `page` — Logseq page name (e.g. `2026-06-08` for today's journal)
- `--format` — `markdown` (default) converts Markdown; `logseq` uses native outline as-is
- `--title` — parent block heading; all content becomes its children
- `--tag` — adds `tags:: #<tag>` property on the title block (requires `--title`)

## Step 1: Load Config

```bash
cat ~/.agent/logseq.json
```

If missing, print error and stop:
> No config at ~/.agent/logseq.json. Set dotfiles.agent.logseq in your Nix profile.

Each of `url` and `token` accepts a plain string, `{ "file": "..." }`, or `{ "command": "..." }`.

```bash
resolve_value() {
  local KEY="$1" FILE="$HOME/.agent/logseq.json"
  local TYPE=$(jq -r "$KEY | type" "$FILE")
  if [ "$TYPE" = "string" ]; then
    jq -r "$KEY" "$FILE"
  else
    local SUBKEY=$(jq -r "$KEY | keys[0]" "$FILE")
    case "$SUBKEY" in
      file)    cat "$(jq -r "$KEY.file" "$FILE" | sed "s|~|$HOME|")" 2>/dev/null ;;
      command) eval "$(jq -r "$KEY.command" "$FILE")" 2>/dev/null ;;
    esac
  fi
}

LOGSEQ_URL=$(resolve_value '.url')
LOGSEQ_TOKEN=$(resolve_value '.token')
```

## Step 2: Parse Arguments

From `$ARGUMENTS`, extract:
- `PAGE` — first positional argument (required)
- `FORMAT` — `--format` value (default: `markdown`)
- `TITLE` — `--title` value (optional)
- `TAG` — `--tag` value (optional)

## Step 3: Build Block Tree

The content to write is provided in the conversation context (by the calling skill or user).

### Format: `logseq` (native)

Each line is a block. 2-space indentation creates child blocks. Use as-is.

### Format: `markdown` (convert)

Convert Markdown to a Logseq block tree using these rules:

| Markdown input | Logseq block content |
|---|---|
| `# H1` | skip — used only as page/parent title |
| `## Section` | `**Section**` — top-level child block |
| `### Subsection` | `**Subsection**` — child of current section |
| `- item` / `* item` | `item` — child of current context |
| `- [ ] task` | `TODO task` |
| `- [x] task` | `DONE task` |
| plain paragraph | block at current level |
| blank line | ignored |
| inline `**bold**`, `[[link]]`, `` `code` `` | pass through unchanged |

Build a JSON array of block objects:
```json
[
  {
    "content": "**Section**",
    "children": [
      { "content": "**Subsection**", "children": [
        { "content": "item" }
      ]}
    ]
  }
]
```

## Step 4: Wrap with Title Block

If `--title` is given, construct the title block content:
```
<TITLE>
tags:: #<TAG>
```
(omit `tags::` line if `--tag` not given)

Wrap the entire converted tree as children of this title block:
```json
[{ "content": "<title-content>", "children": [ ...converted tree... ] }]
```

If `--title` is not given, the converted tree's top-level blocks are inserted directly.

## Step 5: Insert into Logseq

Use `appendBlockInPage` to create the root block and obtain its UUID, then `insertBatchBlock` to insert its children.

```bash
# 1. Create root block (title block, or first top-level block if no title)
ROOT_CONTENT="<title block content or first block content>"
PARENT_RESULT=$(curl -sf \
  -H "Authorization: Bearer $LOGSEQ_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg page "$PAGE" --arg content "$ROOT_CONTENT" \
        '{method: "logseq.Editor.appendBlockInPage", args: [$page, $content]}')" \
  "$LOGSEQ_URL/api")
PARENT_UUID=$(echo "$PARENT_RESULT" | jq -r '.uuid // .result.uuid')

# 2. Insert children under the root block
curl -sf \
  -H "Authorization: Bearer $LOGSEQ_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --argjson blocks '<CHILDREN_JSON>' --arg uuid "$PARENT_UUID" \
        '{method: "logseq.Editor.insertBatchBlock", args: [$uuid, $blocks, {"sibling": false}]}')" \
  "$LOGSEQ_URL/api"
```

If any API call fails, print the error response and exit with code 1.
Print the page name and number of inserted top-level blocks when done.
