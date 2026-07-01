# Asana html_notes 変換ルール（静的リファレンス）

Asana タスクの説明欄は **Markdown ではなく、Asana 独自の制限付き HTML (`html_notes`)** で登録する。
これはハルシネーション防止用の固定仕様リファレンス。Asana 仕様が変わった時のみ更新する。

## 大原則
- ルートは単一の `<body>...</body>`。整形式 XML であること
- **`<p>` は使用不可**（allowlist 外 → `XML is invalid` / 400）。段落は改行やリストで表現する
- Markdown 記法（`**bold**`, `- list`, `# heading`）は**そのまま渡らない**。必ず下記タグへ変換する

## 使用可能タグ（allowlist）
`<body> <strong> <em> <u> <s> <code> <ol> <ul> <li> <a> <blockquote> <pre> <h1> <h2> <hr/> <img>`

- **テーブルタグは無い** → 表は `<ul><li>` の入れ子で表現する
- 属性を付けられるのは `<a>` のみ。他タグに属性を付けると 400

## エスケープ
- URL 内やテキスト中の `&` は `&amp;` に必須変換（生の `&` は 400）
- `<`, `>` もテキストとして出す時は `&lt;` / `&gt;`

## リンク
- **Asana タスクへのメンション / リンク**: `<a data-asana-gid="GID"/>` → Asana が名前付きリンクへ自動展開（href は不要）
- **外部 URL**: `<a href="https://example.com/...">表示テキスト</a>`

## セクション見出し
テンプレの各セクション見出しは `<h2>` で出す。

## 骨組み例
```html
<body>
<h2>背景</h2>
既存タスク <a data-asana-gid="1214301237094692"/> の是正対応が漏れているため。
<h2>受入条件</h2>
<ul>
  <li>対象 SG のインバウンドが最小権限に是正されている</li>
  <li>疎通に影響が出ていないことを確認済み</li>
</ul>
<h2>資料・関連するSlackスレッド</h2>
<ul>
  <li><a href="https://example.com/doc?a=1&amp;b=2">設計メモ</a></li>
</ul>
</body>
```
