"""Write to and read from a Logseq DB graph through the Logseq CLI.

The CLI attaches to whichever db-worker-node serves the graph, or starts its
own. Who owns that worker decides what happens around a write:

- The desktop app's worker (owner-source "electron"): the app syncs and holds
  the tokens, so nothing else is needed.
- A worker the CLI started, on a machine that also runs the desktop app
  (config "desktop": true): the write stays pending in the graph's database
  and the app uploads it the next time it starts. The CLI must not sync here.
  ~/logseq/auth.json is only the app's copy of its own tokens, and a refresh
  from the CLI makes Zitadel revoke the refresh token the app still holds.
  The worker is stopped afterwards: an app started while it is still running
  attaches to it and cannot sync through it.
- A worker the CLI started on a CLI-only machine: the CLI syncs, then the
  worker is stopped. The graph's E2EE password is passed on every start: the
  worker stores it encrypted with the refresh token, which rotates.

~/.agent/logseq.json (dotfiles.agent.logseq) holds:
  graph         graph name
  desktop       true when the desktop app runs on this machine
  cli           the logseq CLI executable
  e2eePassword  CLI-only: string, {"file": ...} or {"command": ...}
  sync          CLI-only: wsUrl, httpBase, authorizeEndpoint, tokenEndpoint,
                clientId (string, {"file"} or {"command"}), scope
"""
import base64
import contextlib
import fcntl
import hashlib
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

CONFIG_PATH = os.environ.get("LOGSEQ_DB_CONFIG") or os.path.expanduser("~/.agent/logseq.json")
STATE_DIR = os.path.expanduser("~/.cache/logseq-db")
CALLBACK_URI = "http://localhost:8765/auth/callback"


class LogseqError(RuntimeError):
    pass


def resolve_value(val):
    """A plain string, {"file": path} or {"command": shell command}."""
    if isinstance(val, str):
        return val
    if isinstance(val, dict):
        if "file" in val:
            try:
                with open(os.path.expanduser(val["file"])) as f:
                    return f.read().strip()
            except OSError:
                return ""
        if "command" in val:
            out = subprocess.run(val["command"], shell=True, capture_output=True, text=True)
            return out.stdout.strip() if out.returncode == 0 else ""
    return ""


def describe_source(val):
    """Why resolve_value gave nothing, without printing the value itself."""
    if isinstance(val, dict) and "command" in val:
        out = subprocess.run(val["command"], shell=True, capture_output=True, text=True)
        err = out.stderr.strip().splitlines()
        return f"`{val['command']}` exited {out.returncode}" + (f": {err[-1]}" if err else "")
    if isinstance(val, dict) and "file" in val:
        return f"{val['file']} is missing or empty"
    return "not set"


class Config:
    def __init__(self, raw):
        self.raw = raw
        self.graph = raw.get("graph") or ""
        self.desktop = bool(raw.get("desktop"))
        cli = raw.get("cli") or "logseq-cli"
        self.cli = cli if isinstance(cli, list) else [cli]
        self.sync = raw.get("sync") or {}
        if not self.graph:
            raise LogseqError(f"{CONFIG_PATH} has no graph.")

    def e2ee_password(self):
        return resolve_value(self.raw.get("e2eePassword"))


def load_config(path=CONFIG_PATH):
    if not os.path.exists(path):
        raise LogseqError(f"No config at {path}. Set programs.logseq-db in your Nix profile.")
    with open(path) as f:
        return Config(json.load(f))


# --- CLI ------------------------------------------------------------------


