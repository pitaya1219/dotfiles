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
| **`voice-in`** | **会議とは無関係。喋った内容をフォーカス中のアプリへその場で流し込む(音声入力)** |
| `voice-in-indicator` | voice-in の状態をメニューバーに出すだけの相棒(常駐が自分で起動する) |

普段は `mtg` ひとつでよく、`mtg-rec` / `mtg-live` / `mtg-self` は単体で使いたいとき用。
`voice-in` だけは用途が別(§ローカル音声入力)だが、収音と確定単位の切り出しを
`mtg-self` と共有しているのでこのツール群に同居している。

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
| **silero VAD** (約0.9MB) | `mtg-minutes` が発話区間の切り出しに使う(下記) |

### 録音からの文字起こしで VAD と正規化を使う理由

`whisper-cli` に「長い無音 + まばらで小さい発話」をそのまま渡すと、発話を拾えず
幻聴(「ご視聴ありがとうございました」の連発)を返す。特にマイクのモニタ経路は
録音レベルが低くなりがちで、実機では自分側が -48dB だった。

そこで `mtg-minutes` は抽出時に **loudnorm でラウドネス正規化**し、
文字起こしに **`--vad`(silero)と `-sns`** を渡す。ライブ字幕(whisper-stream)が
VADモードで安定しているのと同じ土俵に乗せる、という考え方。

実機の同一録音での比較:

| | 自分 | 相手 |
|---|---|---|
| 対処前 | 8行(全て幻聴) | 19行 |
| 対処後 | 30行(実内容) | 124行 |
| ライブ字幕(参考) | 41行 | 34行 |

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
- **デバイスごとに別の ffmpeg プロセスで録り、停止後に1本の mkv へ結合する**
  - 単一の ffmpeg で avfoundation を2つ開くと **最初の入力が壊れる**。音量は
    正常に見えるのに中身が音声にならず、whisper が延々と「ご視聴ありがとう
    ございました」を返す形で表面化した。実機での確認:
    `:0` 単独 → 正常 / `:0`を先 → `:0`が壊れる / `:3`を先 → `:0`は正常
  - 相手側が2番目の入力だったため「相手だけ録れて自分が録れない」という
    分かりにくい壊れ方をしていた(ライブ字幕は別プロセスなので無事だった)
  - 結合は `-c copy` なので再エンコードは発生しない。中間ファイル
    (`*.self.mka` / `*.other.mka`)は結合後に削除する
  - 2プロセスの開始時刻がわずかにずれるため、トラック間に最大数百msの
    ずれが出る。話者分離と文字起こしには影響しない範囲
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

# ローカル音声入力 (`voice-in`)

任意のタイミングで喋った内容を、フォーカス中のアプリへその場で流し込む。

macOS の音声入力は音声を Apple のサーバへ送り、Claude の音声入力は Anthropic へ送る。
`voice-in` はどちらも通らず、収音から文字起こしまで全てこのマシンの中で終わる。
アプリに渡るのは確定したテキストだけで、音声はディスクにも残らない。

```
物理マイク → OBS(RNNoise) → BlackHole 2ch
                                  │
                                  ▼
                 whisper-stream(VAD・ローカル) → 確定テキスト
                                  │
                                  ▼
                 CGEvent の Unicode キー入力 → フォーカス中のアプリ
```

## 常駐させると押した瞬間に始まる

一発モードは押されてから whisper-stream を起動するので、収音が始まるまで待たされる。
常駐(`--daemon`)させておくとそのコストを先に払っておけるので、押した瞬間に送出が始まる。
`--toggle` は常駐が居ればそこへ繋ぎ、居なければ一発で動くので、ホットキー側の設定は同じ。

| | 押してから収音が始まるまで(実測・M3) |
|---|---|
| 常駐あり(温まっている) | **0.06 秒** |
| 常駐あり(冷えている・`--warm-idle` 経過後の初回) | 1.20 秒 |
| 常駐なし(デバイス番号のキャッシュあり) | 1.20 秒 + プロセス起動 |
| 常駐なし(キャッシュなし) | 2.62 秒 |

