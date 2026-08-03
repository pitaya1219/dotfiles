# mtg-minutes

会議を録音し、**話者ラベル付き文字起こし** と **議事録** を生成して Logseq に会議ページを
自動作成するローカルツール群。会議中は自分/相手の発言をライブ字幕として画面に流せる。

- **音声処理は全てローカル**(ffmpeg + whisper.cpp / Apple Silicon Metal)。Claudeに渡すのは最終テキストのみ。
- 既存のノイズキャンセリング構成([[Macでノイズキャンセリング環境を構築する]])をそのまま録音機として活用。

## コマンド一覧

| コマンド | 役割 |
|----------|------|
| **`mtg`** | **会議中に叩くやつ。録音しながら自分/相手のライブ字幕を1画面に流す** |
| `mtg-rec` | 録音だけ(2トラック .mkv) |
| `mtg-live` | 相手のライブ字幕だけ |
| `mtg-self` | 自分のライブ字幕だけ |
| `mtg-minutes` | 録音(または文字起こしテキスト)から議事録を作って Logseq へ |

普段は `mtg` ひとつでよく、`mtg-rec` / `mtg-live` / `mtg-self` は単体で使いたいとき用。

```
        ┌ BlackHole 2ch (自分) ┬─ ffmpeg ─────┐
mtg ────┤                      └─ whisper-stream ─ 字幕(自分)
        │                                     ├─ 2トラック .mkv ─ mtg-minutes ─┬ transcript.txt
        └ BlackHole 16ch (相手)┬─ ffmpeg ─────┘                                ├ minutes.md
                               └─ whisper-stream ─ 字幕(相手)                  └ Logseq 会議ページ
```

```
[00:12] 相手: 来週のリリースなんですけど
[00:18] 自分: はい、木曜で調整してます
[00:25] 相手: じゃあ水曜までにレビューを
```

BlackHole は複数プロセスからの同時読み出しに対応しているので、同じデバイスを
「録音本体 + 無音検知 + ライブ字幕」が同時に開いても競合しない(実機で検証済み)。

OBS の2トラック録音(§2)を録音元にすることもできるが、`mtg` / `mtg-rec` を使うなら不要。

---

## 1. 依存(インストール済み)

| ツール | 用途 | 確認 |
|--------|------|------|
| ffmpeg | 音声抽出・変換 | `which ffmpeg`（home-manager 管理） |
| whisper-cpp | 文字起こし | `which whisper-cli`（home-manager 管理） |
| claude (CLI) | 議事録生成 | `which claude`（別管理・ambient） |
| whisperモデル(turbo / small) | `~/.cache/whisper-cpp/models/` | switch で自動取得(約1.6GB + 約0.5GB) |

### モデルについて

`shared/programs/mtg-minutes.nix` が `fetchurl` で取得し、`home-manager switch` で
`~/.cache/whisper-cpp/models/` に配置される（手動DL不要）。

| モデル | 用途 |
|--------|------|
| **turbo** (large-v3-turbo) | 既定。バッチ文字起こしもライブ字幕(両サイド)もこれ |
| **small** | バッテリー優先で軽くしたいとき用(`--self-model small` など) |

`base` を使いたい場合だけ **手動DL** が必要:

```bash
M=~/.cache/whisper-cpp/models
curl -L -o "$M/ggml-base.bin" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

> 手動DL済みの実ファイルが同じパスにある場合、home-manager は
> `cmp` で中身を比較し、**同一なら警告を出して symlink 作成をスキップする**
> (`Existing file ... will be skipped since they are the same`)。
> switch は失敗しないが、実ファイルが残るので store のコピーと二重に容量を食う。
> symlink に寄せて容量を返すなら、switch 前に消しておく:
> ```bash
> rm -f ~/.cache/whisper-cpp/models/ggml-large-v3-turbo.bin \
>       ~/.cache/whisper-cpp/models/ggml-small.bin
> ```
> 中身が違う場合のみ collision エラーになるが、その判定は実際のファイル配置
> (`writeBoundary`)より前に走るので、失敗しても何も変更されない。

指定したモデルが未配置でも即死はせず、turbo → small → base の順に代替して警告を出す。

## 2. OBS の設定(初回のみ・GUI操作)

既存構成は「マイク → OBS → BlackHole → 通話アプリ」。ここに **相手の声の録音** と **2トラック録音** を足す。

### 2-1. 相手の声をキャプチャするソースを追加
1. ソース → `+` → **「macOS スクリーンキャプチャ(音声)」/「Application Audio Capture」**
2. キャプチャ対象に通話アプリ(Google Chrome / Zoom / Teams)を選択
   - ※ OBS 32 は ScreenCaptureKit でアプリ音声を直接取得可(BlackHole増設不要)

### 2-2. 各ソースを別トラックに割り当て
1. 音声ミキサー → 各ソースの歯車 → **「オーディオの詳細プロパティ」**
2. トラック割り当て:
   - **マイク(UA80 + RNNoise)** → トラック **1** のみ
   - **相手の音声(アプリキャプチャ)** → トラック **2** のみ

### 2-3. 録音を2トラック出力に
1. 設定 → 出力 → 録画
2. 録画フォーマット: **mkv**(またはhybrid mp4)
3. 音声トラック: **1 と 2 にチェック**
4. 録画パス: `~/Movies`(既定)

> これで「Track0=自分 / Track1=相手」の2トラック録音になり、話者分離がタダで手に入る。

## 3. 使い方

会議が終わったら録音ファイルを指定して実行するだけ:

```bash
# 基本(文字起こし + 議事録 + Logseq書き込み)
mtg-minutes ~/Movies/2026-06-25_10-00-00.mkv --title "1on1 田中さん"