def edn(value):
    """Python value -> EDN. Strings starting with ':' are keywords."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if value is None:
        return "nil"
    if isinstance(value, str):
        if value.startswith(":") and " " not in value:
            return value
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return "[" + " ".join(edn(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{" + " ".join(f"{edn(k)} {edn(v)}" for k, v in value.items()) + "}"
    raise TypeError(f"cannot encode {value!r} as EDN")


class Cli:
    def __init__(self, cfg):
        self.cfg = cfg
        self.config_path = None if cfg.desktop else write_cli_config(cfg)

    def run(self, *args, graph=True, timeout_ms=120000):
        cmd = list(self.cfg.cli) + list(args) + ["-o", "json", "--timeout-ms", str(timeout_ms)]
        if graph:
            cmd += ["-g", self.cfg.graph]
        if self.config_path:
            cmd += ["--config", self.config_path]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_ms / 1000 + 30)
        out = proc.stdout.strip()
        try:
            body = json.loads(out.splitlines()[-1]) if out else {}
        except json.JSONDecodeError:
            body = {}
        if proc.returncode != 0 or body.get("status") != "ok":
            message = (body.get("error") or {}).get("message") if isinstance(body.get("error"), dict) else None
            raise LogseqError(f"logseq {' '.join(args[:2])} failed: {message or out or proc.stderr.strip()}")
        return body.get("data")

    def query(self, q, inputs=None):
        args = ["query", "--query", q] + (["--inputs", edn(inputs)] if inputs is not None else [])
        return (self.run(*args) or {}).get("result")

    def transact(self, tx):
        """Apply raw datoms through the worker's outliner, so they sync like an
        edit made in the app. The CLI has no command for some attributes (a
        page's :block/parent). `tx` is a list of [entity id, attribute, value]
        additions, where an int value is an entity id too; the worker has to
        be running, which any query ensures."""
        self._outliner([["~:transact", [self._datoms(tx), ["^ "]]]])

    def save_block(self, block_id, title, ref_uuids):
        """Save the block's title with :block/refs to `ref_uuids` plus its
        tags, as the editor does. `upsert block --content` saves the title
        alone and `--update-tags` drops the refs a block has, so either leaves
        its [[links]] pointing nowhere. save-block keeps the refs of an
        unchanged title, so they also go in as plain datoms."""
        uuid_ = self.query("[:find ?u . :in $ ?e :where [?e :block/uuid ?u]]", [block_id])
        tags = self.query("[:find [?u ...] :in $ ?e :where [?e :block/tags ?t] [?t :block/uuid ?u]]", [block_id]) or []
        refs = [["~:block/uuid", "~u" + u] for u in dict.fromkeys(list(ref_uuids) + tags)]
        block = ["^ ", "~:block/uuid", "~u" + uuid_, "~:block/title", title, "~:block/refs", refs]
        ops = [["~:save-block", [block, ["^ "]]]]
        if refs:
            ops.append(["~:transact", [self._datoms([[block_id, "block/refs", r] for r in refs]), ["^ "]]])
        self._outliner(ops)

    def _datoms(self, tx):
        """Transit :db/add datoms naming entities by uuid, not db id: ops made
        offline are replayed after the remote txs, where a db id can name
        another entity, and the sync then drops the whole tx as a conflicting
        upsert."""
        ids = sorted({x for e, _, v in tx for x in (e, v) if isinstance(x, int) and not isinstance(x, bool)})
        rows = self.query("[:find ?e ?u :in $ [?e ...] :where [?e :block/uuid ?u]]", [ids]) if ids else []
        uuids = dict(rows or [])
        missing = [i for i in ids if i not in uuids]
        if missing:
            raise LogseqError(f"no uuid for entities {missing}")

        def ref(x):
            if isinstance(x, int) and not isinstance(x, bool):
                return ["~:block/uuid", "~u" + uuids[x]]
            return x

        return [["~:db/add", ref(e), "~:" + a.lstrip(":"), ref(v)] for e, a, v in tx]

    def _outliner(self, ops):
        server = worker(self)
        if not server:
            raise LogseqError(f"no worker is serving {self.cfg.graph}")
        args = [server["repo"], ops, ["^ "]]
        body = json.dumps({"method": "thread-api/apply-outliner-ops", "argsTransit": json.dumps(args)})
        req = urllib.request.Request(server["base-url"] + "/v1/invoke", data=body.encode(), method="POST",
                                     headers={"Content-Type": "application/json", "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                result = json.loads(resp.read() or b"{}")
        except (urllib.error.URLError, json.JSONDecodeError) as e:
            raise LogseqError(f"outliner ops on {self.cfg.graph} failed: {e}")
        if not result.get("ok"):
            raise LogseqError(f"outliner ops on {self.cfg.graph} failed: {result}")


def write_cli_config(cfg):
    """Render the CLI's config from logseq.json, for CLI-only machines.

    The CLI otherwise talks to Logseq's own sync service and Cognito.
    """
    s = cfg.sync
    fields = {
        ":ws-url": s.get("wsUrl"),
        ":http-base": s.get("httpBase"),
        ":oauth-authorize-endpoint": s.get("authorizeEndpoint"),
        ":oauth-token-endpoint": s.get("tokenEndpoint"),
        ":oauth-client-id": resolve_value(s.get("clientId")),
        ":oauth-scope": s.get("scope"),
    }
    text = edn({k: v for k, v in fields.items() if v}) + "\n"
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    path = os.path.join(STATE_DIR, "cli.edn")
    try:
        with open(path) as f:
            if f.read() == text:
                return path
    except OSError:
        pass
    with open(path, "w") as f:
        f.write(text)
    return path


# --- Worker lifecycle -------------------------------------------------------


def worker(cli):
    servers = (cli.run("server", "list", graph=False) or {}).get("servers") or []
    for s in servers:
        if s.get("graph") == cli.cfg.graph:
            return s
    return None


def sync_and_wait(cli, timeout=300, start=True):
    if start:
        password = cli.cfg.e2ee_password()
        args = ["sync", "start"] + (["--e2ee-password", password] if password else [])
        cli.run(*args)
    deadline = time.time() + timeout
    while True:
        try:
            st = cli.run("sync", "status") or {}
        except LogseqError as e:
            # A worker catching up on many remote txs answers nothing until it
            # is done, and the CLI reports that as a timeout.
            if "timeout" not in str(e).lower() or time.time() > deadline:
                raise
            continue
        if st.get("last-error"):
            raise LogseqError(f"sync failed: {st['last-error']}")
        done = (st.get("pending-local") == 0
                and st.get("local-checksum")
                and st.get("local-checksum") == st.get("remote-checksum"))
        if done:
            return st
        if time.time() > deadline:
            raise LogseqError(f"sync did not settle within {timeout}s: {st}")
        time.sleep(1)


@contextlib.contextmanager
def session(cfg):
    """Serialize CLI use on this machine and settle the worker afterwards."""
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    with open(os.path.join(STATE_DIR, "lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cli = Cli(cfg)
        if not cfg.desktop and not downloaded(cli):
            with contextlib.suppress(LogseqError):
                cli.run("server", "stop")
            raise LogseqError(f"{cfg.graph} is not downloaded on this machine; run `task logseq:download`.")
        before = worker(cli)
        app_owned = bool(before and before.get("owner-source") == "electron")
        synced = not app_owned and not cfg.desktop
        try:
            # Catch up before reading or writing: a machine that last synced
            # days ago would otherwise work on a stale graph, e.g. create a tag
            # the server already has under another uuid.
            if synced:
                sync_and_wait(cli)
            yield cli
        finally:
            if not app_owned:
                after = worker(cli)
                if after and after.get("owner-source") != "electron":
                    try:
                        if synced:
                            sync_and_wait(cli, start=False)
                    finally:
                        cli.run("server", "stop")


# --- Graph lookups ----------------------------------------------------------


WIKI = re.compile(r"\[\[([^\]]+)\]\]")
BLOCK_REF = re.compile(r"\(\(([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)\)")
DATE = re.compile(r"^\s*(?:\[\[)?(\d{4})-(\d{2})-(\d{2})(?:\]\])?\s*$")


def split_refs(value):
    """'[[a]] #b #[[c d]] e' -> ['a', 'b', 'c d', 'e']."""
    out = []
    for m in re.finditer(r"#\[\[([^\]]+)\]\]|\[\[([^\]]+)\]\]|#(\S+)", value):
        out.append(next(g for g in m.groups() if g))
    rest = re.sub(r"#\[\[[^\]]+\]\]|\[\[[^\]]+\]\]|#\S+", " ", value).strip()
    if rest:
        out.append(rest)
    return out


class Graph:
    def __init__(self, cli):
        self.cli = cli
        self._props = None

    def _load_props(self):
        # Built-in properties are left out: their names (status, priority)
        # collide with the user's and most take only their own closed values.
        items = (self.cli.run("list", "property") or {}).get("items") or []
        props = {}
        for it in items:
            if not it.get("db/ident", "").startswith("user.property/"):
                continue
            props.setdefault((it.get("block/title") or "").lower(), []).append(it)
        self._props = props

    def property(self, name, sample=None):
        """(ident, type, cardinality) of the user property titled `name`.

        A missing one is created, as a date when `sample` is a date.
        """
        if self._props is None:
            self._load_props()
        found = self._props.get(name.lower())
        if not found:
            ptype = "date" if sample and DATE.match(sample) else "default"
            self.cli.run("upsert", "property", "--name", name, "--type", ptype)
            self._load_props()
            found = self._props.get(name.lower()) or []
        if not found:
            raise LogseqError(f"could not create property {name!r}")
        it = found[0]
        card = "many" if it.get("db/cardinality", "").endswith("many") else "one"
        return it["db/ident"], it.get("logseq.property/type", "default"), card

    def journal(self, y, m, d):
        day = int(f"{y}{m}{d}")
        found = self.cli.query(f"[:find [?j ...] :where [?j :block/journal-day {day}]]")
        if found:
            return found[0]
        return self.cli.run("upsert", "page", "--page", f"{y}-{m}-{d}")["result"][0]

    def page(self, title):
        """The page titled `title`, created if missing and brought back if it
        is in the recycle bin, as writing [[title]] in the app does."""
        try:
            return self.cli.run("upsert", "page", "--page", title)["result"][0]
        except LogseqError as e:
            if "recycled" not in str(e):
                raise
            return self.cli.run("upsert", "page", "--page", title, "--restore")["result"][0]

    def set_parent(self, page_id, parent):
        """Put the page under `parent` (a namespace page such as Session), last
        among its siblings. `upsert page` refuses names with "/", so this is the
        CLI-side equivalent of creating "Parent/title"."""
        parent_id = self.page(parent)
        if self.cli.query("[:find ?x . :in $ ?p :where [?p :block/parent ?x]]", [page_id]) == parent_id:
            return
        last = self.cli.query(
            "[:find (max ?o) . :in $ ?s :where [?c :block/parent ?s] [?c :block/name] [?c :block/order ?o]]",
            [parent_id])
        self.cli.transact([[page_id, "block/parent", parent_id], [page_id, "block/order", order_after(last)]])

    def find_page(self, name):
        """The page a [[name]] link means: a journal for a date, `b` under `a`
        for "a/b". A missing page is created, except under a namespace."""
        m = DATE.match(name)
        if m:
            return self.journal(*m.groups())
        *parents, leaf = name.lower().split("/")
        if not parents:
            return self.page(name)
        found = self.cli.query(
            "[:find [(pull ?p [:db/id {:block/parent [:block/name {:block/parent 8}]}]) ...] "
            ":in $ ?n :where [?p :block/name ?n]]", [leaf]) or []
        for entity in found:
            chain, parent = [], entity.get("block/parent")
            while parent:
                chain.insert(0, parent.get("block/name", ""))
                parent = parent.get("block/parent")
            if chain[-len(parents):] == parents:
                return entity["db/id"]
        return None

    def link(self, block_id, text):
        """Point the block's refs at what `text` links to."""
        pages, blocks = links(text)
        uuids = []
        for name in pages:
            page_id = self.find_page(name)
            if page_id is None:
                print(f"logseq-db: no page {name!r} to link; the CLI cannot create one under a namespace",
                      file=sys.stderr)
                continue
            uuids.append(self.cli.query("[:find ?u . :in $ ?e :where [?e :block/uuid ?u]]", [page_id]))
        for u in blocks:
            if self.cli.query(f'[:find ?e . :where [?e :block/uuid #uuid "{u}"]]'):
                uuids.append(u)
        self.cli.save_block(block_id, text, uuids)

    def tag(self, name):
        q = f"[:find [?id ...] :where [?c :block/name {edn(name.lower())}] [?c :block/tags :logseq.class/Tag] [?c :db/ident ?id]]"
        found = self.cli.query(q)
        if not found:
            self.cli.run("upsert", "tag", "--name", name)
            found = self.cli.query(q)
        if not found:
            raise LogseqError(f"could not create tag {name!r}")
        return ":" + found[0]

    def value(self, ptype, card, raw):
        """A text property value -> what the CLI expects for its type."""
        if ptype == "date":
            m = DATE.match(raw)
            if not m:
                raise LogseqError(f"{raw!r} is not a YYYY-MM-DD date")
            return self.journal(*m.groups())
        if ptype in ("node", "page"):
            ids = [self.page(t) for t in split_refs(raw)]
            return ids if card == "many" else (ids[0] if ids else None)
        if ptype == "number":
            return float(raw) if "." in raw else int(raw)
        if ptype == "checkbox":
            return raw.strip().lower() in ("true", "yes", "1")
        if ptype == "default":
            return escape_number_tags(raw)
        return raw

    def properties(self, props):
        """{'date': '[[2026-11-06]]', 'tags': '#x'} -> (property edn map, tag idents)."""
        values, tags = {}, []
        for name, raw in props.items():
            if raw is None or str(raw).strip() == "":
                continue
            if name.lower() == "tags":
                tags += [self.tag(t) for t in split_refs(str(raw))]
                continue
            try:
                ident, ptype, card = self.property(name, str(raw))
            except LogseqError as e:
                # A name taken by a built-in property (status in a fresh
                # graph) cannot be created as a user property from the CLI.
                print(f"logseq-db: skipped property {name}: {e}", file=sys.stderr)
                continue
            values[":" + ident] = self.value(ptype, card, str(raw))
        return values, tags


# --- Writing ----------------------------------------------------------------


# The CLI's Markdown parser reads `key:: value` as a property of the block and
# `#word` as a tag, and fails when either does not exist yet, so text that
# merely mentions one (`tags::` in a sentence, `#519`) cannot go through
# --blocks-file. Neither can a multi-line block. Such blocks are inserted as a
# placeholder and their text set afterwards with --content, which takes any
# text.
# `#400` in text (a PR or issue number) reads as a tag once the block is
# edited in the app and creates a page "400". `\#400` displays the same and
# stays text. Code spans and fences are left as written.
CODE = re.compile(r"```.*?```|`[^`\n]*`", re.S)
NUMBER_TAG = re.compile(r"(?<![\\\w&/#])#(\d+)")


def escape_number_tags(text):
    out, last = [], 0
    for m in CODE.finditer(text):
        out.append(NUMBER_TAG.sub(r"\\#\1", text[last:m.start()]))
        out.append(m.group(0))
        last = m.end()
    out.append(NUMBER_TAG.sub(r"\\#\1", text[last:]))
    return "".join(out)


# A file graph's `TODO text` is plain text to a DB graph; a task is a block
# with the #Task tag and a status.
TASK_MARKER = re.compile(r"^(TODO|LATER|DOING|NOW|DONE|CANCELED|CANCELLED)\s+")
TASK_STATUS = {"TODO": "todo", "LATER": "todo", "DOING": "doing", "NOW": "doing",
               "DONE": "done", "CANCELED": "canceled", "CANCELLED": "canceled"}


def links(text):
    """([[page]] names, ((block)) uuids) in `text`, outside code."""
    plain = CODE.sub(" ", text)
    return list(dict.fromkeys(WIKI.findall(plain))), list(dict.fromkeys(BLOCK_REF.findall(plain)))


def needs_verbatim(content):
    return "::" in content or "\n" in content or "#" in content


def blocks_markdown(blocks, token):
    lines, verbatim = [], {}

    def walk(nodes, depth):
        for node in nodes:
            content = node["content"]
            if needs_verbatim(content):
                key = f"{token}-{len(verbatim)}"
                verbatim[key] = content
                content = key
            lines.append("\t" * depth + "- " + content)
            walk(node.get("children") or [], depth + 1)

    walk(blocks, 0)
    return "\n".join(lines) + "\n", verbatim


def escape_tree(blocks):
    return [dict(node, content=escape_number_tags(node.get("content") or ""),
                 children=escape_tree(node.get("children") or []))
            for node in blocks]


def preorder(blocks):
    for node in blocks:
        yield node
        yield from preorder(node.get("children") or [])


ORDER_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"


def order_after(key):
    """The :block/order key right after `key` (None: the first key).

    Logseq orders siblings by fractional-indexing keys: a head character that
    gives the length of an integer part in base 62 ("a" one digit, "b" two),
    then an optional fraction. Incrementing the integer part sorts after any
    fraction of the same integer."""
    if not key:
        return "a0"
    head = key[0]
    if "a" <= head <= "z":
        length = ord(head) - ord("a") + 2
    elif "A" <= head <= "Z":
        length = ord("Z") - ord(head) + 2
    else:
        raise LogseqError(f"not an order key: {key!r}")
    digits = list(key[1:length])
    for i in reversed(range(len(digits))):
        n = ORDER_DIGITS.index(digits[i]) + 1
        if n < len(ORDER_DIGITS):
            digits[i] = ORDER_DIGITS[n]
            return head + "".join(digits)
        digits[i] = "0"
    if head == "Z":
        return "a0"
    if head == "z":
        raise LogseqError(f"no order key after {key!r}")
    head = chr(ord(head) + 1)
    return head + "".join(digits + ["0"] if head > "a" else digits[1:])


def write(cfg, page, properties=None, blocks=None, parent=None):
    """Upsert `page` (under the namespace page `parent`, if given), set its
    properties, append `blocks` (a tree of {content, children?, tags?,
    properties?}). Returns (page id, block count)."""
    blocks = escape_tree(blocks or [])
    with session(cfg) as cli:
        graph = Graph(cli)
        page_id = graph.page(page)
        if parent:
            graph.set_parent(page_id, parent)
        values, tags = graph.properties(properties or {})
        args = []
        if values:
            args += ["--update-properties", edn(values)]
        if tags:
            args += ["--update-tags", edn(tags)]
        if args:
            cli.run("upsert", "page", "--id", str(page_id), *args)

        if not blocks:
            return page_id, 0

        token = f"@@logseq-db-{uuid.uuid4().hex}"
        text, verbatim = blocks_markdown(blocks, token)
        os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
        path = os.path.join(STATE_DIR, f"blocks-{os.getpid()}.md")
        with open(path, "w") as f:
            f.write(text)
        try:
            ids = cli.run("upsert", "block", "--target-id", str(page_id), "--pos", "last-child",
                          "--blocks-file", path)["result"]
        finally:
            os.unlink(path)

        nodes = list(preorder(blocks))
        if len(ids) != len(nodes):
            raise LogseqError(f"inserted {len(ids)} blocks, expected {len(nodes)}")
        for block_id, node in zip(ids, nodes):
            args = []
            content = node.get("content") or ""
            marker = TASK_MARKER.match(content)
            if marker:
                content = content[marker.end():]
            if marker or needs_verbatim(node.get("content") or ""):
                args += ["--content", content]
            values, tags = graph.properties(node.get("properties") or {})
            if values:
                args += ["--update-properties", edn(values)]
            tags += [graph.tag(t) for t in node.get("tags") or []]
            if tags:
                args += ["--update-tags", edn(tags)]
            if args:
                cli.run("upsert", "block", "--id", str(block_id), *args)
            if marker:
                cli.run("upsert", "task", "--id", str(block_id),
                        "--status", TASK_STATUS[marker.group(1)])
            if args and any(links(content)):
                graph.link(block_id, content)
        return page_id, len(ids)


def query(cfg, q):
    with session(cfg) as cli:
        return cli.query(q)


def find_pages(cfg, date, tags):
    """Pages whose `date` is `date` (YYYY-MM-DD) and that carry one of `tags`,
    with their properties by title: [{"title", "properties": {name: text}}]."""
    y, m, d = date.split("-")
    day = int(f"{y}{m}{d}")
    with session(cfg) as cli:
        graph = Graph(cli)
        date_ident = graph.property("date")[0]
        names = "#{" + " ".join(edn(t.lower()) for t in tags) + "}"
        q = ("[:find [?p ...] :where "
             f"[?p :{date_ident} ?j] [?j :block/journal-day {day}] "
             "[?p :block/tags ?t] [?t :block/name ?tn] "
             f"[(contains? {names} ?tn)]]")
        page_ids = cli.query(q) or []
        out = []
        for pid in sorted(set(page_ids)):
            # User property values are entities (a text value is a block of
            # its own), so each value's title is its text.
            rows = cli.query(
                "[:find ?pt ?vt :where "
                f"[{pid} ?a ?v] [(namespace ?a) ?ns] [(= ?ns \"user.property\")] "
                "[?prop :db/ident ?a] [?prop :block/title ?pt] [?v :block/title ?vt]]") or []
            title = cli.query(f"[:find [?t ...] :where [{pid} :block/title ?t]]") or [""]
            props = {}
            for pt, vt in rows:
                if vt:
                    props.setdefault(pt.lower(), []).append(vt)
            out.append({"title": title[0],
                        "properties": {k: " ".join(sorted(v)) for k, v in props.items()}})
        return out


def available(cfg):
    """The CLI runs and the graph is on this machine."""
    try:
        if cfg.desktop:
            return listed(Cli(cfg))
        with session(cfg):
            return True
    except (LogseqError, OSError, subprocess.SubprocessError):
        return False


def listed(cli):
    graphs = cli.run("graph", "list", graph=False) or {}
    names = graphs.get("graphs") or graphs.get("items") or []
    return any((g if isinstance(g, str) else g.get("name") or g.get("graph")) == cli.cfg.graph for g in names)


# The CLI creates an empty graph for any graph name it is given, and a failed
# `sync download` reports success and leaves one behind, so a listed graph may
# hold nothing. A downloaded one carries the server's graph id and the user's
# properties.
DOWNLOADED_QUERY = (
    '[:find ?v . :where [?k :db/ident :logseq.kv/graph-uuid] [?k :kv/value ?v]'
    ' [?p :db/ident ?i] [(namespace ?i) ?ns] [(= ?ns "user.property")]]'
)


def downloaded(cli):
    """The graph is listed and holds what the sync server has. Checked once,
    then remembered in a marker file, since the query starts a worker."""
    if not listed(cli):
        return False
    marker = os.path.join(STATE_DIR, f"downloaded-{cli.cfg.graph}")
    if os.path.exists(marker):
        return True
    if not cli.query(DOWNLOADED_QUERY):
        return False
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    open(marker, "w").close()
    return True


# --- CLI-only setup -----------------------------------------------------------


def _pkce():
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def _port_open(port, host="127.0.0.1"):
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex((host, port)) == 0


def login(cfg, use_browser=True, out=sys.stdout, inp=sys.stdin):
    """`logseq login` on a machine without a usable browser.

    The CLI only prints the authorize URL once login has finished and tries to
    open a browser before listening, so the URL is built here from a state and
    PKCE verifier handed to the CLI through its config.
    """
    if cfg.desktop:
        raise LogseqError("login is for CLI-only machines; the desktop app owns ~/logseq/auth.json here.")
    s = cfg.sync
    if not s.get("authorizeEndpoint"):
        raise LogseqError("sync.authorizeEndpoint is required for login.")
    client_id = resolve_value(s.get("clientId"))
    if not client_id:
        raise LogseqError(f"sync.clientId resolved to nothing: {describe_source(s.get('clientId'))}")
    state = secrets.token_urlsafe(24)
    verifier, challenge = _pkce()
    base = Cli(cfg).config_path
    with open(base) as f:
        text = f.read().rstrip().rstrip("}")
    path = os.path.join(STATE_DIR, f"login-{os.getpid()}.edn")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(f"{text} :open-browser false :oauth-state {edn(state)} :oauth-code-verifier {edn(verifier)}}}\n")
    url = s["authorizeEndpoint"] + "?" + urllib.parse.urlencode({
        "response_type": "code",
        "client_id": client_id,
        "scope": s.get("scope") or "openid email profile offline_access",
        "redirect_uri": CALLBACK_URI,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    proc = subprocess.Popen(list(cfg.cli) + ["login", "--config", path, "-o", "json"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        for _ in range(100):
            if _port_open(8765) or proc.poll() is not None:
                break
            time.sleep(0.1)
        if proc.poll() is not None:
            raise LogseqError(f"logseq login exited early: {proc.stdout.read()}{proc.stderr.read()}")

        w3m = shutil.which("w3m")
        if use_browser and w3m and inp.isatty():
            print("Sign in with w3m. Once it shows the callback page, quit with q.", file=out)
            subprocess.run([w3m, url])
            # The CLI answers the callback before it exchanges the code for tokens.
            with contextlib.suppress(subprocess.TimeoutExpired):
                proc.wait(timeout=30)
        if proc.poll() is None:
            print(f"Open this URL in a browser and sign in:\n\n{url}\n", file=out)
            print("Paste the URL the browser ends on (http://localhost:8765/auth/callback?...):", file=out)
            callback = inp.readline().strip()
            q = urllib.parse.parse_qs(urllib.parse.urlparse(callback).query)
            if q.get("state", [""])[0] != state:
                raise LogseqError("that URL is not this login's callback (state differs).")
            with contextlib.suppress(OSError):
                urllib.request.urlopen(CALLBACK_URI + "?" + urllib.parse.urlparse(callback).query, timeout=10).read()
        stdout, stderr = proc.communicate(timeout=60)
    finally:
        if proc.poll() is None:
            proc.kill()
        with contextlib.suppress(OSError):
            os.unlink(path)
    try:
        body = json.loads(stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError):
        body = {}
    if proc.returncode != 0 or body.get("status") != "ok":
        raise LogseqError(f"logseq login failed: {stdout or stderr}")
    return body.get("data") or {}


def _remove_graph(cli):
    with contextlib.suppress(LogseqError):
        cli.run("server", "stop")
    cli.run("graph", "remove")


def download(cfg):
    """Fetch the graph from the sync server the first time."""
    cli = Cli(cfg)
    try:
        if listed(cli):
            if downloaded(cli):
                raise LogseqError(f"{cfg.graph} is already downloaded.")
            # `sync download` refuses to run over the empty graph left behind.
            _remove_graph(cli)
        password = cfg.e2ee_password()
        args = ["sync", "download"] + (["--e2ee-password", password] if password else [])
        failure = None
        try:
            cli.run(*args, timeout_ms=1800000)
        except LogseqError as e:
            failure = e
        if not failure and downloaded(cli):
            return
        # A failed download creates the graph before it fails.
        if listed(cli):
            _remove_graph(cli)
        if failure:
            raise failure
    finally:
        with contextlib.suppress(LogseqError):
            cli.run("server", "stop")
    raise LogseqError(
        f"sync download reported success, but {cfg.graph} came down empty and was removed. "
        f"The worker log is under ~/logseq/graphs/Unlinked graphs/{cfg.graph}/; retry the download.")
