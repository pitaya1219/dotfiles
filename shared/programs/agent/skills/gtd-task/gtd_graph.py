#!/usr/bin/env python3
"""Read the GTD conventions out of the Logseq graph, which is where they live.

    gtd_graph.py templates          the GTD templates, one line each
    gtd_graph.py template NAME      one template, as markdown logseq-write takes
    gtd_graph.py rules              the Task Management Rules page (English part)
    gtd_graph.py choices            the values properties and projects can take

Read-only. Everything is read in one graph session, so a command takes a few
seconds rather than a few seconds per query.
"""
import os
import re
import shutil
import sys

TEMPLATE_NAME = r"GTD(<.*>)?"
RULES_PAGE = "Task Management Rules"
# What a task carries; other properties of a template's body are shown as they are.
BUILTIN = {"logseq.property/status": "status", "logseq.property/priority": "priority",
           "logseq.property/deadline": "deadline", "logseq.property/scheduled": "scheduled"}
SKIP = ("created", "updated", "created-by-ref", "order", "tx-id")


def load_logseqdb():
    """The `logseqdb` module that belongs to the installed `logseq-db`."""
    exe = shutil.which("logseq-db")
    if not exe:
        sys.exit("logseq-db is not installed")
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(exe))), "lib"))
    import logseqdb
    return logseqdb


def children(cli, parent_uuid):
    rows = cli.query("[:find ?o ?u ?t :in $ ?p :where [?pe :block/uuid ?p] [?c :block/parent ?pe] "
                     "[?c :block/uuid ?u] [?c :block/title ?t] [?c :block/order ?o]]",
                     [parent_uuid_arg(parent_uuid)]) or []
    return [(u, t) for _, u, t in sorted(rows)]


def parent_uuid_arg(u):
    import uuid
    return uuid.UUID(str(u))


def tree(cli, parent_uuid, depth=0):
    """[(depth, title)] of everything under a block, in order."""
    out = []
    for u, t in children(cli, parent_uuid):
        out.append((depth, t))
        out += tree(cli, u, depth + 1)
    return out


def property_names(graph):
    """{ident: title} of the user properties."""
    graph._load_props()
    return {it["db/ident"]: it.get("block/title") for items in graph._props.values() for it in items}


def body_properties(cli, names, body_uuid):
    """{property name: [value, ...]} of a template's body block."""
    pulled = cli.query("[:find (pull ?b [*]) :in $ ?u :where [?b :block/uuid ?u]]", [parent_uuid_arg(body_uuid)]) or []
    if not pulled:
        return {}
    out = {}
    # Task is implied by the status; any other tag (Chore, Learning, Someday) is part of the template.
    tags = [r[0] for r in cli.query("[:find ?n :in $ ?u :where [?b :block/uuid ?u] [?b :block/tags ?t] [?t :block/title ?n]]",
                                    [parent_uuid_arg(body_uuid)]) or [] if r[0] != "Task"]
    if tags:
        out["tags"] = sorted(tags)
    for key, val in pulled[0][0].items():
        if not key.startswith(("user.property/", "logseq.property/")) or key.split("/")[-1] in SKIP:
            continue
        label = BUILTIN.get(key) or names.get(key)
        if not label:
            continue
        rows = cli.query(f"[:find ?n :in $ ?u :where [?b :block/uuid ?u] [?b :{key} ?v] [?v :block/title ?n]]",
                         [parent_uuid_arg(body_uuid)])
        if rows:
            out[label] = sorted(r[0] for r in rows)
        elif not isinstance(val, (dict, list)):
            out[label] = [str(val)]
    return out


def find_templates(cli):
    rows = cli.query("[:find ?u ?t ?pg :where [?e :block/title ?t] [(re-pattern \"" + TEMPLATE_NAME + "\") ?re] "
                     "[(re-matches ?re ?t)] [?e :block/page ?p] [?p :block/title ?pg] [?e :block/uuid ?u]]") or []
    return sorted(rows, key=lambda r: r[1])


