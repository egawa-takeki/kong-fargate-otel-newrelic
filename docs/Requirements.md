# Kong Gateway + New Relic 分散トレーシング実装要件書

## 1. 概要

### 1.1 目的

Kong Konnect（SaaS）とNew Relicを組み合わせた分散トレーシング環境を構築し、API Gateway経由のリクエストをエンドツーエンドで可視化する。

### 1.2 対象読者

- Kong Gatewayを利用中または検討中のエンジニア
- AWSでAPI基盤の可観測性を向上させたいエンジニア

### 1.3 成果物

- 技術ブログ記事（DevelopersIO）
- Terraformコード一式
- サンプルアプリケーションコード

---

## 2. システム構成

### 2.1 アーキテクチャ図

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

### 2.2 コンポーネント一覧

| コンポーネント | 種別 | 説明 |
|--------------|------|------|
| Kong Konnect | SaaS | Control Plane。プラグイン設定・ルーティング管理 |
| Kong Gateway DP | ECS Fargate | Data Plane。トラフィック処理・トレース生成 |
| Dummy API | ECS Fargate | フロントエンドAPI。Node.js + Express |
| Downstream API | ECS Fargate | バックエンドAPI。Node.js + Express |
| OTEL Collector | Sidecar | New Relicへのトレース転送 |
| ALB | AWS | ロードバランサー |
| New Relic | SaaS | 分散トレーシングバックエンド |

---

## 3. 技術要件

### 3.1 Kong Konnect

| 項目 | 要件 |
|-----|------|
| プラン | Plus以上（OpenTelemetryプラグイン利用のため） |
| リージョン | 任意（AP推奨） |
| Runtime Group | 1つ作成 |

### 3.2 Kong OpenTelemetry プラグイン設定

| パラメータ | 設定値 | 備考 |
|-----------|-------|------|
| Protocols | http, https | gRPCは今回対象外 |
| Propagation.Default Format | w3c | W3C Trace Context形式 |
| Sampling Strategy | parent_drop_probability_fallback | デフォルト |
| Traces Endpoint | `http://localhost:4318/v1/traces` | Sidecar Collector |

### 3.3 OTEL Collector

| 項目 | 要件 |
|-----|------|
| イメージ | otel/opentelemetry-collector-contrib:0.114.0 以上 |
| Receiver | OTLP (HTTP: 4318) |
| Exporter | otlphttp（New Relic OTLPエンドポイント） |

#### Collector設定ファイル（参考）

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 50

exporters:
  otlphttp:
    endpoint: https://otlp.nr-data.net
    headers:
      api-key: ${NEW_RELIC_LICENSE_KEY}

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp]
```

### 3.4 Dummy API / Downstream API（Node.js）

| 項目 | 要件 |
|-----|------|
| ランタイム | Node.js 24.x 以上 |
| フレームワーク | Express |
| OpenTelemetry SDK | @opentelemetry/sdk-node |
| Instrumentation | @opentelemetry/instrumentation-http, @opentelemetry/instrumentation-express |
| Exporter | @opentelemetry/exporter-trace-otlp-http |
| Trace Propagation | W3C Trace Context（traceparentヘッダー） |

#### 必要なnpmパッケージ

```json
{
  "dependencies": {
    "express": "^4.18.0",
    "@opentelemetry/sdk-node": "^0.55.0",
    "@opentelemetry/exporter-trace-otlp-http": "^0.55.0",
    "@opentelemetry/instrumentation-http": "^0.55.0",
    "@opentelemetry/instrumentation-express": "^0.44.0",
    "@opentelemetry/resources": "^1.28.0",
    "@opentelemetry/semantic-conventions": "^1.28.0"
  }
}
```

### 3.5 AWS インフラ

| リソース | 要件 |
|---------|------|
| リージョン | ap-northeast-1（東京） |
| VPC | 新規作成（パブリック/プライベートサブネット） |
| ECS Cluster | Fargate |
| ALB | インターネット向け |
| ECR | Kong DP用、Dummy API用、Downstream API用、OTEL Collector用 |
| IAM Role | ECSタスク用 |
| Security Group | ALB→Kong DP→Dummy API→Downstream API の通信許可 |
| CloudWatch Logs | 各コンテナのログ出力先 |

### 3.6 New Relic 設定

| 項目 | 要件 |
|-----|------|
| アカウント | New Relic アカウント |
| License Key | OTLP認証用のIngest License Key |

---

## 4. IAM 要件

### 4.1 ECSタスクロール

CloudWatch Logsへのログ出力に必要な権限：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 5. ネットワーク要件

### 5.1 Security Group ルール

| 名前 | インバウンド | アウトバウンド |
|-----|------------|--------------|
| ALB SG | 0.0.0.0/0:80 | Kong DP SG:8000 |
| Kong DP SG | ALB SG:8000 | Dummy API SG:3000, 0.0.0.0/0:443 |
| Dummy API SG | Kong DP SG:3000 | Downstream API SG:3001, 0.0.0.0/0:443 |
| Downstream API SG | Dummy API SG:3001 | 0.0.0.0/0:443 |

### 5.2 必要なアウトバウンド通信

| 送信元 | 宛先 | 用途 |
|-------|-----|------|
| Kong DP | Kong Konnect | CP接続 |
| Kong DP | localhost:4318 | OTEL Collector (Sidecar) |
| Dummy API | localhost:4318 | OTEL Collector (Sidecar) |
| Downstream API | localhost:4318 | OTEL Collector (Sidecar) |
| OTEL Collector | otlp.nr-data.net:443 | New Relic OTLPエンドポイント |

---

## 6. Terraform 構成

### 6.1 ディレクトリ構造

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── vpc.tf
├── alb.tf
├── ecs.tf
├── iam.tf
├── security_groups.tf
└── ecr.tf
```

