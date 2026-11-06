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


if __name__ == "__main__":
    unittest.main()
