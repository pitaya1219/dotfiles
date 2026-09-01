#!/usr/bin/env python3
"""Check a code-flow page against itself and against the source it describes.

    python3 check.py flow.html --src src/pkg/module.py [src/pkg/other.py ...]

Findings are printed one per line and the exit status is 1 if there are any.
Run it before handing the page over; see SKILL.md for what each check is for.

The page is parsed with regexes rather than a real HTML parser, which is safe
only because the markup comes from template.html and keeps its shape. Reformat
the node/stage blocks and these checks stop seeing them.
"""

import argparse
import pathlib
import re
import sys

NODE_ID = r'id="(n-[a-z0-9-]+)"'
# A .fn worth grepping for: an identifier, optionally dotted, optionally called.
# Decision nodes ("guard 条件を満たす ?") carry prose instead and are skipped.
SYMBOL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)(\(\))?$")


def flow_region(html):
    m = re.search(r'<div class="flow" id="flow">(.*?)\n</div>', html, re.S)
    if not m:
        sys.exit("could not find the .flow region — is this a code-flow page?")
    return m.group(1)


def parse_stages(flow):
    """[(stage id, [(node id, fn text), ...]), ...] in document order."""
    chunks = re.split(r'<div class="stage" data-s="([a-z0-9]+)">', flow)[1:]
    out = []
    for stage, body in zip(chunks[0::2], chunks[1::2]):
        nodes = []
        for block in re.split(r'<div class="node', body)[1:]:
            nid = re.search(NODE_ID, block)
            fn = re.search(r'<div class="fn">(.*?)</div>', block, re.S)
            if nid:
                text = re.sub(r"<[^>]+>", "", fn.group(1)).strip() if fn else ""
                nodes.append((nid.group(1), text))
        out.append((stage, nodes))
    return out


def parse_scenarios(html):
    m = re.search(r"const SCENARIOS\s*=\s*\[(.*?)\n\];", html, re.S)
    if not m:
        sys.exit("could not find the SCENARIOS array")
    out = []
    for block in re.split(r"\n  \{", m.group(1)):
        key = re.search(r'key\s*:\s*"([^"]*)"', block)
        if not key:
            continue
        path = re.search(r"path\s*:\s*\[(.*?)\]", block, re.S)
        stages = re.search(r"stages\s*:\s*\[(.*?)\]", block, re.S)
        out.append({
            "key": key.group(1),
            "path": re.findall(r'"([^"]+)"', path.group(1)) if path else [],
            "stages": re.findall(r'"([^"]+)"', stages.group(1)) if stages else [],
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("page", type=pathlib.Path)
    ap.add_argument("--src", type=pathlib.Path, nargs="*", default=[],
                    help="source files the page claims to describe")
    args = ap.parse_args()

    html = args.page.read_text()
    stages = parse_stages(flow_region(html))
    scenarios = parse_scenarios(html)

    node_stage, node_fn = {}, {}
    for stage, nodes in stages:
        for nid, fn in nodes:
            node_stage[nid] = stage
            node_fn[nid] = fn

    findings = []

    # 1. A path entry with no node behind it never lights up.
    for sc in scenarios:
        for nid in sc["path"]:
            if nid not in node_stage:
                findings.append(f"{sc['key']}: path references {nid}, which no node defines")

    # 2. A node no scenario reaches is dead code or a missing scenario.
    reached = {nid for sc in scenarios for nid in sc["path"]}
    for nid in node_stage:
        if nid not in reached:
            findings.append(f"{nid} is reached by no scenario — dead code, or a scenario is missing")

    # 3. stages must be exactly the stages the path walks through.
    for sc in scenarios:
        walked = []
        for nid in sc["path"]:
            s = node_stage.get(nid)
            if s and s not in walked:
                walked.append(s)
        if sc["stages"] != walked:
            findings.append(
                f"{sc['key']}: stages {sc['stages']} but the path walks {walked}")

    # 4. Every node named after a symbol must be a symbol that exists.
    #    This is what stops a misread of the code from becoming a confident diagram.
    if args.src:
        blob = "\n".join(p.read_text() for p in args.src)
        skipped = 0
        for nid, fn in sorted(node_fn.items()):
            m = SYMBOL.match(fn)
            if not m:
                skipped += 1
                continue
            symbol = m.group(1)
            # Match on word boundaries: a bare `in` test lets a short method name
            # like read() pass on the word "already".
            if any(re.search(r"\b%s\b" % re.escape(s), blob)
                   for s in (symbol, symbol.split(".")[-1])):
                continue
            findings.append(f"{nid}: \"{fn}\" appears in no --src file — paraphrase, or wrong")
        print(f"checked {len(node_fn) - skipped} node labels against source, "
              f"skipped {skipped} written as prose", file=sys.stderr)
    else:
        print("no --src given: node labels were not checked against the source",
              file=sys.stderr)

    for f in findings:
        print(f)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
