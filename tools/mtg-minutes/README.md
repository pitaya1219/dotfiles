# mtg-minutes

OBSの2トラック録音から **話者ラベル付き文字起こし** と **議事録** を生成し、Logseqに会議ページを自動作成するローカルツール。

```
物理マイク ─┐
            ├ OBS ─ 2トラック録音(.mkv)─ mtg-minutes ─┬ transcript.txt
相手の音声 ─┘  Track1=自分 / Track2=相手              ├ minutes.md
                                                       └ Logseq 会議ページ
```

- **音声処理は全てローカル**(ffmpeg + whisper.cpp / Apple Silicon Metal)。Claudeに渡すのは最終テキストのみ。
- 既存のノイズキャンセリング構成([[Macでノイズキャンセリング環境を構築する]])をそのまま録音機として活用。

---

## 1. 依存(インストール済み)

| ツール | 用途 | 確認 |
|--------|------|------|
| ffmpeg | 音声抽出・変換 | `which ffmpeg`（home-manager 管理） |
| whisper-cpp | 文字起こし | `which whisper-cli`（home-manager 管理） |
| claude (CLI) | 議事録生成 | `which claude`（別管理・ambient） |
| whisperモデル(turbo) | `~/.cache/whisper-cpp/models/ggml-large-v3-turbo.bin` | switch で自動取得(約1.6GB) |

### モデルについて

既定の **turbo (large-v3-turbo)** は `shared/programs/mtg-minutes.nix` が `fetchurl` で取得し、
`home-manager switch` で `~/.cache/whisper-cpp/models/` に配置される（手動DL不要）。

`mtg-live --model base` / `--model small` を使いたい場合は **手動DL** が必要:

```bash
# whisper.cpp の配布モデルを ~/.cache に置く
M=~/.cache/whisper-cpp/models
curl -L -o "$M/ggml-base.bin"  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
curl -L -o "$M/ggml-small.bin" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

> 既に turbo を手動DL済みなら、symlink 衝突を避けるため switch 前に
> `rm ~/.cache/whisper-cpp/models/ggml-large-v3-turbo.bin` しておく。

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
r-shibuya プロファイルの imports に組み込み済みなので、switch すれば `mtg-rec` / `mtg-live` / `mtg-minutes` が PATH に入る。

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
- 相手トラックはBlackHole 16chの先頭2chをモノラルに集約(残り14chは無音)
- `--minutes` を付けると録音停止後に自動で `mtg-minutes` を実行
- OBSの2トラック録音設定が不要。手軽にテスト/運用したい時はこちら
- 録音停止後、両トラックを等間隔サンプリングして無音チェックを行う。OBSのAudio
  Monitoringが復旧しないまま録音してしまった等でどちらかのトラックが大半無音
  だった場合、警告を表示する(録音自体は破棄しない)

---

# ライブ字幕 (`mtg-live`)

会議中に **相手の声** をリアルタイム文字起こししてターミナルに表示する。
1on1などで「相手が今言ったこと」をさっと見返す補助用。録音・議事録系とは独立。

```
通話アプリの出力 → Multi-Output Device(ヘッドホン + BlackHole 16ch)
                         │(自分は普通に聞ける)
                         ▼
              BlackHole 16ch を whisper-stream が読む → ターミナルに字幕
```

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

# デバイス一覧(番号確認用)
mtg-live --list

# 軽くしたい(バッテリー優先など)
mtg-live --model small    # 14倍速・良好
mtg-live --model base     # 22倍速・最軽量

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
- 既定はturbo(M3で8.5倍速・最高精度でライブに十分間に合う)。バッテリー優先なら `--model small`。
  - 参考実測(M3・日本語30秒): base 22倍速/粗い, small 14倍速/良好, turbo 8.5倍速/最良。medium は遅い上に精度も劣るため非採用。

---

# 次フェーズ(未実装)

## 全自動化
- `~/Movies` を監視(launchd / fswatch)し、新規録音が出たら自動で `mtg-minutes` 実行
- OBS WebSocket(`localhost:4455`, 有効化が必要)で録音の開始/停止を外部制御
- `mtg-minutes --latest` で最新録音を自動選択(未実装の小改善案)
