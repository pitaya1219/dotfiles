#!/usr/bin/env python3
"""会議録ページに付けるタグの判定。

    python3 tools/mtg-minutes/tests/test_page_tags.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from mtgcommon import page_tags, team_title  # noqa: E402


class PageTagsTest(unittest.TestCase):
    def test_one_on_one(self):
        for title in ["会議録 2026-01-15 [[山田さん]] on 1", "佐藤on1", "Kenさんとの 1 on 1", "1on1 振り返り"]:
            self.assertEqual(page_tags(title), ["1on1"], title)

    def test_other_meetings(self):
        for title in ["会議録 2026-01-15 開発チーム定例", "勉強会 Session 1", "Python 1on2 version 10"]:
            self.assertEqual(page_tags(title), [], title)


class TeamTitleTest(unittest.TestCase):
    def test_team_names_lose_brackets_and_variants(self):
        cases = {
            "[[電力Hub]] Daily": ("電力Hub Daily", "電力Hub"),
            "[[電力Hub]]定例": ("電力Hub定例", "電力Hub"),
            "[[電力Hub]]Review会": ("電力Hub Review会", "電力Hub"),
            "[[Platform Team]] 定例": ("PFチーム 定例", "PFチーム"),
            "[[プラットフォームチーム]]定例": ("PFチーム定例", "PFチーム"),
            "PFチーム Daily": ("PFチーム Daily", "PFチーム"),
        }
        for title, want in cases.items():
            self.assertEqual(team_title(title), want, title)

    def test_kraken_wide_and_other_meetings(self):
        for title in ["[[Hub Discussion]] 電力Hub改修要件", "[[Hub]]定例", "Hub Meeting", "[[山田さん]] on 1"]:
            self.assertEqual(team_title(title), (title, None), title)


if __name__ == "__main__":
    unittest.main()
