import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import logseqdb  # noqa: E402


class EdnTest(unittest.TestCase):
    def test_values(self):
        self.assertEqual(logseqdb.edn({":a/b": 1, ":c": [2, "x"]}), '{:a/b 1 :c [2 "x"]}')

    def test_string_with_quotes_and_japanese(self):
        self.assertEqual(logseqdb.edn('会議 "x"'), '"会議 \\"x\\""')

    def test_colon_text_with_space_is_a_string(self):
        self.assertEqual(logseqdb.edn(":not a keyword"), '":not a keyword"')

    def test_uuid(self):
        u = "6aec60c8-8d0a-46a4-a039-3b24b0b14423"
        self.assertEqual(logseqdb.edn([logseqdb.uuid.UUID(u)]), f'[#uuid "{u}"]')


class TransitTest(unittest.TestCase):
    def test_escapes_tag_characters(self):
        self.assertEqual(logseqdb.transit_str("~ 契約 ~"), "~~ 契約 ~")
        self.assertEqual(logseqdb.transit_str("^ x"), "~^ x")
        self.assertEqual(logseqdb.transit_str("`#team-elec-hub` text"), "~`#team-elec-hub` text")
        self.assertEqual(logseqdb.transit_str("plain ~"), "plain ~")
        self.assertEqual(logseqdb.transit_str(""), "")


class RefsTest(unittest.TestCase):
    def test_split(self):
        self.assertEqual(logseqdb.split_refs("#work #[[home server]] [[x]]"), ["work", "home server", "x"])

    def test_plain(self):
        self.assertEqual(logseqdb.split_refs("middle"), ["middle"])

    def test_date(self):
        self.assertEqual(logseqdb.DATE.match("[[2026-11-06]]").groups(), ("2026", "11", "06"))
        self.assertIsNone(logseqdb.DATE.match("2026-07-01 to 2026-07-04"))


class EscapeTest(unittest.TestCase):
    def test_numbers_escaped(self):
        self.assertEqual(logseqdb.escape_number_tags("PR #400 and (#12)"), "PR \\#400 and (\\#12)")

    def test_left_alone(self):
        for text in ["#homelab", "already \\#400", "`#400`", "```\n#400\n```",
                     "https://x/pulls/400#issuecomment-1", "&#400;", "a#400"]:
            self.assertEqual(logseqdb.escape_number_tags(text), text, text)

    def test_tree(self):
        tree = logseqdb.escape_tree([{"content": "#1", "children": [{"content": "#2"}]}])
        self.assertEqual(tree[0]["children"][0]["content"], "\\#2")


class BlocksTest(unittest.TestCase):
    def test_rows_keep_text_as_written(self):
        texts = ["`#team-elec-hub` text", "#reception-distr-hub plain", "PR \\#486", "key:: value", "two\nlines"]
        blocks = [{"content": "**Overview**", "children": [{"content": t} for t in texts]}]
        rows = logseqdb.insert_rows(blocks)
        self.assertEqual([title for _, _, title in rows], ["**Overview**"] + texts)
        root = rows[0][0]
        self.assertEqual([parent for _, parent, _ in rows], [None] + [root] * len(texts))

    def test_rows_follow_preorder(self):
        blocks = [{"content": "a", "children": [{"content": "b"}]}, {"content": "TODO c"}]
        rows = logseqdb.insert_rows(blocks)
        self.assertEqual([(p is None, t) for _, p, t in rows], [(True, "a"), (False, "b"), (True, "c")])
        self.assertEqual(rows[1][1], rows[0][0])
        self.assertEqual(len({u for u, _, _ in rows}), 3)

    def test_preorder_matches_insert_order(self):
        blocks = [{"content": "a", "children": [{"content": "b"}]}, {"content": "c"}]
        self.assertEqual([n["content"] for n in logseqdb.preorder(blocks)], ["a", "b", "c"])

    def test_insert_keeps_uuids_and_titles(self):
        page = "11111111-1111-1111-1111-111111111111"
        rows = [("aaaaaaaa-0000-0000-0000-000000000001", None, "`#x` y"),
                ("aaaaaaaa-0000-0000-0000-000000000002", "aaaaaaaa-0000-0000-0000-000000000001", "#z")]
        cli, ops = InsertCli(page, {rows[0][0]: 5, rows[1][0]: 6}), []
        cli._outliner = ops.extend
        self.assertEqual(cli.insert_blocks(1, rows), [5, 6])
        op, (blocks, target, opts) = ops[0]
        self.assertEqual((op, target), ("~:insert-blocks", "~u" + page))
        self.assertEqual(blocks[0], ["^ ", "~:block/uuid", "~u" + rows[0][0], "~:block/title", "~`#x` y"])
        self.assertEqual(blocks[1][-2:], ["~:block/parent", ["~:block/uuid", "~u" + rows[0][0]]])
        self.assertEqual(opts[opts.index("~:replace-empty-target?") + 1], False)

    def test_insert_fails_when_a_block_is_missing(self):
        rows = [("aaaaaaaa-0000-0000-0000-000000000001", None, "a")]
        cli = InsertCli("11111111-1111-1111-1111-111111111111", {})
        cli._outliner = lambda ops: None
        with self.assertRaisesRegex(logseqdb.LogseqError, "not found"):
            cli.insert_blocks(1, rows)

    def test_remove_inserted_deletes_only_what_exists(self):
        top = ["aaaaaaaa-0000-0000-0000-000000000001", "aaaaaaaa-0000-0000-0000-000000000002"]
        cli = InsertCli("p", {top[0]: 5})
        logseqdb.remove_inserted(cli, top)
        self.assertEqual(cli.deleted, [[top[0]]])

    def test_task_marker(self):
        m = logseqdb.TASK_MARKER.match("DONE closed")
        self.assertEqual(logseqdb.TASK_STATUS[m.group(1)], "done")
        self.assertIsNone(logseqdb.TASK_MARKER.match("TODOS are not tasks"))

    def test_links(self):
        u = "6aec60c8-8d0a-46a4-a039-3b24b0b14423"
        text = f"see [[Session/a b]], #[[c]] and (({u})); [[Session/a b]] again, not `[[code]]`"
        self.assertEqual(logseqdb.links(text), (["Session/a b", "c"], [u]))
        self.assertEqual(logseqdb.links("PR \\#519"), ([], []))


