# asana-notify

Asana を定期的に見て、変化を herdr のトーストで知らせる。

ブラウザで Asana のタブを開きっぱなしにする理由は通知だけなので、その通知だけを
取り出したもの。タブ1枚が数百MB常駐するのに対し、こちらは launchd が数秒だけ
プロセスを起こして終わる。

## 何を通知するか

2系統を見ている。

| 系統 | 取得元 | 通知 |
|---|---|---|
| 自分に割り当てられたタスク | `GET /tasks?assignee=me&workspace=…&completed_since=now` | 新しい割り当て / 本日期限 / 期限切れ |
| ボードのイベント | `GET /events?resource=<projectGid>` | 他人が付けたコメント / ボードに増えたタスク |

意図的に鳴らさないもの:

- 自分の操作(`event.user.gid` が自分)。自分で書いたコメントで自分に通知しても意味がない
- システムが書いた story(「〜に移動しました」「完了しました」)。人が打った文字だけを拾う。
  判定は `/events` に `opt_fields` で `resource.resource_subtype` を載せて行うので、
  落とすものを `/stories/{gid}` で取りに行かない
- 自分の割り当てとして既に鳴らすタスクが、同じポーリングで「ボードに増えた」として
  重なる分。合流点で畳む。コメントは畳まない(「田中のコメント」は割り当て通知とは
  別の情報)
- `assignee` の変更。My Tasks 側の差分が同じことを拾うので、二重に鳴らさない
- 削除・ボードからの除外

期限は1つのタスクにつき2回まで鳴る。**期限当日に「本日期限」、その翌日に一度だけ
「期限切れ」**、以降は放置していても黙る。見逃しに一度だけ気付ければよく、溜まった
backlog が毎朝鳴るのは邪魔でしかない、という線引き。

期限日を動かして再び到達すれば、その新しい期限日でまた2回鳴る。

state に記録するのは期限日だけでなく段階(`due` / `overdue`)も含む。期限日だけを
鍵にすると当日の通知が組を使い切ってしまい、「期限切れ」に永久に到達しない。

## 設定

`~/.agent/asana.json`(`dotfiles.agent.asana` が生成する)を読む。

```json
{
  "projectGid": "1208405292637994",
  "todoSectionGid": "1209218441201478",
  "token": { "command": "passage show asana/pat" }
}
```

- `token` — 必須。Personal Access Token。文字列 / `{ "file": … }` / `{ "command": … }`
  のいずれか(`logseq.json` と同じ規約)。実体を Nix store に焼かないため
  `{ "command": "passage show …" }` を使う
- `projectGid` — 任意。無い場合はコメント通知が無効になり、自分の割り当てだけを見る
- `workspaceGid` — 任意。省略時は `/users/me` の先頭のワークスペース

PAT は https://app.asana.com/0/my-apps で発行する。管理者の承認は要らない。

## 使い方

```
asana-notify                 # 1回見て、あれば通知して終了(launchd 用)
asana-notify --check         # 設定とトークンの確認だけ。通知しない
asana-notify --dry-run       # 通知内容を標準出力に出すだけ。state も書かない
asana-notify --watch         # 自分で回り続ける(既定 300 秒間隔)
asana-notify --reset         # 基準を捨てて次回に取り直す
asana-notify --config PATH   # 別の設定ファイルを使う(動作確認用)
```

初回は何も鳴らさず現状を基準として記録する。割り当ても期限も両方で、そうしないと
未完了タスクと溜まった期限切れが一斉に鳴る。

## state

`~/.local/state/asana-notify/state.json`。

```
sync           Events API の sync token
my_task_gids   前回見た自分のタスク。新しい割り当ての判定に使う
due_notified   {タスク gid: "期限日/段階"}。段階は due か overdue
pending        herdr に届かなかった通知。次回に持ち越す(最大 50 件)
me_gid         自分の gid。自分の操作を除くのに使う
workspace_gid  ワークスペースの gid
```

`me_gid` と `workspace_gid` はトークンが変わらない限り不変なので、キャッシュして
`/users/me` を毎回叩かないようにしている。定常状態のポーリングは2リクエスト
(`/tasks` と `/events`)。別のユーザーのトークンに差し替えたときは `--reset`。

`version` が合わない state は読まずに捨てる。形を変えたときに古い state を
読んで誤爆させないため。

herdr が起きていないあいだの通知は `pending` に溜まり、次に起きたときにまとめて
出る。届かなかった通知で state を進めてしまわないので、取りこぼしはない。

## launchd

`programs.asana-notify.agent.enable` で `StartInterval` の一発実行として登録する。
常駐ループ(`--watch`)ではないのは、常駐している Asana タブを消すために作った
ものが常駐していては本末転倒だから。間隔は 300 秒固定で、下限を決めるのは Asana の
レート制限であって、ローカルのメモリではない。

`EnvironmentVariables.PATH` を明示しているのは、トークンをコマンド(`passage` など)
で取る以上必要だから。launchd が agent に渡すのは `/usr/bin:/bin:/usr/sbin:/sbin`
だけで、`home.packages` 由来のものは何も見えない。

ログは `~/.local/share/asana-notify.log` と `~/.local/share/asana-notify-error.log`。

## テスト

```
python3 tools/asana-notify/tests/test_asananotify.py
```

トークンもネットワークも要らない範囲、つまり「何を通知すると決めるか」だけを
固定している。Asana の応答そのものは `--dry-run` を実機で回して確かめる。