### 6.2 モジュール/リソース一覧

| ファイル | 主なリソース |
|---------|------------|
| vpc.tf | VPC, Subnet, IGW, NAT Gateway, Route Table |
| alb.tf | ALB, Target Group, Listener |
| ecs.tf | ECS Cluster, Task Definition, Service |
| iam.tf | IAM Role, Policy |
| security_groups.tf | Security Group |
| ecr.tf | ECR Repository |

---

## 7. アプリケーション構成

### 7.1 Dummy API エンドポイント

| メソッド | パス | 説明 |
|---------|-----|------|
| GET | /health | ヘルスチェック |
| GET | /api/users | ユーザー一覧（ダミーデータ） |
| GET | /api/users/:id | ユーザー詳細（ダミーデータ） |
| POST | /api/users | ユーザー作成（ダミー） |
| GET | /api/chain | downstream-apiを呼び出し（分散トレーシング確認用） |
| GET | /api/chain/:id | 特定IDでdownstream-apiを呼び出し |

### 7.2 Downstream API エンドポイント

| メソッド | パス | 説明 |
|---------|-----|------|
| GET | /health | ヘルスチェック |
| GET | /api/data | データ取得 |
| GET | /api/data/:id | 特定IDのデータ取得 |
| POST | /api/data | データ処理 |

### 7.3 Kong Gateway ルーティング

| Route | Service | Upstream |
|-------|---------|----------|
| /api/* | dummy-api-service | http://dummy-api.kong-otel-dev.local:3000 |

---

## 8. 動作確認項目

### 8.1 機能確認

| # | 確認項目 | 期待結果 |
|---|---------|---------|
| 1 | ALB経由でAPIアクセス | 200 OK |
| 2 | New Relicでトレース表示 | Kong DP → Dummy API → Downstream API のSpanが表示 |
| 3 | Trace ID伝播 | Kong/Dummy API/Downstream APIで同一Trace ID |
| 4 | Service Map | Kong DP → Dummy API → Downstream API の依存関係が可視化 |

### 8.2 確認コマンド例

```bash
# APIアクセス
curl -i http://<ALB_DNS>/api/users

# チェーンリクエスト（分散トレーシング確認）
curl http://<ALB_DNS>/api/chain

# レスポンスヘッダーでTrace ID確認
curl -v http://<ALB_DNS>/api/users 2>&1 | grep -i traceparent
```

---

## 9. 前提条件・制約

### 9.1 前提条件

- Kong Konnect アカウント（Plus以上）
- New Relic アカウント（License Key が必要）
- AWSアカウント（適切な権限）
- Terraform 1.5 以上
- Docker（ローカルビルド用）
- AWS CLI 設定済み

### 9.2 制約・注意事項

| 項目 | 内容 |
|-----|------|
| New Relic License Key | 環境変数 `NEW_RELIC_LICENSE_KEY` として設定が必要 |
| Kong OpenTelemetryプラグイン | Collector経由でのトレース送信が必要 |
| コスト | NAT Gateway等の課金に注意 |

---

## 10. 参考資料

- [Kong OpenTelemetry Plugin](https://docs.konghq.com/hub/kong-inc/opentelemetry/)
- [New Relic OTLP Endpoint](https://docs.newrelic.com/docs/more-integrations/open-source-telemetry-integrations/opentelemetry/opentelemetry-setup/)
- [OpenTelemetry Collector Contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)

---

## 11. 改訂履歴

| バージョン | 日付 | 内容 |
|-----------|-----|------|
| 1.0 | 2025-12-15 | 初版作成（X-Ray版） |
| 2.0 | 2025-12-16 | New Relic版に移行 |