class InsertCli(logseqdb.Cli):
    """A graph whose page has `page_uuid` and whose blocks are `existing`
    ({uuid: entity id})."""

    def __init__(self, page_uuid, existing):
        self.page_uuid, self.existing, self.deleted = page_uuid, existing, []

    def query(self, q, inputs=None):
        if ":find ?u ." in q:
            return self.page_uuid
        wanted = [str(u) for u in inputs[0]]
        if ":find ?u ?e" in q:
            return [[u, self.existing[u]] for u in wanted if u in self.existing]
        return [u for u in wanted if u in self.existing]

    def delete_blocks(self, block_uuids):
        self.deleted.append(block_uuids)


class FakeCli:
    def __init__(self, statuses):
        self.cfg = type("Cfg", (), {"graph": "g", "e2ee_password": lambda self: None})()
        self.statuses = list(statuses)

    def run(self, *args, **kwargs):
        if args[:2] == ("sync", "status"):
            return self.statuses.pop(0) if len(self.statuses) > 1 else self.statuses[0]
        return {}


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.grace, logseqdb.DIVERGED_GRACE = logseqdb.DIVERGED_GRACE, 0
        self.sleep, logseqdb.time.sleep = logseqdb.time.sleep, lambda s: None

    def tearDown(self):
        logseqdb.DIVERGED_GRACE = self.grace
        logseqdb.time.sleep = self.sleep

    def status(self, local, remote, pending=0, tx=10):
        return {"pending-local": pending, "local-tx": tx, "remote-tx": tx,
                "local-checksum": local, "remote-checksum": remote}

    def test_settles(self):
        cli = FakeCli([self.status("a", "b", pending=1), self.status("a", "a")])
        self.assertEqual(logseqdb.sync_and_wait(cli)["local-checksum"], "a")

    def test_diverged(self):
        cli = FakeCli([self.status("a", "b")])
        with self.assertRaisesRegex(logseqdb.LogseqError, "diverged"):
            logseqdb.sync_and_wait(cli, timeout=60)


class OrderTest(unittest.TestCase):
    def test_after(self):
        self.assertEqual(logseqdb.order_after(None), "a0")
        self.assertEqual(logseqdb.order_after("bCz"), "bD0")
        self.assertEqual(logseqdb.order_after("b1X"), "b1Y")
        self.assertEqual(logseqdb.order_after("a6G"), "a7")
        self.assertEqual(logseqdb.order_after("az"), "b00")
        self.assertEqual(logseqdb.order_after("Zz"), "a0")

    def test_sorts_after(self):
        for key in ["a0", "a6G", "az", "bCz", "bzz", "Zz"]:
            self.assertGreater(logseqdb.order_after(key), key)


