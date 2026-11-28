---
name: sleeves-sparkle-release
description: "SleevesのSparkle 2自動更新機構、EdDSA署名鍵管理、GitHub Releases / appcast.xml生成・リリース運用を行うときに使う。Sparkleバージョン更新、署名・notarization、appcastトラブルシューティング時に読み込む。"
---

# Sleeves Sparkle 2 更新チェック & リリース運用

## 1. 構成

- **Sparkle バージョン**: `2.10.1` (SPM、`apps/macos/project.yml` で exact pin)。
  - **バンプ時の必須作業**: `apps/macos/project.yml` と `.github/workflows/release.yml` の `SPARKLE_VERSION` を必ず同時に揃える(`generate_appcast` 出力形式互換のため)。
- **アプリ側実装**:
  - 更新 UI はすべて Sparkle 標準(`SPUStandardUpdaterController` の既定 UserDriver)。
  - `apps/macos/Sleeves/UpdateController.swift` はログ出力用 `SPUUpdaterDelegate` を差し込む薄いラッパーのみ。
  - メニュー: `Sleeves` → `Check for Updates…` (`CommandGroup(after: .appInfo)`)。
  - 自動チェック: `SUEnableAutomaticChecks = YES` + `startingUpdater: true` (アプリ側に独自スケジューラは無い)。
  - `--catalog-test` CLI 経路では `UpdateController` を生成しない(`SleevesApp.init` で optional)。
- **Info.plist**: `apps/macos/Sleeves/Info.plist` は部分 plist で、ビルド時に生成 Info.plist へマージされる(`SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` の 3 キー)。
- **ログ調査**: Sparkle 本体の詳細ログはサブシステム `org.sparkle-project.Sparkle` に出る。
  ```bash
  /usr/bin/log show --last 5m --style compact --info --predicate 'subsystem CONTAINS "sparkle"'
  ```

## 2. フィードとリリースフロー

- **`SUFeedURL`**: `https://github.com/matsuokashuhei/Sleeves/releases/latest/download/appcast.xml`
  - 各リリースに `appcast.xml` を添付する方式(`latest/download` が最新リリースのアセットへリダイレクトするため固定 URL)。
- **CI (`.github/workflows/release.yml`)**: `generate_appcast` で `appcast.xml` を生成し、`gh release upload --clobber` で添付する。

## 3. EdDSA 鍵管理(最重要)

- **公開鍵**: `apps/macos/Sleeves/Info.plist` の `SUPublicEDKey` に埋め込み済み。
- **秘密鍵の保管場所(2 箇所・どちらもリポジトリ外)**:
  1. macOS ログインキーチェーン(`Private key for signing Sparkle updates` — `sign_update` / `generate_appcast` が引数なしで自動利用)
  2. エクスポートファイル `~/.config/records/sparkle-eddsa-private-key` (mode 600、`generate_keys -x` 形式の 44 バイト)
- **絶対禁止**: 秘密鍵をコミット・ログ・PR・スクリーンショットに出さないこと。漏洩・紛失時は `generate_keys` で新ペアを生成し、新 `SUPublicEDKey` を含むリリースで鍵ローテーションを行う。
- **GitHub Secrets**: `SPARKLE_EDDSA_PRIVATE_KEY` (秘密鍵ファイルの中身そのまま)が `release.yml` で必須。登録コマンド:
  ```bash
  gh secret set SPARKLE_EDDSA_PRIVATE_KEY -R matsuokashuhei/Sleeves < ~/.config/records/sparkle-eddsa-private-key
  ```

## 4. 検証済みの落とし穴・対処法

- **`sparkle:version` は `CFBundleVersion` としか比較しない**:
  - `CFBundleShortVersionString` へのフォールバックは無い。配布済み v0.1.0 が `CFBundleVersion=1` のため、今後の `CFBundleVersion` は必ず `1` を超える単調増加整数にする必要がある(semver を入れると `0.2.0 < 1` で v0.1.0 に永遠に更新が届かない)。
  - リリースビルドは `CURRENT_PROJECT_VERSION="${{ github.run_number }}"` を採用し、人間向け表記は `MARKETING_VERSION` 側で担う。
- **更新ペイロードにも `SUPublicEDKey` が必須**:
  - 現行アプリに鍵があるのに新アプリに `SUPublicEDKey` が無いと `"key removal"` として検証失敗する。Sparkle 未搭載ビルドは更新対象にならない。
- **SPM 由来の `Sparkle.framework` は adhoc 署名**:
  - リリース署名は **inside-out** (XPC 群 → `Autoupdate` → `Updater.app` → `Sparkle.framework` → `.app`) で明示署名しないと notarization で reject される(`--deep` 一発ではネストに `--options runtime` が伝わらない)。
- **`generate_appcast` が `sparkle:edSignature` を付けない事象**:
  - まれに `edSignature` が抜けることがあるため、CI ログ(`head -30 appcast.xml`)で必ず `edSignature=` の有無を確認する。
  - 欠落していた場合は `sign_update` で手動署名し、`enclosure` 属性へ追加して `gh release upload --clobber` で差し替える。
- **手動での `appcast.xml` 後付け**:
  - Sparkle リリースの `Sparkle-<version>.tar.xz` を取得し、`generate_appcast --ed-key-file` 実行 → 必要に応じて XML の `sparkle:version` 等を手直し → `gh release upload --clobber`。
