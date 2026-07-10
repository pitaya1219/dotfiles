---
name: logseq-write
description: Append content to a Logseq page (or create a new page) via HTTP API, with optional Markdown-to-blocks conversion
user-invocable: true
version: 2.1.0
---

Append content to a Logseq page, or create a new page with properties. Reads connection config from `~/.agent/logseq.json`.

`$ARGUMENTS` format: `<page> [--format markdown|logseq] [--title "..."] [--tag tag-name] [--create-page] [--prop key=value]... [--asset path[:name]]...`

- `page` — Logseq page name (e.g. `2026-06-08` for today's journal, or `Session: fix-bug` for a new page)
- `--format` — `markdown` (default) converts Markdown; `logseq` uses native outline as-is
- `--title` — parent block heading; all content becomes its children (append mode only)
- `--tag` — adds `tags:: #<tag>` property on the title block (requires `--title`, append mode only)
- `--create-page` — create a new page instead of appending to an existing one; `<page>` becomes the page title
- `--prop key=value` — set a page property (repeatable, requires `--create-page`)
- `--asset path[:name]` — copy a local file into the graph's `assets/` dir and append a link block to the content (repeatable). Optional `:name` overrides the on-disk filename (defaults to the source basename). Image extensions render inline (`![]`), everything else as a download link (`[]`).

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
- `TITLE` — `--title` value (optional, append mode only)
- `TAG` — `--tag` value (optional, append mode only)
- `CREATE_PAGE` — true if `--create-page` is present
- `PROPS` — map of key→value from all `--prop key=value` occurrences
- `ASSETS` — list of `path[:name]` from all `--asset` occurrences

## Step 3: Create Page (if `--create-page`)

Call `logseq.Editor.createPage` with the page title and collected properties:

```bash
# Build properties JSON object from --prop key=value pairs
PROPS_JSON=$(jq -n \
  --arg tags   "$PROP_tags" \
  --arg date   "$PROP_date" \
  # ... repeat for each collected prop
  '{tags: $tags, date: $date, ...}')

RESULT=$(curl -sf \
  -H "Authorization: Bearer $LOGSEQ_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg name "$PAGE" --argjson props "$PROPS_JSON" \
        '{method: "logseq.Editor.createPage", args: [$name, $props, {"redirect": false}]}')" \
  "$LOGSEQ_URL/api")

# Verify page was created
echo "$RESULT" | jq -e '.uuid' > /dev/null || { echo "createPage failed: $RESULT"; exit 1; }
```

After page creation, proceed to insert content blocks into the new page using `PAGE` as the page name.

## Step 3.5: Copy Assets (if `--asset`)

For each `--asset path[:name]`, copy the file into the graph's `assets/` directory
and build a link block. Collect the resulting blocks into `ASSET_BLOCKS` (a JSON
array of `{ "content": ... }` objects) for appending in Step 4.

```bash
# Resolve the current graph's on-disk assets/ dir (once)
GRAPH_PATH=$(curl -sf \
  -H "Authorization: Bearer $LOGSEQ_TOKEN" -H "Content-Type: application/json" \
  -d '{"method":"logseq.App.getCurrentGraph","args":[]}' \
  "$LOGSEQ_URL/api" | jq -r '.path // empty')

ASSET_BLOCKS='[]'
if [ -n "$GRAPH_PATH" ] && [ -d "$GRAPH_PATH/assets" ]; then
  for SPEC in "${ASSETS[@]}"; do
    SRC="${SPEC%%:*}"                          # part before optional :name
    NAME="${SPEC#*:}"; [ "$NAME" = "$SPEC" ] && NAME="$(basename "$SRC")"
    [ -f "$SRC" ] || { echo "asset not found, skipping: $SRC" >&2; continue; }
    cp "$SRC" "$GRAPH_PATH/assets/$NAME"
    # Image extensions render inline; everything else is a download link.
    case "${NAME,,}" in
      *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.bmp) PREFIX='!';;
      *) PREFIX='';;
    esac
    LINK="${PREFIX}[${NAME}](../assets/${NAME})"
    ASSET_BLOCKS=$(jq -c --arg c "$LINK" '. + [{content:$c}]' <<<"$ASSET_BLOCKS")
  done
fi
```

## Step 4: Build Block Tree

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

If `ASSET_BLOCKS` (from Step 3.5) is non-empty, append its blocks to the end of this
top-level array so asset links appear after the content. When content is empty (assets
only), the tree is just `ASSET_BLOCKS`.

## Step 5: Wrap with Title Block (append mode only)

If `--title` is given (and not `--create-page`), construct the title block content:
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

## Step 6: Insert into Logseq

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
