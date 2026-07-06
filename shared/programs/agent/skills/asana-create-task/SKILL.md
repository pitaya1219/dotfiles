---
name: asana-create-task
description: Create a templated task in the Elec Hub Asana project through dialogue — gather materials/Slack first, draft each section, then register via html_notes
user-invocable: true
version: 1.0.0
---

Elec Hub（Asana）に、固定テンプレートに沿ったタスクを対話的に作成するスキル。
資料・Slack を起点に各セクションのドラフトを生成し、Asana の `html_notes`（制限付き HTML）で登録する。

> **このスキルを拡張・保守する時は、先に `MAINTAINING.md` を読むこと。** deepdive の追加手順・ファイルの役割分担を記載。

## Step 1: 設定ロード（無ければ対話で作成）

`~/.agent/asana.json` から `projectGid` / `todoSectionGid` を読む。**設定があれば利用、無ければ対話で作成する**:

1. `mcp__claude_ai_Asana__asana_typeahead_search`（`resource_type=project`）でプロジェクトを候補提示 → 選択（`projectGid`）
2. `mcp__claude_ai_Asana__asana_get_project_sections` で投入先セクションを候補提示 → 選択（`todoSectionGid`）
3. `{ "projectGid": "...", "todoSectionGid": "..." }` をプレーン JSON で `~/.agent/asana.json` に書き込む

## Step 2: 資料・Slack を起点に収集

タスク本文は**ユーザーが書くのではなく、対話からエージェントが生成する**。まず素材を集める:

1. ユーザーに **資料 URL / 関連 Slack スレッド** を尋ねる
2. 内容を取得する:
   - Slack: `mcp__claude_ai_Slack__slack_read_thread`（スレッド URL から channel/ts を解決）
   - その他 URL・ドキュメント: `WebFetch`
3. （任意・できれば）**関連タスクの曖昧検索**: キーワードがあれば `mcp__claude_ai_Asana__asana_search_tasks`（`projects_any=<projectGid>`, `text=<keyword>`, `completed=false`）で **設定プロジェクト内に限定** して候補を提示。ユーザーが選んだら `mcp__claude_ai_Asana__asana_get_task` で本文を取得。タスク URL の直指定も可（URL 末尾の数値が GID）

## Step 3: テンプレートに沿ってドラフト生成

`references/template.md` の 7 セクション構造に沿い、Step 2 の素材から各セクションのドラフトを生成する。

- **収集は資料起点**だが、**出力はテンプレの正規順**（背景 → … → 資料・関連するSlackスレッド）に整える
- 各セクションをユーザーと確認・補正する。埋まらないセクションは質問して埋めるか、明示的に「なし」とする

## Step 4: 対象リポジトリの解決

「対象のリポジトリ」はユーザーが**略称**（例 `kraken-cdk`、`org/repo`）で指定できる。フル URL に解決する:

1. Gitea: `mcp__gitea__search_repos`（`query=<略称>`）で照会
2. 見つからなければ GitHub: `gh search repos <略称> --json fullName,url --limit 5`（`tokyogas-tech` org 等）
3. 一意に解決できなければユーザーにフル URL を確認する

## Step 5: 種別別の深掘り（deepdive）

`references/deepdive.md` を読み、**タイトル・背景のキーワード**から該当するトリガー節を選ぶ（LLM 判断）。
該当があれば、その節の追加質問をユーザーに投げて内容を補強する。該当が無ければスキップ。

## Step 6: タスク作成（html_notes で登録）

1. 本文を `references/html-rules.md` に従い Asana の `html_notes` へ変換する（**Markdown ではなく制限付き HTML**。allowlist・エスケープ・リンク記法は html-rules.md が正本）
2. 作成（1 ステップで section まで指定できる）:
   ```
   mcp__claude_ai_Asana__asana_create_task(
     name       = <タイトル>,
     project_id = <projectGid>,
     section_id = <todoSectionGid>,   # ToDo（カンバン）へ配置
     html_notes = <変換後HTML>
   )
   ```
3. `html_notes` 起因で失敗する場合（`XML is invalid` 等）のみ、`notes`（プレーン）で作成 → `mcp__claude_ai_Asana__asana_update_task`（`html_notes=...`）の 2 ステップにフォールバックする

## Step 7: 報告

作成したタスクの URL を提示して完了。section は作成時に指定済み（`asana_update_task` では section は移動しない点に注意）。