# Logseqに書かず手元だけ
mtg-minutes RECORDING.mkv --no-logseq

# 議事録なし(文字起こしのみ)
mtg-minutes RECORDING.mkv --no-minutes --no-logseq

# 録音が無い/失敗した場合: ライブ字幕ログから議事録を作る
mtg-minutes --transcript ~/Documents/mtg-minutes/live/live_20260731_100000.txt --title "1on1 田中さん"

# 録音音声を添付しない(容量節約・長尺会議など)
mtg-minutes RECORDING.mkv --no-attach-audio

# トラック番号を変える(自分=1, 相手=0 の場合など)
mtg-minutes RECORDING.mkv --self-track 1 --other-track 0
```

出力:
- `~/Documents/mtg-minutes/<日時>/transcript.txt` … 話者ラベル付き全文
- `~/Documents/mtg-minutes/<日時>/minutes.md` … 議事録
- Logseqページ「会議録 YYYY-MM-DD <title>」(議事録 + 録音プレーヤー + 文字起こし全文リンク)
  - 録音は全トラックを1本にミックスして `m4a` に変換し、グラフの `assets/` に配置 → `![録音](../assets/...)` で再生可能
  - 既定で添付ON。`--no-attach-audio` または config の `attach_audio: false` でOFF
  - **文字起こし全文は `assets/transcript_<日時>.txt` に置き、ページからはリンク参照**(長文でページが重くならないように)。assetsが解決できない時のみページ内に埋め込み
  - 議事録本文は logseq-write 規約で変換(`## 見出し`=トップレベル / 箇条書きは個別の子ブロック / `- [ ]`→`TODO`)

## 4. インストール(PATHに通す)

home-manager で管理する。`shared/programs/mtg-minutes.nix` が `bin/*` を nix パッケージ化し、
`ffmpeg` / `whisper-cpp`(whisper-cli・whisper-stream)を runtimeInputs として固定する。
r-shibuya プロファイルの imports に組み込み済みなので、switch すれば
`mtg` / `mtg-rec` / `mtg-live` / `mtg-self` / `mtg-minutes` が PATH に入る。

共通コードは `lib/mtgcommon.py` にあり、`$out/lib` に置かれる。各スクリプトが自分の
`../lib` を `sys.path` に足して読む(`PYTHONPATH` は使わない。子プロセスとして呼ぶ
`claude` CLI などに影響させないため)。

```bash
home-manager switch --flake .#r-shibuya
```

`claude` CLI は別管理(ambient PATH)。turbo モデルも switch で自動配置される(§1 参照)。

## 5. 設定の上書き

`~/.config/mtg-minutes/config.json` を **home-manager が宣言管理**する。
`programs.mtg-minutes.settings` に書いたキーが書き込まれる(read-only symlink になる):

```nix
programs.mtg-minutes = {
  enable = true;
  logseqTokenCommand = "passage show logseq/http-api/claude-code/token";
  settings = {
    self_label = "自分";
    other_label = "相手";
    output_dir = "~/Documents/mtg-minutes";
    audio_bitrate = "96k";
  };
};
```

書ける主なキー(未指定はスクリプト DEFAULTS が適用):
`model` / `whisper_bin` / `language` / `self_label` / `other_label` /
`logseq_url` / `logseq_page_prefix` / `output_dir` / `attach_audio` /
`audio_bitrate` / `logseq_assets_dir`。

### Logseq トークン

