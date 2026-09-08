"""Asana polling notifier: config, API access, event classification, delivery.

Split from bin/asana-notify so the classification and diffing logic can be
tested without a token or a network.
"""
import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request

CONFIG_PATH = os.path.expanduser("~/.agent/asana.json")
STATE_PATH = os.path.expanduser("~/.local/state/asana-notify/state.json")
API_BASE = "https://app.asana.com/api/1.0"

# A poll that finds nothing to say still rewrites the state file, so the sync
# token and the task snapshot advance together. Undelivered notifications ride
# along in the same file; this caps how many survive a long herdr outage.
MAX_PENDING = 50

STATE_VERSION = 1

# The points in a due date's life that are worth one toast each. Recording
# which one last fired, alongside the date, is what lets a missed deadline
# nudge once the morning after and then go quiet: keyed on the date alone the
# due-today toast consumes the entry and the overdue one can never be reached,
# and keyed on nothing at all a stale backlog rings every single poll.
STAGE_DUE = "due"
STAGE_OVERDUE = "overdue"


class ConfigError(RuntimeError):
    pass


class ApiError(RuntimeError):
    pass


def _resolve_value(cfg, key):
    """Resolve a config value that is a plain string, {"file": ...}, or
    {"command": ...}. Same contract as logseq_common._resolve_value, so a
    token can be kept in passage rather than in the Nix store.
    """
    val = cfg.get(key)
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
            try:
                out = subprocess.run(
                    val["command"], shell=True, capture_output=True, text=True, check=True
                )
                return out.stdout.strip()
            except subprocess.CalledProcessError:
                return ""
    return ""


def load_config(path=CONFIG_PATH):
    """Returns (token, project_gid, workspace_gid). project_gid and
    workspace_gid may be None; token may not.
    """
    if not os.path.exists(path):
        raise ConfigError(
            f"No config at {path}. Set dotfiles.agent.asana in your Nix profile."
        )
    with open(path) as f:
        cfg = json.load(f)
    token = _resolve_value(cfg, "token")
    if not token:
        raise ConfigError(
            f"token is empty after resolution. Add a personal access token to {path} "
            "(create one at https://app.asana.com/0/my-apps)."
        )
    return token, cfg.get("projectGid"), cfg.get("workspaceGid")


def load_state(path=STATE_PATH):
    try:
        with open(path) as f:
            state = json.load(f)
    except (OSError, ValueError):
        return {}
    if state.get("version") != STATE_VERSION:
        return {}
    return state


def save_state(state, path=STATE_PATH):
    state["version"] = STATE_VERSION
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


class Asana:
    def __init__(self, token, timeout=30):
        self.token = token
        self.timeout = timeout

    def get(self, path, **params):
        """GET an API path. Returns the decoded body. Raises ApiError on any
        non-2xx except 412, which the events endpoint uses to hand back a fresh
        sync token and is therefore the caller's business, not an error.
        """
        url = f"{API_BASE}{path}"
        if params:
            url = f"{url}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            if e.code == 412:
                try:
                    return json.loads(body)
                except ValueError:
                    raise ApiError(f"412 with unparseable body: {body[:200]}")
            if e.code == 401:
                raise ApiError("401 Unauthorized — the personal access token is invalid or revoked.")
            raise ApiError(f"{e.code} {e.reason} for {path}: {body[:200]}")
        except urllib.error.URLError as e:
            raise ApiError(f"cannot reach Asana ({e.reason}).")

    def me(self):
        return self.get("/users/me", opt_fields="gid,name,workspaces")["data"]

    def my_tasks(self, workspace_gid):
        """Incomplete tasks assigned to the token's owner, across the workspace."""
        tasks, offset = [], None
        while True:
            params = dict(
                assignee="me",
                workspace=workspace_gid,
                completed_since="now",
                opt_fields="name,due_on,permalink_url",
                limit=100,
            )
            if offset:
                params["offset"] = offset
            body = self.get("/tasks", **params)
            tasks.extend(body.get("data", []))
            offset = (body.get("next_page") or {}).get("offset")
            if not offset:
                return tasks

    def events(self, resource_gid, sync):
        """Returns (events, new_sync). The list is empty when Asana rejected the
        sync token and handed back a fresh one, which happens on the very first
        poll and again whenever a token goes stale — in both cases there is no
        history to report, only a new baseline.

        resource_subtype rides along on each event so classify_event can drop
        the system stories Asana writes for every move and completion without
        spending a request on each one.
        """
        params = {
            "resource": resource_gid,
            "opt_fields": "action,user.gid,resource.resource_subtype,resource.name",
        }
        if sync:
            params["sync"] = sync
        body = self.get("/events", **params)
        if body.get("errors") or not sync:
            return [], body.get("sync")
        return body.get("data", []), body.get("sync", sync)

    def story(self, gid):
        return self.get(
            f"/stories/{gid}",
            opt_fields="type,text,created_by.name,target.name,target.permalink_url",
        )["data"]

    def task(self, gid):
        return self.get(f"/tasks/{gid}", opt_fields="name,permalink_url")["data"]


