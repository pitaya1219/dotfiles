#!/usr/bin/env python3
"""Append content to a Logseq page, or create a new page with properties.

This is the full implementation behind the logseq-write skill: config
resolution, Markdown/native-outline -> block-tree conversion, optional page
creation, optional Nextcloud asset upload, and the Logseq API calls. The
skill's SKILL.md only tells the calling agent how to invoke this script —
none of the API/JSON plumbing is left for the agent to hand-write, which is
the actual fix for the instability that motivated this rewrite (weaker
models were inconsistently reproducing multi-step curl/jq chains and
hand-built nested JSON block trees).

Usage:
    logseq_write.py <page> [--format markdown|logseq] [--title T] [--tag TAG]
                     [--create-page] [--prop key=value]... [--asset path[:name]]...
    Content is read from stdin (may be empty when --asset alone supplies content).

    logseq_write.py --check
    Prints nothing; exits 0 if Logseq is reachable, 1 otherwise. (Prefer
    logseq_status.py for this — kept here too since --check is cheap and some
    callers already have this script's path handy.)
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from logseq_common import ConfigError, call_api, is_available, load_config  # noqa: E402
import nextcloud_asset  # noqa: E402


def parse_args(argv):
    p = argparse.ArgumentParser(prog="logseq_write.py")
    p.add_argument("page", nargs="?")
    p.add_argument("--format", choices=["markdown", "logseq"], default="markdown")
    p.add_argument("--title")
    p.add_argument("--tag")
    p.add_argument("--create-page", action="store_true")
    p.add_argument("--prop", action="append", default=[], metavar="key=value")
    p.add_argument("--asset", action="append", default=[], metavar="path[:name]")
    p.add_argument("--check", action="store_true", help="only check Logseq availability")
    args = p.parse_args(argv)

    if args.check:
        return args

    if not args.page:
        p.error("page is required (unless --check)")
    if args.tag and not args.title:
        p.error("--tag requires --title")
    if args.prop and not args.create_page:
        p.error("--prop requires --create-page")
    for kv in args.prop:
        if "=" not in kv:
            p.error(f"--prop must be key=value, got: {kv!r}")
    return args


# --- Markdown / native-outline -> block tree ---------------------------------


def _new_node(content):
    return {"content": content, "children": []}


def _strip_empty_children(node):
    if not node.get("children"):
        node.pop("children", None)
    else:
        for child in node["children"]:
            _strip_empty_children(child)
    return node


def _build_indented_tree(events):
    """Assemble (depth, node) events into a block tree via stack-based
    indentation nesting: a node at depth D becomes a child of the nearest
    preceding node at depth < D (plain ">=" pop rule, so equal-depth events
    become siblings). `depth=None` appends `node` as a leaf into whatever
    context is currently deepest, without opening a new nesting level for it.

    Shared by convert_markdown and convert_logseq_native — the two formats
    differ only in how a line maps to a (depth, node) event, not in how
    those events nest into a tree.
    """
    root = []
    stack = [(-1, root)]
    for depth, node in events:
        if depth is None:
            stack[-1][1].append(node)
            continue
        while len(stack) > 1 and stack[-1][0] >= depth:
            stack.pop()
        stack[-1][1].append(node)
        stack.append((depth, node["children"]))
    for node in root:
        _strip_empty_children(node)
    return root


def convert_markdown(text):
    """Markdown -> Logseq block tree, per the table in SKILL.md:
    H1 skipped; H2/H3(+) become bold section/subsection blocks nested by
    heading depth; list items (with [ ]/[x] -> TODO/DONE) nest by
    indentation, always deeper than the enclosing heading; plain paragraphs
    attach as a leaf under the current context; inline markdown passes
    through unchanged.
    """

    def events():
        for raw in text.split("\n"):
            line = raw.rstrip("\n")
            if not line.strip():
                continue

            h = re.match(r"^(#{1,6})\s+(.*)", line)
            if h:
                hashes, heading_text = h.groups()
                if len(hashes) == 1:
                    continue  # H1 is the page/parent title, not content
                # Heading depth (2-6) and list depth (100+indent, below)
                # use disjoint ranges so they never collide in the shared
                # stack, and lists always nest deeper than any heading.
                yield len(hashes), _new_node(f"**{heading_text.strip()}**")
                continue

            li = re.match(r"^(\s*)[-*]\s+(.*)", line)
            if li:
                indent, item_text = li.groups()
                checkbox = re.match(r"^\[( |x|X)\]\s+(.*)", item_text)
                if checkbox:
                    mark = "DONE" if checkbox.group(1).lower() == "x" else "TODO"
                    content = f"{mark} {checkbox.group(2)}"
                else:
                    content = item_text
                yield 100 + len(indent), _new_node(content)
                continue

            # Plain paragraph: leaf under whatever context is currently deepest.
            yield None, {"content": line}

    return _build_indented_tree(events())


def convert_logseq_native(text):
    """Native Logseq outline: each line is a block, 2-space indent = 1 level."""

    def events():
        for raw in text.split("\n"):
            if not raw.strip():
                continue
            stripped = raw.lstrip(" ")
            indent = len(raw) - len(stripped)
            yield indent // 2, _new_node(stripped)

    return _build_indented_tree(events())


# --- Logseq API operations -----------------------------------------------------


def _parse_json(body):
    try:
        return json.loads(body) if body else {}
    except json.JSONDecodeError:
        return {}


def create_page(url, token, page):
    status, body = call_api(url, token, "logseq.Editor.createPage", [page, {}, {"redirect": False}])
    result = _parse_json(body)
    if status != 200 or "uuid" not in result:
        print(f"createPage failed (HTTP {status}): {body}", file=sys.stderr)
        sys.exit(1)


def get_page_blocks_tree(url, token, page):
    status, body = call_api(url, token, "logseq.Editor.getPageBlocksTree", [page])
    if status != 200:
        print(f"getPageBlocksTree failed (HTTP {status}): {body}", file=sys.stderr)
        sys.exit(1)
    return _parse_json(body) or []


def insert_block(url, token, sibling_uuid, content, before):
    status, body = call_api(
        url, token, "logseq.Editor.insertBlock",
        [sibling_uuid, content, {"before": before, "sibling": True}],
    )
    if status != 200:
        print(f"insertBlock failed (HTTP {status}): {body}", file=sys.stderr)
        sys.exit(1)


def update_block(url, token, block_uuid, content):
    status, body = call_api(url, token, "logseq.Editor.updateBlock", [block_uuid, content])
    if status != 200:
        print(f"updateBlock failed (HTTP {status}): {body}", file=sys.stderr)
        sys.exit(1)


def upsert_block_property(url, token, block_uuid, key, value):
    status, body = call_api(
        url, token, "logseq.Editor.upsertBlockProperty", [block_uuid, key, value]
    )
    if status != 200:
        print(f"upsertBlockProperty failed (HTTP {status}): {body}", file=sys.stderr)
        sys.exit(1)


def apply_page_properties(url, token, page, props):
    """Write page properties, whether or not the page already existed.

    createPage takes a properties argument but drops it when the page is
    already there, and a page is already there more often than it looks: a
    `[[Wiki link]]` from any other page materializes an empty one. Writing a
    two-page set where the first links to the second therefore silently lost
    every property on the second. So properties are never left to createPage;
    they are always written here, against the page's own first block.

    Existing properties are updated key by key rather than replaced wholesale,
    so a property added by hand on a page this script rewrites survives.
    """
    if not props:
        return

    blocks = get_page_blocks_tree(url, token, page)
    first = blocks[0] if blocks else None

    if first and (first.get("properties") or {}):
        for key, value in props.items():
            upsert_block_property(url, token, first["uuid"], key, value)
        return

    content = "\n".join(f"{key}:: {value}" for key, value in props.items())
    if first is None:
        append_block_in_page(url, token, page, content)
    elif not (first.get("content") or "").strip():
        # createPage leaves one empty placeholder block behind. Fill that block
        # instead of inserting before it, or the page keeps a blank block
        # wedged between its properties and its content.
        update_block(url, token, first["uuid"], content)
    else:
        insert_block(url, token, first["uuid"], content, before=True)


def append_block_in_page(url, token, page, content):
    status, body = call_api(url, token, "logseq.Editor.appendBlockInPage", [page, content])
    result = _parse_json(body)
    uuid = result.get("uuid") or (result.get("result") or {}).get("uuid")
    if status != 200 or not uuid:
        print(f"appendBlockInPage failed (HTTP {status}): {body}", file=sys.stderr)
        sys.exit(1)
    return uuid


def insert_batch_block(url, token, parent_uuid, blocks, sibling):
    status, body = call_api(
        url, token, "logseq.Editor.insertBatchBlock", [parent_uuid, blocks, {"sibling": sibling}]
    )
    if status != 200:
        print(f"insertBatchBlock failed (HTTP {status}): {body}", file=sys.stderr)
        sys.exit(1)


def count_blocks(blocks):
    total = 0
    for b in blocks:
        total += 1 + count_blocks(b.get("children") or [])
    return total


def insert_tree(url, token, page, tree):
    """Insert a top-level block tree into `page`.

    appendBlockInPage only ever creates a single block, so the first
    top-level entry becomes the anchor: its own children go in as
    sibling=false (nested under it), and any further top-level entries go in
    as sibling=true against that same anchor (siblings at the page's root
    level). This generalizes the two cases the original prose only partially
    specified: a single --title-wrapped tree (children of one root block —
    the common case) and multiple untitled top-level blocks (real page-root
    siblings, previously left to each agent's own interpretation).
    """
    if not tree:
        return 0
    first, rest = tree[0], tree[1:]
    anchor = append_block_in_page(url, token, page, first["content"])
    total = 1
    children = first.get("children") or []
    if children:
        insert_batch_block(url, token, anchor, children, sibling=False)
        total += count_blocks(children)
    if rest:
        insert_batch_block(url, token, anchor, rest, sibling=True)
        total += count_blocks(rest)
    return total


def main():
    args = parse_args(sys.argv[1:])

    try:
        url, token = load_config()
    except ConfigError as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)

    if args.check:
        sys.exit(0 if is_available(url, token) else 1)

    if args.create_page:
        create_page(url, token, args.page)
        apply_page_properties(url, token, args.page, dict(kv.split("=", 1) for kv in args.prop))

    asset_blocks = []
    for spec in args.asset:
        if ":" in spec:
            src, name = spec.split(":", 1)
        else:
            src, name = spec, None
        link = nextcloud_asset.upload(src, name)
        if link is not None:
            asset_blocks.append({"content": link})

    content = sys.stdin.read() if not sys.stdin.isatty() else ""
    if args.format == "markdown":
        content_tree = convert_markdown(content)
    else:
        content_tree = convert_logseq_native(content)
    content_tree += asset_blocks

    if args.title:
        title_content = args.title
        if args.tag:
            title_content += f"\ntags:: #{args.tag}"
        root_tree = [{"content": title_content, "children": content_tree}]
    else:
        root_tree = content_tree

    inserted = insert_tree(url, token, args.page, root_tree)
    print(f"Page: {args.page}, {inserted} block(s) inserted")


if __name__ == "__main__":
    main()
