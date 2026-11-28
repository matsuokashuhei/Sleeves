# Sleeves Website (Mac App Store)

macOS アプリ「Sleeves」の Mac App Store 申請・公開用 Web サイト（日英バイリンガル対応）です。

## ローカル起動方法（公式 Nginx Docker イメージ）

```bash
docker run -d --rm --name sleeves-website -p 8080:80 \
  -v "$PWD/apps/web/site:/usr/share/nginx/html:ro" \
  -v "$PWD/apps/web/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:alpine
```

起動後、ブラウザで以下を開いて確認できます:

- トップページ（マーケティングURL）: http://localhost:8080/
- サポート（サポートURL）: http://localhost:8080/support/
- プライバシーポリシー（プライバシーポリシーURL）: http://localhost:8080/privacy/
- 利用規約: http://localhost:8080/terms/

英語表示で直接開く場合は `?lang=en` を付けられます（例: `http://localhost:8080/?lang=en`）。

### 停止

```bash
docker stop sleeves-website
```

## App Store 申請前の差し替えチェックリスト

1. **サポートメールアドレス**: `support@example.com` を実際の連絡先メールアドレスに置換してください。
   - `site/support/index.html`
   - `site/privacy/index.html`
   - `site/terms/index.html`
2. **App Store Connect 設定**:
   - **Marketing URL**: `https://sleeves.cacheandbuffer.com/`
   - **Support URL**: `https://sleeves.cacheandbuffer.com/support/`
   - **Privacy Policy URL**: `https://sleeves.cacheandbuffer.com/privacy/`

## 本番ホスティング（Cloudflare Pages）

- **公開 URL**: https://sleeves.cacheandbuffer.com
- **インフラ管理**: Cloudflare Pages プロジェクト・カスタムドメイン・DNS（CNAME）は [infra/cloudflare/](../../infra/cloudflare/README.md) の Terraform で管理しています（Docker イメージ `hashicorp/terraform:1.17.2` 経由、State は Cloudflare R2）。
- **レスポンスヘッダ**: [site/_headers](site/_headers) でセキュリティヘッダとキャッシュ制御を定義しています。
- **デプロイ**: `.github/workflows/web-deploy.yml` により、`apps/web/site/**` の変更時に `main` ブランチは本番デプロイ、PR はプレビューデプロイが自動実行されます。
