#!/usr/bin/env python3
"""議事録 Markdown → Logseq ブロックの変換。

    python3 tools/mtg-minutes/tests/test_md_to_blocks.py
"""
import importlib.machinery
import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "lib"))
loader = importlib.machinery.SourceFileLoader("mtg_minutes", str(ROOT / "bin" / "mtg-minutes"))
spec = importlib.util.spec_from_loader("mtg_minutes", loader)
mtg_minutes = importlib.util.module_from_spec(spec)
loader.exec_module(mtg_minutes)


class MdToBlocksTest(unittest.TestCase):
    def test_todo_items_are_plain_bullets(self):
        md = "## ToDo / ネクストアクション\n- [ ] 渋谷さん / PR を直す\n- [x] 山中さん / 済\n- TODO 全員 / 共有\nDONE 段落"
        items = [c["content"] for c in mtg_minutes.md_to_blocks(md)[0]["children"]]
        self.assertEqual(items, ["渋谷さん / PR を直す", "山中さん / 済", "全員 / 共有", "段落"])

    def test_other_text_is_kept(self):
        md = "## 決定事項\n- TODOS の扱いを決めた\n- [リンク](https://example.com)"
        items = [c["content"] for c in mtg_minutes.md_to_blocks(md)[0]["children"]]
        self.assertEqual(items, ["TODOS の扱いを決めた", "[リンク](https://example.com)"])


if __name__ == "__main__":
    unittest.main()
