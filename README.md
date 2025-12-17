# Kong Gateway + New Relic 分散トレーシング

Kong Konnect（SaaS）とNew Relicを組み合わせた分散トレーシング環境のデモプロジェクトです。

## アーキテクチャ

```
                                    ┌─────────────────────────────────────────┐
                                    │            Kong Konnect (SaaS)          │
                                    │         Control Plane (CP)              │
                                    └──────────────────┬──────────────────────┘
                                                       │ 設定同期
                                                       ▼
┌──────────┐      ┌──────────┐      ┌─────────────────────────────────────────┐
│  Client  │─────▶│   ALB    │─────▶│         ECS Fargate Task                │
└──────────┘      └──────────┘      │  ┌─────────────┐  ┌──────────────────┐  │
                                    │  │   Kong DP   │  │  OTEL Collector  │  │
                                    │  │  Container  │─▶│    (Sidecar)     │  │
                                    │  └─────────────┘  └────────┬─────────┘  │
                                    └────────┬───────────────────┼────────────┘
                                             │                   │
                                             ▼                   │
                                    ┌─────────────────────────────────────────┐
                                    │         ECS Fargate Task                │
                                    │  ┌─────────────┐  ┌──────────────────┐  │
                                    │  │  Dummy API  │  │  OTEL Collector  │  │
                                    │  │  (Node.js)  │─▶│    (Sidecar)     │  │
                                    │  └──────┬──────┘  └────────┬─────────┘  │
                                    └─────────┼──────────────────┼────────────┘
                                              │                  │
                                              ▼                  │
                                    ┌─────────────────────────────────────────┐
                                    │         ECS Fargate Task                │
                                    │  ┌─────────────┐  ┌──────────────────┐  │
                                    │  │ Downstream  │  │  OTEL Collector  │  │
                                    │  │    API      │─▶│    (Sidecar)     │  │
                                    │  └─────────────┘  └────────┬─────────┘  │
                                    └────────────────────────────┼────────────┘
                                                                 │
                                                                 ▼
                                    ┌─────────────────────────────────────────┐
                                    │      New Relic OTLP Endpoint            │
                                    │      https://otlp.nr-data.net           │
                                    └──────────────────┬──────────────────────┘
                                                       │
                                                       ▼
                                    ┌─────────────────────────────────────────┐
                                    │         New Relic One Dashboard         │
                                    └─────────────────────────────────────────┘
```

### 分散トレーシングの流れ

```
Kong DP (span)
  └─> dummy-api (span)
        └─> downstream-api (span)
```

## 前提条件

- Kong Konnect アカウント
- New Relic アカウント
- AWSアカウント（適切な権限）
- Terraform 1.5 以上
- Docker
- AWS CLI 設定済み

## ディレクトリ構成

```
kong-otel/
├── terraform/           # インフラ構成
├── app/
│   ├── dummy-api/       # フロントエンドAPI（Kong経由でアクセス）
│   └── downstream-api/  # バックエンドAPI（dummy-apiから呼び出し）
├── otel-collector/      # OTEL Collector設定
└── docs/                # ドキュメント
```

## セットアップ手順

### 1. Kong Konnect の準備

1. [Kong Konnect](https://cloud.konghq.com/) にログイン
2. API Gateway で新しい Gateway を作成
3. 証明書とキーをダウンロード
4. クラスターエンドポイントをメモ

### 2. New Relic の準備

1. [New Relic](https://one.newrelic.com/) にログイン
2. API Keys で License Key を取得
3. License Key を環境変数 `NEW_RELIC_LICENSE_KEY` として設定

### 3. Terraform 変数の設定

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して Kong 認証情報を設定
```

### 4. Docker イメージのビルドとプッシュ

```bash
# AWS にログイン
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-northeast-1.amazonaws.com

# Terraform で ECR リポジトリを先に作成
cd terraform
terraform init
terraform apply -target=aws_ecr_repository.dummy_api -target=aws_ecr_repository.downstream_api -target=aws_ecr_repository.otel_collector

# ECR URL を取得
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-1

# Dummy API イメージをビルド・プッシュ
cd ../app/dummy-api
docker build -t ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kong-otel-dev-dummy-api:latest .
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kong-otel-dev-dummy-api:latest

# Downstream API イメージをビルド・プッシュ
cd ../downstream-api
docker build -t ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kong-otel-dev-downstream-api:latest .
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kong-otel-dev-downstream-api:latest

# OTEL Collector イメージをビルド・プッシュ
cd ../../otel-collector
docker build -t ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kong-otel-dev-otel-collector:latest .
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kong-otel-dev-otel-collector:latest
```

### 5. インフラのデプロイ

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 6. Kong Konnect でルーティング設定

Kong Konnect で以下を設定

1. **Service** を作成
   - Name: `dummy-api-service`
   - Host: `dummy-api.kong-otel-dev.local`
   - Port: `3000`

2. **Route** を作成
   - Paths: `/api`

3. **OpenTelemetry プラグイン** を有効化
   - Traces Endpoint: `http://localhost:4318/v1/traces`
   - Propagation Default Format: `w3c`

## 動作確認

```bash
# ALB DNS名を取得
ALB_DNS=$(terraform output -raw alb_dns_name)

# APIにアクセス
curl -i http://${ALB_DNS}/api/users

# ユーザー詳細
curl http://${ALB_DNS}/api/users/1

# ユーザー作成
curl -X POST http://${ALB_DNS}/api/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Test User", "email": "test@example.com"}'

# 分散トレーシング確認（downstream-apiを呼び出し）
curl http://${ALB_DNS}/api/chain

# 特定IDでの分散トレーシング確認
curl http://${ALB_DNS}/api/chain/123
```

## トレースの確認

1. New Relic One → APM & Services → Distributed Tracing
2. Service Map でサービス間の依存関係を確認
   - `kong-gateway` → `dummy-api` → `downstream-api` の連鎖が可視化される
3. 個別トレースをクリックして詳細を確認
   - 各サービスでのSpanとその所要時間が確認できる

## API エンドポイント

### dummy-api (Port: 3000)

| メソッド | パス | 説明 |
|---------|------|------|
| GET | /health | ヘルスチェック |
| GET | /api/users | ユーザー一覧 |
| GET | /api/users/:id | ユーザー詳細 |
| POST | /api/users | ユーザー作成 |
| GET | /api/chain | downstream-apiを呼び出し（分散トレーシング確認用） |
| GET | /api/chain/:id | 特定IDでdownstream-apiを呼び出し |

### downstream-api (Port: 3001)

| メソッド | パス | 説明 |
|---------|------|------|
| GET | /health | ヘルスチェック |
| GET | /api/data | データ取得 |
| GET | /api/data/:id | 特定IDのデータ取得 |
| POST | /api/data | データ処理 |

## クリーンアップ

```bash
cd terraform
terraform destroy
```
