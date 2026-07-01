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

1. `references/deepdive.md` に新しい `## 節` を追加する
2. `**トリガー**:` にマッチさせたいキーワード群を列挙（タイトル・背景から LLM がマッチ判定する）
3. `**追加質問**:` に、その種別で追加で聞くべき質問と、生成物のどのセクションを補強するかを書く
4. 表を扱う質問なら、`html_notes` にテーブルタグが無い点に注意（`references/html-rules.md`）

## 設定 (`~/.agent/asana.json`)

スキーマ: `{ "projectGid": "...", "todoSectionGid": "..." }`

- 未存在時は `SKILL.md` Step 1 のウィザードが対話で生成する（チーム配布向け）
- dotfiles オーナーは Nix で宣言 → 読み取り専用シンリンクで生成される:
  ```nix
  dotfiles.agent.asana = {
    projectGid = "1208405292637994";
    todoSectionGid = "1209218441201478";
  };
  ```

## ソース編集後の反映

このスキルのソースは `~/dotfiles/shared/programs/agent/skills/asana-create-task/`。編集後:

```bash
cd ~/dotfiles
nix run home-manager/master -- switch --flake .#$USER
```

`~/.claude/skills/asana-create-task/`（→ `~/.agent/skills/...`）に反映される。
