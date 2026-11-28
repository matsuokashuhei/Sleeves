# Sleeves Website (Mac App Store)

macOS アプリ「Sleeves」の Mac App Store 申請・公開用 Web サイト（日英バイリンガル対応）です。

## ローカル起動方法（公式 Nginx Docker イメージ）

```bash
docker run -d --rm --name sleeves-website -p 8080:80 \
  -v "$PWD/Website/site:/usr/share/nginx/html:ro" \
  -v "$PWD/Website/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
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
   - **Marketing URL**: `https://<your-domain>/`
   - **Support URL**: `https://<your-domain>/support/`
   - **Privacy Policy URL**: `https://<your-domain>/privacy/`
