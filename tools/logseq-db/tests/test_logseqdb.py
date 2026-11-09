import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import logseqdb  # noqa: E402


class EdnTest(unittest.TestCase):
    def test_values(self):
        self.assertEqual(logseqdb.edn({":a/b": 1, ":c": [2, "x"]}), '{:a/b 1 :c [2 "x"]}')

    def test_string_with_quotes_and_japanese(self):
        self.assertEqual(logseqdb.edn('会議 "x"'), '"会議 \\"x\\""')

    def test_colon_text_with_space_is_a_string(self):
        self.assertEqual(logseqdb.edn(":not a keyword"), '":not a keyword"')


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
    def test_markdown_and_verbatim(self):
        blocks = [{"content": "**Overview**", "children": [
            {"content": "plain"},
            {"content": "mentions `tags:: x`"},
            {"content": "PR #519"},
            {"content": "two\nlines"},
        ]}]
        text, verbatim = logseqdb.blocks_markdown(blocks, "@@t")
        self.assertEqual(text, "- **Overview**\n\t- plain\n\t- @@t-0\n\t- @@t-1\n\t- @@t-2\n")
        self.assertEqual(list(verbatim.values()), ["mentions `tags:: x`", "PR #519", "two\nlines"])

    def test_preorder_matches_insert_order(self):
        blocks = [{"content": "a", "children": [{"content": "b"}]}, {"content": "c"}]
        self.assertEqual([n["content"] for n in logseqdb.preorder(blocks)], ["a", "b", "c"])

    def test_task_marker(self):
        m = logseqdb.TASK_MARKER.match("DONE closed")
        self.assertEqual(logseqdb.TASK_STATUS[m.group(1)], "done")
        self.assertIsNone(logseqdb.TASK_MARKER.match("TODOS are not tasks"))

    def test_links(self):
        u = "6aec60c8-8d0a-46a4-a039-3b24b0b14423"
        text = f"see [[Session/a b]], #[[c]] and (({u})); [[Session/a b]] again, not `[[code]]`"
        self.assertEqual(logseqdb.links(text), (["Session/a b", "c"], [u]))
        self.assertEqual(logseqdb.links("PR \\#519"), ([], []))


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

    def test_nothing_to_set(self):
        logseqdb.update(None, "block", 7, {}, [])


if __name__ == "__main__":
    unittest.main()
