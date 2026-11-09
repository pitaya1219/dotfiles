#!/usr/bin/env python3
"""会議録ページに付けるタグの判定。

    python3 tools/mtg-minutes/tests/test_page_tags.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from mtgcommon import page_tags  # noqa: E402


class PageTagsTest(unittest.TestCase):
    def test_one_on_one(self):
        for title in ["会議録 2026-01-15 [[山田さん]] on 1", "佐藤on1", "Kenさんとの 1 on 1", "1on1 振り返り"]:
            self.assertEqual(page_tags(title), ["1on1"], title)

    def test_other_meetings(self):
        for title in ["会議録 2026-01-15 開発チーム定例", "勉強会 Session 1", "Python 1on2 version 10"]:
            self.assertEqual(page_tags(title), [], title)


if __name__ == "__main__":
    unittest.main()
