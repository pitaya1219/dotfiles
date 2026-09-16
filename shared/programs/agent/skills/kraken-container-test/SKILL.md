---
name: kraken-container-test
description: Build and run local container tests for kraken-transfer-for-other-systems
user-invocable: true
version: 1.1.0
---

# Kraken Container Test Skill

## What This Skill Does

`kraken-transfer-for-other-systems` のローカルコンテナテスト環境を構築し、ユニットテスト・e2e テストを実行する。

## Usage

```
/kraken-container-test              # フルセット: 環境構築 → ユニットテスト → e2e テスト
/kraken-container-test --unit-only  # Docker 不要なユニットテストのみ実行
/kraken-container-test --e2e-only   # e2e テストのみ実行 (コンテナは起動する)
/kraken-container-test --keep       # テスト後もコンテナを起動したままにする
/kraken-container-test --teardown   # コンテナを停止・削除するだけ
```

---

## Phase 0: プロジェクトディレクトリの特定

以下の優先順位でプロジェクトルートを特定する。

1. カレントディレクトリに `docker-compose.yml` と `pyproject.toml` が存在し、`pyproject.toml` に `kraken-transfer-for-other-systems` が含まれていれば、そこをプロジェクトルートとする。
2. カレントディレクトリ直下に `kraken-transfer-for-other-systems/` ディレクトリがあればそこを使う。
3. どちらも見つからない場合はエラーメッセージを出して停止する。

```bash
# 例: セッションディレクトリから実行している場合
PROJECT_DIR="$(pwd)/kraken-transfer-for-other-systems"
# 例: プロジェクトルートから実行している場合
PROJECT_DIR="$(pwd)"
```

以降の全操作は `cd "$PROJECT_DIR"` した状態で行う。

---

## Phase 1: 環境セットアップ

### 1-1. `.env` ファイルの準備

```bash
cd "$PROJECT_DIR"
if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    echo "✅ .env を .env.example からコピーしました"
  else
    echo "❌ .env.example が見つかりません。手動で .env を作成してください"
    exit 1
  fi
else
  echo "✅ .env が既に存在します"
fi
```

### 1-2. Docker の起動確認

```bash
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker が起動していません。Docker (Rancher Desktop など) を起動してください"
  exit 1
fi
echo "✅ Docker が起動しています"
```

### 1-3. bind mount 先ディレクトリの作成

`docker/local-s3/data` と `output` は gitignore されているため、クローン直後には存在しない。
Docker が作ろうとして `chown: permission denied` で起動に失敗するので、先に作っておく。

```bash
cd "$PROJECT_DIR"
mkdir -p docker/local-s3/data output
```

---

## Phase 2: Docker イメージのビルドとサービス起動

`--unit-only` が指定された場合はこの Phase をスキップする。

### 2-1. Docker イメージのビルド

```bash
cd "$PROJECT_DIR"
echo "🔨 Docker イメージをビルド中..."
docker compose build
echo "✅ ビルド完了"
```

### 2-2. DB・依存サービスの起動

`minio` サービスが起動するイメージは Silo (`pgsty/silo`)。MinIO の community イメージが
凍結されたための drop-in 置換で、サービス名とエンドポイント (`http://minio:9000`) は据え置き。
バケット作成ジョブの名前だけが `minio-mc` から `local-s3-init` に変わっている。

```bash
echo "🚀 サービスを起動中 (db, fake-api, minio, local-s3-init)..."
docker compose up -d db fake-api minio local-s3-init
```

### 2-3. DB の起動待ち

DB が完全に起動するまで待つ。最大 60 秒待機。

```bash
echo "⏳ DB の起動を待機中..."
ATTEMPTS=0
MAX_ATTEMPTS=30
until docker compose exec -T db mysqladmin ping -h localhost --silent 2>/dev/null; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    echo "❌ DB の起動タイムアウト (${MAX_ATTEMPTS}秒)"
    docker compose logs db | tail -30
    exit 1
  fi
  echo "  waiting... (${ATTEMPTS}/${MAX_ATTEMPTS})"
  sleep 2
done
echo "✅ DB が起動しました"
```