トークン実体は config にも nix store にも焼かず、**取得コマンド**を指定する。
`logseqTokenCommand` が config.json の `logseq_token_cmd` に書かれ、`mtg-minutes` が
**実行時に評価**してトークンを得る(passage 運用にそのまま乗る)。

解決順: `logseq_token`(明示) → `logseq_token_cmd`(コマンド) → `configs.edn` 自動取得。
環境変数 `MTG_MODEL` / `MTG_LOGSEQ_TOKEN` 等でも一時上書き可。

> 既に手書きの `~/.config/mtg-minutes/config.json` があると switch が衝突する。
> nix 管理に移すときは先に削除しておく。

---

# 会議中の一括起動 (`mtg`)

**会議中はこれ一本でよい。** 録音しながら、自分と相手の発言をライブ字幕として
1つのターミナルに時系列で流す。以前は `mtg-rec` と `mtg-live` を別セッションで
並べる必要があったのを1コマンド・1プロセスにまとめたもの。

```bash
mtg                          # 録音 + 両サイド字幕、Ctrl-C で停止
mtg --minutes "1on1 田中"     # 停止後そのまま議事録生成まで実行
mtg --live other             # 相手の字幕だけ(録音はする)
mtg --no-rec                 # 録音せず字幕だけ
mtg --duration 30            # 30秒で自動停止(テスト用)
mtg --list                   # デバイス一覧(録音用 / 字幕用の両方)
```

やっていること:

- `mtg-rec` をサブプロセスとして起動し、2トラック `.mkv` を `~/Movies` に録音
- `whisper-stream` を2本(BlackHole 2ch / 16ch)このプロセス内で回してライブ字幕
- Ctrl-C で全部止め、`--minutes` があれば `mtg-minutes` に引き渡す

### 表示と保存

字幕は **文字起こしが終わった順** に表示され、**発話開始時刻順** に保存される。
whisper-stream の VAD 出力に含まれる `t0`(発話開始時刻)を拾い、
`[Start speaking]` を観測した時刻を原点に絶対時刻へ直しているので、
サイドごとにモデルや発話長が違って処理遅延がずれても時刻は揃う。

whisper-stream の出力を読むうえで実機依存の癖が3つある(`stream.cpp` 準拠、
回帰テストは `tests/test_parse.py`):

- `[Start speaking]` は `printf` なので **stdout** に出る。stderr を見ても来ない
- `no_timestamps = !use_vad` なので、`--step 0`(VAD)ではセグメントに
  `[00:00:04.000 --> 00:00:10.000]` が付く。これを外すCLIオプションは無いので、
  読む側で剥がす。チャンク先頭の `t0` に足すと発話の絶対時刻になる
- VAD経路は `audio.clear()` を呼ばず直近10秒を読み直すため、チャンク同士が
  大きく重なり同じ発言が繰り返し出る。絶対時刻で既出範囲を落とし、
  重なった区間で本文が既出と同一なら再認識とみなして落とす

> **既知の制限**: 重複除去は完全ではない。重なった音声は認識のたびに文字列も
> セグメントの切れ目も変わるため(「コードアウトアウトアウトして」と
> 「コードアウトアウンラップして」のように)、時刻でも本文一致でも捕まらない
> 取りこぼしが残る。気になるなら `--length` を短くしてチャンクの重なり自体を
> 減らすと軽減する(そのぶん文の途中で切れやすくなる)。
> 議事録は録音からのバッチ文字起こしで作られるので、この影響を受けるのは
> ライブ表示と、録音が無いときの `--transcript` 経由だけ。

保存先は `~/Documents/mtg-minutes/live/live_<日時>.txt`。到着した順にその場で
追記し(途中で落ちても記録が残るように)、終了時に発話順へ並べ替えて書き直す。

**録音が失敗していた場合は、このファイルがそのまま救済材料になる**:

```bash
mtg-minutes --transcript ~/Documents/mtg-minutes/live/live_20260731_100000.txt --title "会議名"
```

`mtg --minutes` は録音があればそちら(バッチ文字起こしなので高精度)を使い、
録音が無い/空なら自動でライブ字幕ログにフォールバックする。

### モデル

既定は **両サイドとも turbo**。

当初は自分側を small にしてメモリと GPU を節約するつもりだったが、実測すると
**2本目の turbo はメモリをほとんど食わない**:

| | 使用メモリ | 増分 |
|---|---|---|
| 0本 | 6.25 GB | — |
| turbo 1本 | 7.17 GB | +0.92 GB |
| turbo 2本 | 7.13 GB | **±0.00 GB** |