内訳はデバイス列挙 1.0〜1.6 秒 + モデルロード 1.7 秒。列挙は SDL の初期化待ちで、
一度引けた番号は `~/.cache/voice-in/device.json` に覚えて次から省く。
番号は機器の抜き差しでずれる(実際に `BlackHole 2ch` が `#3` → `#2` に動いた)ので、
覚えた番号で開いたあと whisper-stream が報告するデバイス名で答え合わせし、
違っていれば列挙し直す。

温めっぱなしは「近くで喋った内容を一日中ローカルで文字起こしし続ける」ことになり
GPU と電池を食うので、使われないまま `--warm-idle`(既定 900 秒)が過ぎたら
whisper-stream を落とす。次に押されたときに読み直す。

**送出していない間の発話はアプリへ入らない。** 常駐中は disarm でも whisper-stream は
回り続けるが、VAD モードは発話検知のたびに直近 `--length`(10秒)を遡って読むため、
そのままだと「押す直前に喋っていた内容」が最初の確定に混ざる。開始時刻より前に
始まった発話は捨てている。

ログイン時から常駐させるなら:

```nix
programs.mtg-minutes.voiceIn.daemon.enable = true;   # 既定は false
```

launchd で上がる(`KeepAlive`)。ログは `~/.cache/voice-in/daemon.log`。

ただし launchd が上げた常駐は責任プロセスが自分自身になるので、ターミナルに
与えたアクセシビリティ許可は効かない(上記の表)。launchd 常駐で送出まで
動かすには、**システム設定のアクセシビリティに `+` から常駐の実体
(`/etc/profiles/per-user/<user>/bin/voice-in` の実行ファイル)を足す**必要がある。
それをやりたくなければ、常駐を端末から上げる:

```bash
voice-in --daemon        # iTerm の許可がそのまま効く
```

こちらなら追加の許可設定は要らない。ホットキーは常駐に繋ぐだけなので、
どちらで上げても押した瞬間に始まる。

## 粒度 — なぜ「発話の区切りごと」なのか

whisper-stream を VAD モード(`--step 0`)で回し、**一息ぶんが途切れた時点でその文を確定して送る**。
喋り終えて無音になってから 1 秒前後で入る(turbo。モデルロードは別途 1.7 秒)。

単語単位で流れ続ける表示にはしていない。スライディングモード(`--step > 0`)は確定行を
吐かず、同じ行を `\r` で上書きし続ける描画を出すだけなので、他アプリへ反映するには
「さっき入れた分を消してから書き直す」ことになる。途中でフォーカスが移ったり自分で
キーを打つと壊れるため、入力手段としては採らない。

確定単位の切り出しと重複除去は `mtgcommon.LiveTranscriber` をそのまま使っている
(VAD モードはバッファを消さず直近 `--length` を読み直すのでチャンクが大きく重なる。
その除去は `mtg` / `mtg-self` で実会議に揉まれた実装)。

## なぜクリップボード + Cmd+V ではないのか

音声入力は喋っている最中に何度も確定するので、Cmd+V 方式だとそのたびにクリップボードを
踏む。退避・復元を挟んでも、途中で自分がコピーした内容と競合する。
`CGEventKeyboardSetUnicodeString` はイベントに Unicode 文字列を直接載せるので
クリップボードを一切触らない。

`osascript` の `keystroke` は文字列をキーコードに落とすため、現在のレイアウトで打てない
文字(日本語)が化ける。CGEvent の Unicode 文字列はレイアウトを経由しないので日本語が通る。

## 初回セットアップ

### 1. アクセシビリティを許可する

イベント送出には TCC の「アクセシビリティ」が要る。未許可のまま起動すると
システムのダイアログが出るので、**システム設定 > プライバシーとセキュリティ >
アクセシビリティ** で許可する。

**許可は voice-in ではなく「起動元」に付く**(実機で確認)。ターミナルから叩くと
許可を求められるのは **iTerm** で、リストに載るのも iTerm。TCC は実行中の
バイナリではなく責任プロセス(responsible process)に紐づけるため。これは
nix と相性が良い —— nixpkgs の python が上がって store パスが変わっても、
起動元が同じなら許可は剥がれない。

