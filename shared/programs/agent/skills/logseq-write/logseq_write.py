#!/usr/bin/env python3
"""Append content to a Logseq page, or create a new page with properties.

This is the full implementation behind the logseq-write skill:
Markdown/native-outline -> block-tree conversion and optional Nextcloud asset
upload. The write itself goes through `logseq-db write` (tools/logseq-db),
which owns the Logseq CLI, property types and sync. The skill's SKILL.md only
tells the calling agent how to invoke this script, so no plumbing is left for
the agent to hand-write.

Usage:
    logseq_write.py <page> [--format markdown|logseq] [--title T] [--tag TAG]
                     [--create-page] [--prop key=value]... [--asset path[:name]]...
    Content is read from stdin (may be empty when --asset alone supplies content).

    logseq_write.py --check
    Prints nothing; exits 0 if Logseq can be written here, 1 otherwise.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from logseq_common import LogseqError, available, write  # noqa: E402
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


def count_blocks(blocks):
    return sum(1 + count_blocks(b.get("children") or []) for b in blocks)


def main():
    args = parse_args(sys.argv[1:])

    if args.check:
        sys.exit(0 if available() else 1)

    if "/" in args.page:
        print(f"Logseq DB page names cannot contain '/': {args.page!r}", file=sys.stderr)
        sys.exit(1)

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
        title_block = {"content": args.title, "children": content_tree}
        if args.tag:
            title_block["tags"] = [args.tag]
        root_tree = [title_block]
    else:
        root_tree = content_tree

    properties = dict(kv.split("=", 1) for kv in args.prop) if args.create_page else {}
    try:
        write(args.page, properties, root_tree)
    except LogseqError as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
    print(f"Page: {args.page}, {count_blocks(root_tree)} block(s) inserted")


if __name__ == "__main__":
    main()