class UpdateTest(unittest.TestCase):
    def test_properties_and_tags_go_in_separate_upserts(self):
        calls = []

        class FakeCli:
            def run(self, *args):
                calls.append(args)

        logseqdb.update(FakeCli(), "page", 7, {":user.property/topic-x": [9]}, [":user.class/Guide-y"])
        self.assertEqual(calls, [
            ("upsert", "page", "--id", "7", "--update-properties", "{:user.property/topic-x [9]}"),
            ("upsert", "page", "--id", "7", "--update-tags", "[:user.class/Guide-y]"),
        ])

    def test_one_property_per_upsert(self):
        calls = []

        class FakeCli:
            def run(self, *args):
                calls.append(args)

        logseqdb.update(FakeCli(), "page", 7, {":user.property/team-x": [9], ":user.property/project-y": [8]}, [])
        self.assertEqual(calls, [
            ("upsert", "page", "--id", "7", "--update-properties", "{:user.property/team-x [9]}"),
            ("upsert", "page", "--id", "7", "--update-properties", "{:user.property/project-y [8]}"),
        ])

    def test_nothing_to_set(self):
        logseqdb.update(None, "block", 7, {}, [])


class ChoiceTest(unittest.TestCase):
    class FakeCli:
        """A graph with the text property `model`, whose choices are `choices`."""

        def __init__(self, choices):
            self.choices = dict(choices)
            self.added = []

        def run(self, *args, **kwargs):
            if args[:2] == ("list", "property"):
                return {"items": [{"db/ident": "user.property/model-x", "block/title": "model",
                                   "logseq.property/type": "default"}]}
            return {}

        def query(self, q, inputs=None):
            if "closed-value-property" in q:
                return [[t, i] for t, i in self.choices.items()]
            if "#uuid" in q:
                return self.choices.get(self.added[-1])
            return None

        def add_choice(self, ident, title):
            self.added.append(title)
            self.choices[title] = 100 + len(self.added)
            return "new-uuid"

    def test_existing_choice(self):
        cli = self.FakeCli({"claude-opus-5-5": 7})
        values, _ = logseqdb.Graph(cli).properties({"model": "claude-opus-5-5"})
        self.assertEqual(values, {":user.property/model-x": 7})
        self.assertEqual(cli.added, [])

    def test_new_value_becomes_a_choice(self):
        cli = self.FakeCli({"claude-opus-5-5": 7})
        values, _ = logseqdb.Graph(cli).properties({"model": "mistral-large-4-0-3"})
        self.assertEqual(cli.added, ["mistral-large-4-0-3"])
        self.assertEqual(values, {":user.property/model-x": 101})

    def test_free_text_stays_text(self):
        values, _ = logseqdb.Graph(self.FakeCli({})).properties({"model": "x"})
        self.assertEqual(values, {":user.property/model-x": "x"})


class TaskFieldsTest(unittest.TestCase):
    def test_split_keeps_user_properties_apart(self):
        task, rest = logseqdb.split_task_fields({"Priority": "High", "area": "work", "STATUS": "done"})
        self.assertEqual(task, {"priority": "High", "status": "done"})
        self.assertEqual(rest, {"area": "work"})

    def test_priority_and_dates(self):
        args, waiting = logseqdb.parse_task({"priority": "Medium", "deadline": "2026-12-01",
                                             "scheduled": "[[2026-11-30]]"})
        self.assertEqual(args, ["--priority", "medium", "--deadline", "2026-12-01", "--scheduled", "2026-11-30"])
        self.assertFalse(waiting)

    def test_marker_sets_the_status(self):
        self.assertEqual(logseqdb.parse_task({}, "todo"), (["--status", "todo"], False))

    def test_explicit_status_beats_the_marker(self):
        self.assertEqual(logseqdb.parse_task({"status": "Backlog"}, "todo"), (["--status", "backlog"], False))

    def test_status_spellings(self):
        for given, wanted in [("In Review", "in-review"), ("in progress", "doing"), ("Cancelled", "canceled"),
                              ("later", "todo")]:
            self.assertEqual(logseqdb.parse_task({"status": given})[0], ["--status", wanted], given)

    def test_waiting_is_made_a_task_then_replaced(self):
        # logseq-cli rejects --status waiting, so it is made a Task as Backlog
        # first and the Waiting choice is set afterwards.
        for given in ("Waiting", "wait"):
            self.assertEqual(logseqdb.parse_task({"status": given}), (["--status", "backlog"], True), given)

    def test_blank_values_are_ignored(self):
        self.assertEqual(logseqdb.parse_task({"priority": "  ", "status": ""}), ([], False))

    def test_bad_values_fail_before_anything_is_written(self):
        for task in ({"priority": "soon"}, {"status": "someday"}, {"deadline": "next week"},
                     {"scheduled": "2026-13"}):
            with self.assertRaises(logseqdb.LogseqError, msg=str(task)):
                logseqdb.parse_task(task)