その代わり、**起動元が変われば許可も別扱いになる**。これが常駐とホットキーの
構成を決めている:

| 起動元 | 責任プロセス | 送出できるか |
|---|---|---|
| iTerm から `voice-in` | iTerm | ○(iTerm に許可があれば) |
| Karabiner の `shell_command` | Karabiner | iTerm の許可は効かない |
| launchd エージェント | それ自身 | iTerm の許可は効かない |

**ホットキーはこの制約を踏まない。** 送出するのは常駐プロセスだけで、
ホットキーが叩く `--toggle` は unix socket に一行書くクライアントに過ぎない。
許可が要るのは常駐側だけなので、**常駐を許可のある場所から上げれば、
ホットキー自体は無権限で通る**。

常駐していないときの `--toggle` は一発モードを裏で起動するので、そちらは
Karabiner が責任プロセスになる。ホットキーで使うなら常駐させておくのが前提。

許可が無いまま常駐しても終了はせず(launchd の `KeepAlive` と噛み合って
再起動を繰り返すため)、生きたまま待つ。許可は上げ直さなくても後から下りるので、
許可した直後にホットキーを押せばそのまま動く。未許可のうちは押すと
エラー音が鳴り、`voice-in --toggle` が理由を表示する。

権限なしで動作を見たいだけなら `voice-in --no-insert`(画面に出すだけ)。

### 2. ホットキーを有効化する(Karabiner)

nix が `~/.config/karabiner/assets/complex_modifications/voice-in.json` を置く。
Karabiner-Elements の GUI で **Complex Modifications > Add predefined rule** を開くと
「voice-in (ローカル音声入力)」が一覧に出るので、そこから Enable する
(`karabiner.json` 本体は Karabiner 自身が書き換えるので symlink で宣言管理できない)。

**ルールを変えたら入れ直すこと。** Enable は asset の内容を `karabiner.json` へ
**コピー**する。asset はテンプレート置き場でしかないので、`keys` を変えて switch しても
有効化済みのコピーは古いまま動き続ける。Complex Modifications から古い行を Remove して
Add predefined rule し直す。「switch したのにキーが変わらない」はこれ。

既定は **左Control + 右Control の同時押しでトグル**。押すと始まり、もう一度押すと
止まる。片方だけなら素の Control として働くので、通常のショートカットは潰れない。

押している間だけにしたいなら:

```nix
programs.mtg-minutes.voiceIn.karabiner.mode = "hold";
```

トグルは手が空き、常駐が無くても成立する(押す → 音が鳴ってから喋る → もう一度押す)。
かわりに止め忘れると次に触ったアプリへ文字が入る(無発話 300 秒で自動停止する保険はある)。
押しっぱなしは離せば必ず止まるが、喋っているあいだキーが塞がり、**常駐が必須**になる
(常駐が無いと収音が始まる前に離されて終わる。そのときはエラー音が鳴る)。

**離した後も、押していた区間に始まった発話は入る。** VAD は発話が途切れてから確定する
ので、喋り終えて離すと最後の一息は1秒ほど遅れて届く。そこで切ると毎回最後の文が落ちる
ため、離したあと 3 秒は届くのを待つ(その間に始まった発話は入れない)。`--status` では
この待ちを `settling` と表示する。

キーを変えるなら:

```nix
programs.mtg-minutes.voiceIn.karabiner.keys = [ "left_option" "right_option" ];
```

修飾キーを2つ以上並べること。1つだけ書くとそのキーが押された時点で発火し、
修飾キーとして使えなくなる(switch 時に弾いている)。

**右Control は内蔵キーボードには無い**(Mac の内蔵キーボードの Control は左だけ)。
既定のままだと外部キーボードを繋いでいるときしか押せない。内蔵でも使いたいなら、
両方にあるキー(`left_option` + `right_option` など)に変える。

同時押しとみなす間隔は既定 250ms(`simultaneousThresholdMs`)。Karabiner の既定値
1000ms のままだと「片方で何かした直後にもう片方を使う」が誤爆するので縮めてある。
押しても反応しないなら伸ばす。

反応しない・意図しないキーが発火する場合は **Karabiner-EventViewer** で、
押したキーが期待する `key_code` として届いているかを見る(キーボードによっては
右Control が別のコードで来る)。