def note(title, body, sound="request", gid=None):
    return {"title": title, "body": body, "sound": sound, "gid": gid}


def body_lines(*lines):
    """Join the parts of a toast body, dropping the ones that came back empty.

    A task with no permalink or a comment whose text is blank would otherwise
    leave an empty line in the middle of the body, where strip() cannot reach.
    """
    return "\n".join(l for l in lines if l)


def new_assignment_notes(previous_gids, tasks):
    """Tasks that appear in My Tasks for the first time.

    previous_gids is None on the very first run, which baselines silently
    rather than announcing every open task at once.
    """
    if previous_gids is None:
        return []
    known = set(previous_gids)
    return [
        note("Asana: 新しい割り当て",
             body_lines(t["name"], t.get("permalink_url")), gid=t["gid"])
        for t in tasks
        if t["gid"] not in known
    ]


def due_notes(tasks, already, today):
    """Tasks due today or overdue, announced once per (task, due date).

    Keyed by due date and stage as well as gid, so a task rings on its due
    date, once more the day it goes overdue, and then not again — while
    pushing the deadline out and hitting it afresh starts the pair over.

    `already` is None on the very first run, which records what is already due
    without announcing it — the same baseline new_assignment_notes takes, and
    for the same reason: a backlog of overdue tasks would otherwise arrive as
    one toast each the first time the notifier runs.
    """
    baseline = already is None
    already = already or {}
    out, updated = [], dict(already)
    for t in tasks:
        due = t.get("due_on")
        if not due or due > today:
            continue
        overdue = due < today
        stage = f"{due}/{STAGE_OVERDUE if overdue else STAGE_DUE}"
        if already.get(t["gid"]) == stage:
            continue
        updated[t["gid"]] = stage
        if baseline:
            continue
        label = "期限切れ" if overdue else "本日期限"
        out.append(note(
            f"Asana: {label}",
            body_lines(f"{t['name']} ({due})", t.get("permalink_url")),
            gid=t["gid"],
        ))
    # Drop tasks that left My Tasks so the map cannot grow without bound.
    live = {t["gid"] for t in tasks}
    return out, {gid: stage for gid, stage in updated.items() if gid in live}


def classify_event(event, me_gid):
    """Reduce a raw Asana event to what should be fetched and announced.

    Returns None for events that need no notification: anything the token's
    owner did themselves, deletions, and field changes that the My Tasks diff
    already reports (assignee) or that carry no signal on their own.
    """
    if (event.get("user") or {}).get("gid") == me_gid:
        return None
    action = event.get("action")
    resource = event.get("resource") or {}
    rtype = resource.get("resource_type")
    if rtype == "story" and action == "added":
        # Asana writes a story for every move, completion and field edit. The
        # subtype tells them apart without fetching the story, but only when
        # the caller asked for the field — absent, fall through and let the
        # fetch decide rather than dropping a real comment.
        subtype = resource.get("resource_subtype")
        if subtype and subtype != "comment_added":
            return None
        return {"kind": "story", "gid": resource["gid"]}
    if rtype == "task" and action == "added":
        return {"kind": "task_added", "gid": resource["gid"]}
    return None


def summarize(text, limit=140):
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def herdr_argv(n):
    """Build the `herdr notification show` invocation for one notification.

    Delivery is herdr's in-app toast rather than the macOS notification centre:
    a launchd-started process is its own responsible process, so it would need
    its own notification grant, and the toast renders wherever the TUI is
    attached including over SSH (shared/programs/herdr.nix sets
    ui.toast.delivery = "herdr").
    """
    return [
        "herdr", "notification", "show", n["title"],
        "--body", n["body"],
        "--sound", n.get("sound", "request"),
    ]
