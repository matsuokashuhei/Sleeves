# AGENTS.md — Sleeves(レコードシェルフ)開発ガイド

## このプロジェクト

macOS アプリおよびランディングページを管理するモノレポ。Apple Music / Spotify のアルバム・プレイリストを壁のレコードシェルフ風に自由配置（スパース・可変グリッド・複数シェルフ対応）し、クリックで再生する。

## 鉄則（必ず守る）

### 1. ロギングは必須

エージェントは UI をリアルタイムに操作・目視できないため、動作判断の第一情報源はログとする（見た目確認が必要な場合は `sleeves-local-verification` スキルの `screencapture` / CLI プレビューを使う）。

- すべての UI アクション（ボタンクリック、追加フロー、クリップボード操作等）に `os.Logger` を仕込む（subsystem: `com.cacheandbuffer.Sleeves`）
- 非同期処理・外部プロセス実行・エラー経路には必ず開始／成功／失敗のログを出す
- 新規ファイル・新機能は実装時からログを入れる
- 例: `Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")`
- 文字列補間は `\(value, privacy: .public)` を指定し、`log show` で読めるようにする

### 2. ユーザーに操作を依頼したら、ログは自分で監視・分析する

- ユーザーへ操作を依頼したら、`log show` / `log stream` で結果を**自分で取得して判断する**（エラーメッセージの転記をユーザーに頼まない）
- 操作依頼 → ログ監視 → 原因判断 → 次のアクション、のサイクルを回す

### 3. ファイルを追加・削除したら xcodegen を再実行

新しい Swift ファイルの追加・削除・リネーム後は必ず `make gen`（`apps/macos` で `xcodegen generate`）を実行する（`project.pbxproj` の直編集は禁止）。

### 4. スキルは `.agents/skills/` に作成する

新しいスキル（`SKILL.md`）は `.agents/skills/<name>/SKILL.md` に置く。`.devin/skills/` には置かない。

### 5. コード実装したら必ず `builder-reviewer-loop` を回す

コード実装（自分で書いた場合も含む）の完了前に、必ず `.agents/skills/builder-reviewer-loop` のレビューゲートを通す（ユーザー指示）。読み取り専用レビュアーによる要件・ルール照合と実機検証の手順は省略しない。

### 6. 作業が完了したら必ずアプリを起動する

コード変更を伴うタスクの完了時は毎回、新ビルドのアプリを起動しておく（`make run`、または必ず `pkill` してから `open`）。

## ビルド・起動・基本コマンド

ルートの `Makefile` から実行できる:

```bash
make gen     # Xcodeプロジェクト生成 (cd apps/macos && DEVELOPER_DIR=... xcodegen generate)
make build   # Debug ビルド (-project apps/macos/Sleeves.xcodeproj -derivedDataPath .build)
make test    # 単体テスト実行 (SleevesTests)
make run     # 起動 (pkill -x Sleeves してから open .build/Build/Products/Debug/Sleeves.app)
make logs    # 直近5分のログ取得 (subsystem == "com.cacheandbuffer.Sleeves")

# 初回 / clone 後のエージェントプラグイン導入（cursor-team-kit / pstack）
bash .agents/plugins/install-cursor-plugins.sh
```