### 2-4. local-s3-init (バケット作成) の完了待ち

```bash
echo "⏳ バケット設定の完了を待機中..."
docker compose wait local-s3-init 2>/dev/null || true
echo "✅ ローカル S3 セットアップ完了"
```

2 回目以降は「バケットが既に存在する」「アクセスキーが既に使われている」という
`mc: <ERROR>` が出るが、`setup.sh` が `|| true` で流しているので無視してよい。

---

## Phase 3: ユニットテストの実行

`--e2e-only` が指定された場合はこの Phase をスキップする。

```bash
cd "$PROJECT_DIR"
echo ""
echo "========================================="
echo "  ユニットテスト実行 (e2e 除外)"
echo "========================================="
poetry run pytest -m "not e2e" -v
UNIT_EXIT=$?
if [ $UNIT_EXIT -eq 0 ]; then
  echo "✅ ユニットテスト: PASSED"
else
  echo "❌ ユニットテスト: FAILED (exit=$UNIT_EXIT)"
fi
```

---

## Phase 4: e2e テストの実行

`--unit-only` が指定された場合はこの Phase をスキップする。

e2e テストはホストマシンから直接 `poetry run pytest -m e2e` で実行する。  
DB は Docker コンテナとして `localhost:3306` に公開されているため、pytest は `PYTEST_DB_HOST=localhost` でアクセスする。

`.env` の `DB_HOST=db` はアプリコンテナ向けの設定なので、pytest 実行時は環境変数で上書きする。

```bash
cd "$PROJECT_DIR"
echo ""
echo "========================================="
echo "  e2e テスト実行"
echo "========================================="
PYTEST_DB_HOST=localhost \
PYTEST_DB_USER=root \
PYTEST_DB_PASSWORD=root \
PYTEST_DB_NAME=test_kraken_migration \
PYTEST_DB_PORT=3306 \
poetry run pytest -m "e2e" -v
E2E_EXIT=$?
if [ $E2E_EXIT -eq 0 ]; then
  echo "✅ e2e テスト: PASSED"
else
  echo "❌ e2e テスト: FAILED (exit=$E2E_EXIT)"
fi
```

---

## Phase 5: 後処理

### 5-1. コンテナの停止

`--keep` または `--teardown` でない限り、テスト後にコンテナを停止する。  
`--teardown` が指定された場合は単独でこの処理を実行する。

```bash
cd "$PROJECT_DIR"
echo ""
echo "🧹 コンテナを停止中..."
docker compose down
echo "✅ コンテナ停止完了"
```

---

## Phase 6: 結果サマリー

実行したテストの pass/fail をまとめて出力する。

```
========================================
テスト結果サマリー
========================================
ユニットテスト : PASSED  (or FAILED / SKIPPED)
e2e テスト     : PASSED  (or FAILED / SKIPPED)
========================================
```

どちらかが FAILED の場合は全体として失敗とみなし、ユーザーにログの確認方法を案内する。

```bash
# ログ確認コマンド案内例
docker compose logs db | tail -50
docker compose logs fake-api | tail -50
```

---

## 注意事項

- `nscacert.pem` / `nscacert_combined.pem` が存在しない環境ではビルドが失敗する可能性がある。Zero Trust 配下では `bash ~/.config/agent-overlays/kraken-transfer-for-other-systems/setup.sh "$PROJECT_DIR"` がこれらの配置と Dockerfile へのパッチを行う。
- DB ポート `3306` がホスト側で既に使用中の場合はコンテナ起動が失敗する。`lsof -i :3306` で確認するようユーザーに案内する。
- ローカル S3 のデータは `docker/local-s3/data/` に bind mount で永続化される。named volume ではないので `docker compose down -v` では消えない。クリーンな状態にするには `docker compose down` 後に `rm -rf docker/local-s3/data/*` するよう案内する。