## 使い方

```bash
voice-in                    # 前面で起動。Ctrl-C で終了
voice-in --daemon           # 常駐(ログイン時から上げるなら daemon.enable = true)
voice-in --arm              # 開始だけ(押しっぱなしホットキーが押下時に呼ぶ)
voice-in --toggle           # 開始/停止(トグル式ホットキーが呼ぶ)
voice-in --stop             # 停止(押しっぱなしホットキーが離したときに呼ぶ)
voice-in --status           # 状態を表示(daemon armed warm など)
voice-in --quit-daemon      # 常駐を終了させる
voice-in --no-insert        # アプリへ入れず画面に出すだけ(動作確認用)
voice-in --list             # キャプチャデバイス一覧(ついでに番号をキャッシュする)
voice-in --device UAB-80    # OBS を経由せず生マイクから拾う
voice-in --language en      # 英語(発話の区切りに半角スペースが入る)
```

**収音が始まった時点で音が鳴る**(`--no-sound` で無効)ので、鳴ってから喋る。
常駐に繋がっているときは押した瞬間に鳴る。停止時にも音が鳴る。

## 今どっちなのかを見る

常駐すると**メニューバーに状態が出る**(`--no-indicator` で無効)。

| 表示 | 状態 |
|---|---|
| 🎙 | 待機。押せば始まる |
| 🔴 入力中 | 送出中。喋ったぶんがアプリへ入る |
| 🎙 … | 停止済み。最後の一息が届くのを待っている |

表示は `voice-in-indicator` という別プロセスが出す。常駐本体に持たせなかったのは、
メニューバーに出すには Cocoa の run loop をメインスレッドで回す必要があり、そうすると
`NSApp.run()` から戻るまで Python が制御を取り戻せず、Ctrl-C で常駐を止められなくなる
ため。回避するには定期タイマーで息継ぎさせることになり、見張りから消したポーリングを
別の形で戻すはめになる。表示だけ切り出せば、常駐側のスレッド構成もシグナル処理も
そのままでいい。状態が変わったときに1行書いて伝え、常駐が終われば stdin が閉じて
向こうも終わる。

音でも分かる(開始・停止・エラーで別の音が鳴る)。
うまく動かないときは `~/.cache/voice-in/session.log`(常駐は `daemon.log`)を見る。

## 気をつけること

- **入る先はフォーカス中のアプリ**。喋っている途中でウィンドウを切り替えると、
  そこへ文字が入る。
- **止め忘れ対策**に、無発話が 300 秒続くと送出を停止する(`--idle-timeout 0` で無効)。
  常駐している場合は常駐が生きたまま送出だけ止まる。
- **BlackHole 2ch は OBS が流し込んでいる**。OBS が起動していない、あるいはマイク
  再接続後にモニタリングが復帰していないと、デバイスは開けるのに中身が無音になる
  (`mtg-rec` で実際に起きた障害)。1 度も発話を検出できずに終わった場合は
  その旨を警告する。OBS を経由したくないなら `--device UAB-80`。
- **ログに本文は残さない**。裏で動かしたときのログは文字数だけを記録する。
  喋った内容が平文でディスクに溜まるのを既定にしないため。追う必要があるときだけ
  `--log-text`。
- **一息が `--length`(既定 10 秒)を超えると頭が落ちる**。VAD モードは区切りの時点から
  遡って `--length` ぶんを読むため。長く喋りたいなら伸ばす。
- **「ご視聴ありがとうございました」が入る**のは whisper の幻聴。無音や極小音量を
  渡されると学習元の YouTube 字幕由来の定型文を返す。`whisper-cli` なら `-sns` と
  silero VAD で抑えられるが、`whisper-stream` はどちらも持たず、内蔵 VAD が
  エネルギー比較だけなのでモニタ経路のような低レベル入力では無音チャンクを投げてしまう。
  読む側で落としている(`mtgcommon.HALLUCINATIONS`)。**発話まるごとが一致したときだけ**
  落とすので、「ありがとうございました」のような普通の発言は残る。別の定型文が出たら
  そのリストに足す。

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
