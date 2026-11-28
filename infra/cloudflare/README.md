# Sleeves Cloudflare Infrastructure (Terraform)

`https://sleeves.cacheandbuffer.com` をホストする Cloudflare Pages・カスタムドメイン・DNS レコードを管理します。

## 前提

- Docker がローカルで動作すること（Terraform は `hashicorp/terraform:1.17.2` コンテナ経由で実行します）
- `cacheandbuffer.com` が Cloudflare DNS に登録済みであること

## 初回セットアップ（1回のみ）

### 1. State 保存用 R2 バケットの作成（`infra/cloudflare/terraform/`）

R2 バックエンド用のバケット自体は、独立したブートストラップ用ディレクトリ `infra/cloudflare/terraform/` で作成します。

```bash
export CLOUDFLARE_API_TOKEN="..."
make tf-state-init
make tf-state-plan
make tf-state-apply
```

出力される `r2_s3_endpoint` と `state_bucket_name` を次の `backend.hcl` に使用します。

### 2. API トークンの準備

1. **Cloudflare API Token**（`CLOUDFLARE_API_TOKEN`）
   - `Account` / `Workers R2 Storage` / `Edit`（`cloudflare_r2_bucket` 用）
   - `Account` / `Cloudflare Pages` / `Edit`
   - `Zone` / `DNS` / `Edit`
   - `Zone` / `Zone` / `Read`
2. **R2 API Token**（`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`）
   - `Object Read & Write`（対象バケット: `sleeves-terraform-state`）

### 3. ローカル設定ファイルの作成（Git 管理外）

```bash
cp infra/cloudflare/backend.hcl.example infra/cloudflare/backend.hcl
cp infra/cloudflare/terraform.tfvars.example infra/cloudflare/terraform.tfvars
```

`backend.hcl` の `<CLOUDFLARE_ACCOUNT_ID>` と `terraform.tfvars` の `<CLOUDFLARE_ZONE_ID>` を実際の値に置換します。

## 実行手順（リポジトリルートから）

```bash
export CLOUDFLARE_API_TOKEN="..."
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

make tf-init
make tf-fmt
make tf-validate
make tf-plan
make tf-apply
```

## GitHub Actions 用 Secrets

リポジトリの Settings > Secrets and variables > Actions に以下を登録します。

- `CLOUDFLARE_API_TOKEN` — Cloudflare API Token
- `CLOUDFLARE_ACCOUNT_ID` — Cloudflare Account ID
- `CLOUDFLARE_ZONE_ID` — Cloudflare DNS Zone ID（`cacheandbuffer.com`）
- `R2_ACCESS_KEY_ID` — R2 API Token (Access Key ID)
- `R2_SECRET_ACCESS_KEY` — R2 API Token (Secret Access Key)
- `R2_STATE_BUCKET` — State 保存用 R2 バケット名（例: `sleeves-terraform-state`）