class ManyChoiceTest(unittest.TestCase):
    class FakeCli(ChoiceTest.FakeCli):
        """`context` takes several values, each one of its choices."""

        def run(self, *args, **kwargs):
            if args[:2] == ("list", "property"):
                return {"items": [{"db/ident": "user.property/context-x", "block/title": "context",
                                   "logseq.property/type": "default", "db/cardinality": "db.cardinality/many"}]}
            return {}

    def test_several_choices_go_in_as_a_list(self):
        cli = self.FakeCli({"@agent": 5, "@computer": 6})
        values, _ = logseqdb.Graph(cli).properties({"context": "@agent, @computer"})
        self.assertEqual(values, {":user.property/context-x": [5, 6]})

    def test_one_choice_is_still_a_list(self):
        values, _ = logseqdb.Graph(self.FakeCli({"@home": 9})).properties({"context": "@home"})
        self.assertEqual(values, {":user.property/context-x": [9]})

    def test_new_choice_is_added(self):
        cli = self.FakeCli({"@agent": 5})
        values, _ = logseqdb.Graph(cli).properties({"context": "@agent, @pair"})
        self.assertEqual(cli.added, ["@pair"])
        self.assertEqual(values, {":user.property/context-x": [5, 101]})


class WriteTaskTest(unittest.TestCase):
    """write() end to end against a recording graph: which CLI calls a block's
    properties turn into, and that a bad value writes nothing."""

    class RecordingCli:
        def __init__(self):
            self.calls, self.inserted = [], []

        def run(self, *args, **kwargs):
            self.calls.append(args)
            if args[:2] == ("list", "property"):
                return {"items": [{"db/ident": "user.property/context-x", "block/title": "context",
                                   "logseq.property/type": "default", "db/cardinality": "db.cardinality/many"}]}
            return {}

        def query(self, q, inputs=None):
            if "closed-value-property" in q:
                if ":logseq.property/status" in str(inputs):
                    return [["Waiting", 77], ["Todo", 78]]
                return [["@agent", 5]]
            return None

        def insert_blocks(self, target_id, rows):
            self.inserted = rows
            return list(range(200, 200 + len(rows)))

        def delete_blocks(self, uuids):
            self.calls.append(("delete", uuids))

    def run_write(self, blocks):
        cli = self.RecordingCli()
        session = mock.MagicMock()
        session.__enter__.return_value = cli
        session.__exit__.return_value = False  # a truthy value here would swallow errors
        with mock.patch.object(logseqdb, "session", return_value=session), \
                mock.patch.object(logseqdb.Graph, "page", return_value=1):
            logseqdb.write(None, "2026-11-21", blocks=blocks)
        return cli

    def upserts(self, cli):
        return [c for c in cli.calls if c[:2] == ("upsert", "task")]

    def test_priority_context_and_marker_together(self):
        cli = self.run_write([{"content": "TODO ship it",
                               "properties": {"priority": "High", "context": "@agent", "deadline": "2026-12-01"}}])
        self.assertEqual(self.upserts(cli), [("upsert", "task", "--id", "200", "--status", "todo",
                                              "--priority", "high", "--deadline", "2026-12-01")])
        props = [c for c in cli.calls if c[:2] == ("upsert", "block") and "--update-properties" in c]
        self.assertEqual(props, [("upsert", "block", "--id", "200", "--update-properties",
                                  "{:user.property/context-x [5]}")])

    def test_priority_alone_makes_a_task(self):
        cli = self.run_write([{"content": "plain block", "properties": {"priority": "low"}}])
        self.assertEqual(self.upserts(cli), [("upsert", "task", "--id", "200", "--priority", "low")])

    def test_waiting_sets_the_choice_after_the_task(self):
        cli = self.run_write([{"content": "waiting on someone", "properties": {"status": "Waiting"}}])
        self.assertEqual(self.upserts(cli), [("upsert", "task", "--id", "200", "--status", "backlog")])
        last = [c for c in cli.calls if "--update-properties" in c][-1]
        self.assertEqual(last, ("upsert", "block", "--id", "200", "--update-properties",
                                "{:logseq.property/status 77}"))

    def test_children_are_not_tasks_unless_asked(self):
        cli = self.run_write([{"content": "TODO parent", "children": [{"content": "background: text"}]}])
        self.assertEqual(self.upserts(cli), [("upsert", "task", "--id", "200", "--status", "todo")])

    def test_a_bad_value_writes_nothing(self):
        opened = mock.Mock(side_effect=AssertionError("the graph must not be opened"))
        blocks = [{"content": "a"}, {"content": "b", "properties": {"priority": "soon"}}]
        with mock.patch.object(logseqdb, "session", opened):
            with self.assertRaises(logseqdb.LogseqError):
                logseqdb.write(None, "p", blocks=blocks)
        opened.assert_not_called()


if __name__ == "__main__":
    unittest.main()