def render(title, props, subtree):
    """A template body as markdown for logseq-write: the title as an open task,
    its properties as `key:: value` lines, its sub-blocks as nested items."""
    lines = [f"- [ ] {title}"]
    for key, values in props.items():
        lines.append(f"  {key}:: {', '.join(values)}")
    for depth, text in subtree:
        lines.append("  " * (depth + 1) + "- " + text.replace("\n", " "))
    return "\n".join(lines)


def cmd_templates(cli, graph):
    names = property_names(graph)
    for u, name, page in find_templates(cli):
        body = children(cli, u)
        summary = "(no body)"
        if body:
            bu, bt = body[0]
            props = body_properties(cli, names, bu)
            subs = len(tree(cli, bu))
            shown = ", ".join(f"{k}={'/'.join(v)}" for k, v in props.items()) or "no properties"
            summary = f"{bt[:50]!r}  {shown}  {subs} sub-block(s)"
        print(f"{name:<16} defined on {page:<12} {summary}")


def cmd_template(cli, graph, wanted):
    names = property_names(graph)
    found = [r for r in find_templates(cli) if r[1].lower() == wanted.lower()]
    if not found:
        have = ", ".join(r[1] for r in find_templates(cli))
        sys.exit(f"no template named {wanted!r}; the graph has: {have}")
    u, name, page = found[0]
    body = children(cli, u)
    if not body:
        sys.exit(f"{name} has no body block")
    bu, bt = body[0]
    print(f"<!-- {name}, defined on {page}. Fill the {{{{placeholders}}}} and keep the structure. -->")
    print(render(bt, body_properties(cli, names, bu), tree(cli, bu)))


def cmd_rules(cli):
    pages = cli.query(f'[:find ?e :where [?e :block/title "{RULES_PAGE}"] [(missing? $ ?e :block/page)]]') or []
    if not pages:
        sys.exit(f"page {RULES_PAGE!r} not found")
    rows = cli.query("[:find ?o ?u ?t ?p :in $ ?page :where [?pe :block/title ?page] [?c :block/page ?pe] "
                     "[?c :block/uuid ?u] [?c :block/title ?t] [?c :block/order ?o] [?c :block/parent ?pp] "
                     "[?pp :block/uuid ?p]]", [RULES_PAGE]) or []
    by_parent = {}
    for o, u, t, p in rows:
        by_parent.setdefault(p, []).append((o, u, t))
    top = cli.query(f'[:find ?u :where [?e :block/title "{RULES_PAGE}"] [(missing? $ ?e :block/page)] [?e :block/uuid ?u]]')
    root = top[0][0]

    def walk(parent, depth):
        for _, u, t in sorted(by_parent.get(str(parent), [])):
            yield depth, t
            yield from walk(u, depth + 1)

    for depth, text in walk(root, 0):
        # The page repeats itself in Japanese after a "---" block.
        if text.strip() == "---" and depth == 0:
            return
        print("  " * depth + "- " + text.replace("\n", " / "))


def cmd_choices(cli, graph):
    names = property_names(graph)
    ident_of = {v: k for k, v in names.items()}
    for label, ident in (("status", "logseq.property/status"), ("priority", "logseq.property/priority"),
                         ("area", ident_of.get("area")), ("context", ident_of.get("context"))):
        if ident:
            print(f"{label:<9}: {', '.join(sorted(graph.choices(ident)))}")
    for tag in ("Project", "Team", "Place"):
        rows = cli.query(f'[:find ?n :where [?c :block/name "{tag.lower()}"] [?e :block/tags ?c] [?e :block/title ?n]]') or []
        if rows:
            print(f"{tag.lower():<9}: {', '.join(sorted(r[0] for r in rows))}")
    print(f"\nuser properties that exist: {', '.join(sorted(n for n in names.values() if n))}")


def main(argv):
    if not argv or argv[0] not in ("templates", "template", "rules", "choices") or (argv[0] == "template" and len(argv) < 2):
        print(__doc__)
        return 2
    lq = load_logseqdb()
    with lq.session(lq.load_config()) as cli:
        graph = lq.Graph(cli)
        if argv[0] == "templates":
            cmd_templates(cli, graph)
        elif argv[0] == "template":
            cmd_template(cli, graph, " ".join(argv[1:]))
        elif argv[0] == "rules":
            cmd_rules(cli)
        else:
            cmd_choices(cli, graph)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