モデルファイルのページが OS 側で共有されるため、重み(1.5GB)は1度しか載らず、
プロセスごとに増えるのは計算バッファ分だけだった。`whisper-server` を1本立てて
両サイドから叩くような「1インスタンス共有」の作り替えは、メモリ目的なら意味がない。

残るコストは Metal の取り合い(発熱・バッテリー)だけ。turbo は単体で実時間の
8.5倍あるため2本でも実時間には間に合う。軽くしたいなら `--self-model small`。

### 停止まわり

`mtg-rec` は別プロセスグループで起動している。同じグループのままだと端末の
Ctrl-C が `mtg-rec` にも直接届き、`mtg` からの停止指示と二重になって、
finalize や無音チェックの最中に2発目の SIGINT が刺さるため。停止の指示元を
`mtg` に一本化し、停止時は `killpg` でグループごと送っている
(= 端末の Ctrl-C と同じ効き方を再現し、配下の ffmpeg にもちゃんと届く)。

---

# コマンド録音 (`mtg-rec`)

OBSを使わずにコマンドで会議を2トラック録音する。録音した `.mkv` はそのまま `mtg-minutes` に渡せる。

```
Track1 = 自分の声 (BlackHole 2ch ← OBS+RNNoise後のクリーン音声)
Track2 = 相手の声 (BlackHole 16ch ← Multi-Output Device経由)
```

**前提**:
- 通常の会議セットアップ(物理マイク → OBS(RNNoise) → BlackHole 2ch)が動いていること。= OBS起動中で、マイクのモニタリングがBlackHole 2chに出ている状態。自分の声はここに乗る。
  - OBSを使わず生マイクで録るなら `--self-device "UAB-80"` 等で上書き。
- Multi-Output Device(ヘッドホン + BlackHole 16ch)を作成し、通話アプリ/システムの出力先に指定しておくこと(相手の声がBlackHole 16chに乗る)。

```bash
mtg-rec                       # 録音開始 → Ctrl-C で停止
mtg-rec --minutes "1on1 田中"  # 停止後そのまま議事録生成まで一気に
mtg-rec --duration 30         # 30秒で自動停止(テスト用)
mtg-rec --list                # 録音デバイス一覧
```

- 出力: `~/Movies/mtg_<日時>.mkv`(ffmpegのログは同名の `.log` に保存)
- 各トラックは**全チャンネルを足してモノラルに集約**する。チャンネル数は
  録音開始前にデバイスを一瞬開いて数える
  - 先頭2ch決め打ちにしない理由: 複数出力装置が BlackHole 16ch の
    どのチャンネルに音声を書くかは Audio MIDI 設定次第で変わる。実機では
    **ch3** に乗っており、先頭2chには -46dB の残留しか無かった。決め打ちだと
    「録音は成功しているのに中身はノイズだけ」という気付きにくい失敗をする
    (whisper がノイズに対して「ご視聴ありがとうございました」を延々と
    出力する形で表面化した)
  - ライブ字幕が無事だったのは、whisper-stream(SDL)がモノラルを要求し
    CoreAudio が全チャンネルをダウンミックスするため。録音側だけが壊れていた
  - ffmpeg 標準のダウンミックス(`-ac 1`)でも拾えるが、レイアウト上の役割ごとに
    係数がかかって 17dB ほど痩せるため、等倍で足している
- `--minutes` を付けると録音停止後に自動で `mtg-minutes` を実行
- OBSの2トラック録音設定が不要。手軽にテスト/運用したい時はこちら
- **録音中の無音検知**: 各トラックを別プロセスでもう一系統開いてsilencedetectを
  回し、既定120秒以上無音が続いたらその場で警告(会議中に気づいて対処できる)。
  `--live-silence-sec 0` で無効化、秒数を変えるなら `--live-silence-sec N`
- 録音停止後にもファイル全体を等間隔サンプリングして無音チェックを行う
  (会議中の検知漏れ・無効化時のフォールバック)。OBSのAudio Monitoringが
  復旧しないまま録音してしまった等でどちらかのトラックが大半無音だった場合、
  警告を表示する(録音自体は破棄しない)

---

# ライブ字幕 (`mtg-live` / `mtg-self`)

会議中に発言をリアルタイム文字起こししてターミナルに表示する。
**録音しながら両サイド出したいなら `mtg` を使う**(こちらはその片側だけを単体で回すもの)。

| コマンド | 対象 | デバイス | 既定モデル |
|----------|------|----------|-----------|
| `mtg-live` | 相手の声 | BlackHole 16ch | turbo |
| `mtg-self` | 自分の声 | BlackHole 2ch | turbo |

