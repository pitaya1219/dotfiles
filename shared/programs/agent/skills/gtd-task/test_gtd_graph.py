"""Tests for gtd_graph.py, the parts that do not need a graph.

    python3 test_gtd_graph.py
"""
import contextlib
import io
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gtd_graph as g  # noqa: E402


class TemplateNameTest(unittest.TestCase):
    def matches(self, title):
        return re.fullmatch(g.TEMPLATE_NAME, title) is not None

    def test_the_templates(self):
        for title in ("GTD", "GTD<Minimum>", "GTD<SDI>", "GTD<KrakenPJ>", "GTD<Learning>", "GTD<Chore>"):
            self.assertTrue(self.matches(title), title)

    def test_tasks_that_only_mention_gtd(self):
        for title in ("GTD TODO: Hermes E2EE", "Logseq の GTD まわり", "GTD<", "XGTD", "gtd"):
            self.assertFalse(self.matches(title), title)


class RenderTest(unittest.TestCase):
    def test_title_properties_and_sub_blocks(self):
        text = g.render("{{content}}", {"tags": ["Learning"], "area": ["personal"], "context": ["@agent", "@computer"]},
                        [(0, "**Purpose**"), (1, "why"), (0, "**Steps**")])
        self.assertEqual(text.splitlines(), [
            "- [ ] {{content}}",
            "  tags:: Learning",
            "  area:: personal",
            "  context:: @agent, @computer",
            "  - **Purpose**",
            "    - why",
            "  - **Steps**",
        ])

    def test_a_template_without_properties(self):
        self.assertEqual(g.render("Something", {}, []), "- [ ] Something")

    def test_a_newline_in_a_sub_block_does_not_split_it(self):
        self.assertEqual(g.render("t", {}, [(0, "two\nlines")]).splitlines(), ["- [ ] t", "  - two lines"])

    def test_the_output_is_what_logseq_write_reads(self):
        # The skill's own claim: the helper's output goes straight to logseq-write.
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logseq-write"))
        import logseq_write
        tree = logseq_write.convert_markdown(g.render("{{content}}", {"area": ["personal"]}, [(0, "background")]))
        self.assertEqual(tree[0]["content"], "TODO {{content}}")
        self.assertEqual(tree[0]["properties"], {"area": "personal"})
        self.assertEqual([c["content"] for c in tree[0]["children"]], ["background"])


class CommandLineTest(unittest.TestCase):
    def test_no_command_prints_the_usage(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(g.main([]), 2)
        self.assertIn("gtd_graph.py templates", out.getvalue())

    def test_template_needs_a_name(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(g.main(["template"]), 2)

    def test_an_unknown_command_prints_the_usage(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(g.main(["nonsense"]), 2)


class FakeGraph:
    """What property_names() reads: no user properties."""
    _props = {}

    def _load_props(self):
        pass


class UnknownTemplateTest(unittest.TestCase):
    class FakeCli:
        def query(self, q, inputs=None):
            return [["6aec1200-0000-4000-8000-000000000001", "GTD", "2025-12-06"],
                    ["6aec1200-0000-4000-8000-000000000002", "GTD<SDI>", "2026-06-18"]]

    def test_the_error_lists_what_exists(self):
        with self.assertRaises(SystemExit) as raised:
            g.cmd_template(self.FakeCli(), FakeGraph(), "GTD<Nope>")
        self.assertIn("GTD, GTD<SDI>", str(raised.exception))

    def test_the_name_is_case_insensitive(self):
        class Cli(self.FakeCli):
            def query(self, q, inputs=None):
                if "re-pattern" in q:
                    return [["6aec1200-0000-4000-8000-000000000002", "GTD<SDI>", "2026-06-18"]]
                return []  # no body block

        with self.assertRaises(SystemExit) as raised:
            g.cmd_template(Cli(), FakeGraph(), "gtd<sdi>")
        self.assertIn("no body block", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