- `/Applications` にはインストールしない（ユーザー指示）
- `xcode-select` は CLT 向きのため、`xcodebuild` / `xcodegen` を直接叩くときは必ず `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を付ける
- テストで音を出すときは事前にシステム音量を 0 にし、終了後に戻す
- JSON 解析には python ではなく `jq` を使う（ユーザー指示）
- アプリの場所を移すと Launch Services 登録が壊れることがある → `lsregister -f <app>` で復旧

## 絶対に踏んではいけない地雷（要点）

- **MusicKit entitlement 禁止**: `com.apple.developer.musickit` は存在しない。entitlements に書くとプロビジョニングエラーになる（App ID の App Services で有効化）。
- **ドラッグ中の `@State` 高頻度更新禁止**: 走行中セッション配下のクロージャが破棄され `EXC_BAD_ACCESS` でクラッシュする。ゴースト追従は 60fps タイマーで命令的に動かす。
- **座標・余白・間隔の不変条件**: 余白は `ShelfPluginRegistry.effectivePadding`、ピッチは `effectiveSpacing`、ヒット判定・ドロップ・ゴースト着地は `ShelfView.slotVisualRect` を使う（生の設定値やピッチ位置を読むとプラグイン部材とずれる）。
- **ジャケット面変形フック**: 3D 回転等の幾何変形は `transformJacket` ではなく `transformJacketSurface` に実装する。
- **EdDSA 秘密鍵の厳重管理**: Sparkle 更新用秘密鍵をコミット・ログ・PR・スクリーンショットに絶対に出さない。

## リポジトリ構成

- `apps/macos/` — macOS アプリ（Xcode プロジェクト一式）
  - `project.yml` — xcodegen 定義（ターゲット変更はここを編集）
  - `Sleeves/` — アプリ本体（`SleevesApp.swift`, `ShelfView.swift`, `SettingsView.swift`, `ShelfShareView.swift`, `WindowGlass.swift`, `DeleteConfirmationDialog.swift`, `PlaybackMonitor.swift`, `UpdateController.swift`, `AppIconManager.swift`, `Plugins/`, `Localizable.xcstrings`, `InfoPlist.xcstrings`, `Info.plist`）
  - `Shared/` — アプリとテストにリンクされる共有層（`MediaEntry.swift`, `MediaCatalogClient.swift`, `SpotifyCatalogClient.swift`, `PlaybackEngine.swift`, `PlaylistPlayer.swift`, `ShortcutInstaller.swift`, `ShelfManager.swift`, `ShelfStore.swift`, `ShelfSettings.swift`, `ShelfPluginModel.swift`, `AppIconImageProcessor.swift`, `ShowcaseCatalog.swift`, `ShowcaseMode.swift`）
  - `SleevesTests/` — 単体テスト
- `apps/web/` — Mac App Store 向けランディングページ（`site/`, `nginx.conf`, `README.md`）
- `docs/` — ドキュメント（`architecture/` 設計メモ、`legal/` 法務文書）
- `assets/` — 画像・デザイン素材（`design/`, `icons/`, `showcase/`, `screenshots/`）
- `scripts/` — 生成・運用スクリプト（`generate-paper-textures.py`）
- `Makefile` — ルートから macOS アプリの生成・ビルド・テスト・起動・ログ取得を行うラッパー

## 詳細ドキュメント & スキル参照先

該当領域を触るときに必要なものだけ読み込むこと。

### スキル（`.agents/skills/`）
- `builder-reviewer-loop` — ビルダー／レビュアー2体による実装・レビューゲート
- `sleeves-local-verification` — CLI 検証フラグ（`--catalog-test` / `--chrome-preview` / `--delete-dialog-preview`）、`screencapture`、`CGEvent` の手順と制約
- `sleeves-plugin-dev` — シェルフエフェクトプラグイン（10種フック）と構造スタイル（Store / Ledge / Rack / Wall）の開発ガイド
- `sleeves-sparkle-release` — Sparkle 2 自動更新、EdDSA 鍵管理、リリース署名・`appcast.xml` 運用

### 設計メモ（`docs/architecture/`）
- `docs/architecture/music-playback.md` — Apple Music / MusicKit / Shortcuts / TCC / Spotify 再生・メタデータ取得仕様
- `docs/architecture/shelf-ui-and-dnd.md` — スパース配置、D&D・GhostPanel、余白・Liquid Glass・右クリック、複数シェルフ、データ永続化・旧移行仕様
- `docs/architecture/agent-plugins.md` — `cursor-team-kit` / `pstack` 導入・変換仕様と Devin / Antigravity adapter 運用メモ