```
通話アプリの出力 → 複数出力装置(ヘッドホン + BlackHole 16ch)
                         │(自分は普通に聞ける)
                         ▼
              BlackHole 16ch を whisper-stream が読む → ターミナルに字幕   … mtg-live

物理マイク → OBS(RNNoise) → BlackHole 2ch
                                  │
                                  ▼
              BlackHole 2ch を whisper-stream が読む → ターミナルに字幕    … mtg-self
```

`mtg-self` は `mtg-rec` の自分側と同じ経路をそのまま使う。OBS を使わず生マイクで
拾うなら `mtg-self --device "UAB-80"` のように上書きする。単体で使うなら
`--model small` にするとバッテリー消費を抑えられる。

字幕は `[時刻] ラベル: 本文` の形で表示・保存される。

## 初回セットアップ(音声経路・1回だけ)

既存のマイク経路(BlackHole 2ch)とは **別系統** が必要。相手の音声を「ヘッドホン」と
「キャプチャ用デバイス」の両方へ流すため。

### 1. BlackHole 16ch を追加(要管理者パスワード・再起動)
```bash
brew install --cask blackhole-16ch
```
※ 導入後はMacを再起動(2ch導入時と同様)。

### 2. Multi-Output Device を作成
1. **Audio MIDI設定.app** を開く
2. 左下 `+` → **「複数出力装置を作成」**
3. チェックを入れる: **使用中のヘッドホン/スピーカー** と **BlackHole 16ch**
4. (任意)名前を「会議出力」などに変更。主装置はヘッドホン側に。

### 3. 通話アプリの出力先を Multi-Output Device に
- **Zoom / Teams(ネイティブアプリ)**: アプリの音声設定 → スピーカー → 作成した複数出力装置
- **Google Meet(ブラウザ)**: システム設定 → サウンド → 出力 → 複数出力装置
  (※ ブラウザは個別指定不可なのでシステム出力を切替)

> これで「自分はヘッドホンで聞ける」かつ「whisper-stream が BlackHole 16ch から相手の声を読める」。

## 使い方

```bash
# 既定(BlackHole 16ch・turboモデル・高精度・VADモード)で開始
mtg-live

# 自分側(BlackHole 2ch)
mtg-self
mtg-self --model small    # バッテリー優先で軽くする

# デバイス一覧(番号確認用)
mtg-live --list

# 軽くしたい(バッテリー優先など)
mtg-live --model small    # 14倍速・良好
mtg-live --model base     # 22倍速・最軽量(手動DLが必要)

# 相手の発言を英語にライブ翻訳
mtg-live --translate

# 字幕ログのファイル保存をしない(既定は ~/Documents/mtg-minutes/live/ に保存される)
mtg-live --no-save

# デバイスを名前/番号で明示
mtg-live --device "BlackHole 16ch"
mtg-live --capture-id 2
```

Ctrl-C で終了。

## チューニング
- `--step 0`(既定)= VADモード。発話の区切りで確定表示(自然な文・低負荷)。
- `--step 700` 等にするとスライディング表示(より即時だが断片的・高負荷)。
- `--vad-thold`(既定0.6)= 小さいほど厳しく拾う。雑音が多ければ上げる。
- `mtg-live` の既定はturbo(M3で8.5倍速・最高精度でライブに十分間に合う)。バッテリー優先なら `--model small`。
  - 参考実測(M3・日本語30秒): base 22倍速/粗い, small 14倍速/良好, turbo 8.5倍速/最良。medium は遅い上に精度も劣るため非採用。
- `mtg` は両サイドとも turbo。2本目のモデルはページが共有されメモリをほとんど食わない
  (実測 ±0.00GB)ので、節約する意味が薄い。残るのは Metal の取り合いだけなので、
  発熱・バッテリーが気になるときだけ `mtg --self-model small` で落とす。

---

# 次フェーズ(未実装)

## 全自動化
- `~/Movies` を監視(launchd / fswatch)し、新規録音が出たら自動で `mtg-minutes` 実行
- OBS WebSocket(`localhost:4455`, 有効化が必要)で録音の開始/停止を外部制御
- `mtg-minutes --latest` で最新録音を自動選択(未実装の小改善案)

## ライブ字幕まわり
- 話者ラベルを実名にする(`mtg --other-label "田中さん"` 等)
- 会議中に印を打つ(キー入力で「あとで見る」マーカーを字幕ログに挿入)
- ライブ字幕を随時 Claude に流し、会議中に要約・論点抽出を出す
