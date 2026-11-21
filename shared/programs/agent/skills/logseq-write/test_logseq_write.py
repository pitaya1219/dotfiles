"""Tests for logseq_write.py's markdown conversion.

    python3 test_logseq_write.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import logseq_write as lw  # noqa: E402


def texts(blocks):
    return [(b["content"], texts(b.get("children") or [])) for b in blocks]


class PropertyLineTest(unittest.TestCase):
    def test_properties_belong_to_the_item_above(self):
        tree = lw.convert_markdown(
            "- [ ] ship it\n"
            "  priority:: High\n"
            "  area:: personal\n"
            "  context:: @agent, @computer\n"
            "  - background: why\n"
        )
        self.assertEqual(len(tree), 1)
        self.assertEqual(tree[0]["content"], "TODO ship it")
        self.assertEqual(tree[0]["properties"], {"priority": "High", "area": "personal", "context": "@agent, @computer"})
        self.assertEqual(texts(tree[0]["children"]), [("background: why", [])])

    def test_a_property_line_is_not_a_block(self):
        tree = lw.convert_markdown("- a\n  priority:: low\n- b\n")
        self.assertEqual([b["content"] for b in tree], ["a", "b"])
        self.assertNotIn("properties", tree[1])

    def test_properties_of_a_child_stay_on_the_child(self):
        tree = lw.convert_markdown("- parent\n  - child\n    deadline:: 2026-12-01\n")
        self.assertNotIn("properties", tree[0])
        self.assertEqual(tree[0]["children"][0]["properties"], {"deadline": "2026-12-01"})

    def test_the_value_may_be_a_link(self):
        tree = lw.convert_markdown("- x\n  project:: [[homelab]]\n  remind-on:: [[2026-12-01]]\n")
        self.assertEqual(tree[0]["properties"], {"project": "[[homelab]]", "remind-on": "[[2026-12-01]]"})

    def test_a_later_value_replaces_an_earlier_one(self):
        tree = lw.convert_markdown("- x\n  priority:: low\n  priority:: urgent\n")
        self.assertEqual(tree[0]["properties"], {"priority": "urgent"})


class StaysTextTest(unittest.TestCase):
    """Lines that look like properties but are not under a list item."""

    def test_a_paragraph_stays_a_block(self):
        tree = lw.convert_markdown("priority:: high\n")
        self.assertEqual(texts(tree), [("priority:: high", [])])

    def test_not_indented_deeper_than_the_item(self):
        tree = lw.convert_markdown("- a\npriority:: high\n")
        self.assertEqual(texts(tree), [("a", [("priority:: high", [])])])

    def test_after_a_heading_or_a_paragraph(self):
        tree = lw.convert_markdown("- a\n\n## Section\n  priority:: high\n")
        self.assertNotIn("properties", tree[0])
        tree = lw.convert_markdown("- a\nsome text\n  priority:: high\n")
        self.assertNotIn("properties", tree[0])

    def test_an_empty_value_is_text(self):
        # Left as the old converter left any paragraph, indent included.
        tree = lw.convert_markdown("- a\n  priority::\n")
        self.assertEqual(texts(tree), [("a", [("  priority::", [])])])

    def test_existing_conversion_is_unchanged(self):
        # Same result as before properties existed: a paragraph attaches under
        # the block above it.
        tree = lw.convert_markdown("# T\n## Overview\n- one\n  - two\n- [x] done\nplain\n")
        self.assertEqual(texts(tree), [("**Overview**", [("one", [("two", [])]), ("DONE done", [("plain", [])])])])


if __name__ == "__main__":
    unittest.main()
