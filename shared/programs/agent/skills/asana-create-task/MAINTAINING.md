# asana-create-task — 保守ガイド

このスキルを拡張・保守する時に読むファイル。`SKILL.md` は実行フローに徹し、育てる知識はここと `references/` に置く。

## ファイルの役割分担

| ファイル | 性格 | 更新頻度 | 何を書くか |
|---|---|---|---|
| `SKILL.md` | 実行パス（発火時に丸ごとコンテキストへ載る） | まれ | 手順のみ。**薄く保つ** |
| `references/template.md` | 準静的 | まれ | タスクの標準 7 セクション構造 |
| `references/html-rules.md` | **静的リファレンス** | Asana 仕様変更時のみ | `html_notes` の allowlist / エスケープ / リンク記法。幻覚防止 |
| `references/deepdive.md` | **育てるファイル** | 継続的 | 種別ごとの追加質問。観点が増えるたび追記 |
| `MAINTAINING.md` | メタ | 随時 | この保守ガイド |

原則: **SKILL.md を太らせない**。発火時に丸ごとコンテキストへ載るため、ドメイン知識は `references/` に逃がし、必要時に読ませる（progressive disclosure）。

## deepdive エントリの追加手順

`references/deepdive.md` に新しい `## 節` を追加し、各節を以下のフォーマットで書く:

1. `**トリガー**:` マッチさせたいキーワード群（タイトル・背景から LLM がマッチ判定する）
2. `**追加質問**:` その種別で追加で聞くべき質問
3. `**補強先**:` 生成物のどのセクションを補強するか
4. 表を扱う質問なら、`html_notes` にテーブルタグが無い点に注意（`references/html-rules.md`）

## 設定 (`~/.agent/asana.json`)

スキーマ: `{ "projectGid": "...", "todoSectionGid": "..." }`。
設定があれば利用し、無ければ `SKILL.md` Step 1 が対話で作成する。
