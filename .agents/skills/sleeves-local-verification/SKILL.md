---
name: sleeves-local-verification
description: "Sleeves macOSアプリのローカル検証・デバッグ手順。CLI検証フラグ(--catalog-test / --chrome-preview / --delete-dialog-preview)、os.Loggerログ監視、screencaptureによる視覚確認、CGEventでの入力合成時の注意点を使うときに読み込む。"
---

# Sleeves ローカル検証・デバッグ

## 1. ビルド・再起動・ログ取得

```bash
# プロジェクト生成(ファイル追加・削除後は必須。pbxproj直編集禁止)
make gen
# (直接実行する場合: cd apps/macos && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate)

# Debugビルド
make build
# (直接実行する場合: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/macos/Sleeves.xcodeproj -scheme Sleeves -configuration Debug -derivedDataPath .build build)

# 起動(/Applications にはインストールしない)
# 注意: open は起動中プロセスを再表示するだけで新ビルドを起動しない。必ず pkill してから open する
make run

# アプリログ取得(debugレベルを含めるには --info が必要)
make logs

# Sparkle更新ログ取得
/usr/bin/log show --last 5m --style compact --info \
  --predicate 'subsystem CONTAINS "sparkle"'
```

- `xcode-select` は CLT 向きのため、`xcodebuild` / `xcodegen` には必ず `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を付ける。
- テストで音を出すときは事前にシステム音量を 0 にし、終了後に元へ戻す。
- JSON 解析には python ではなく `jq` を使う。
- アプリの場所を移すと Launch Services 登録が壊れることがある → `lsregister -f <app>` で復旧できる。

## 2. CLI 検証経路(UI操作なしでの検証)

すべて `.build/Build/Products/Debug/Sleeves.app/Contents/MacOS/Sleeves` に引数を渡して起動する。

- **カタログ取得・再生検証**:
  ```bash
  .build/Build/Products/Debug/Sleeves.app/Contents/MacOS/Sleeves \
    --catalog-test "https://music.apple.com/jp/album/brown-sugar/1440842296" [--play]
  ```
  - UI を出さずに `MediaCatalogClient.fetch` (+ `--play` で `PlaybackEngine.play`) を実行し、結果をログ(`category: "CatalogTest"`)に出して終了する(`SleevesApp.init`)。
  - `--catalog-test` 経路では `UpdateController` (Sparkle) を生成しない。
- **クローム(ツールバー・信号ボタン)見た目確認**:
  - `Sleeves --chrome-preview`
  - 起動 1.5 秒後にプライマリウィンドウのツールバーと信号ボタンを強制表示する(3 秒で自動非表示)。マウス移動を合成せずにスクリーンショットで見た目を確認する用途。
- **削除確認ダイアログ確認**:
  - `Sleeves --delete-dialog-preview`
  - 起動 1.5 秒後に合成エントリ(`id=delete-dialog-preview`、実 store に無いため Delete は no-op)の削除確認ダイアログを `forceConfirm` で自動表示する。
  - **注意**: ダイアログ内のチェックボックスをトグルすると実 `settings.json` の `confirmDelete` を書き換える。

## 3. スクリーンショット撮影と入力合成(CGEvent)

- **スクリーンショット**:
  - `screencapture -R x,y,w,h` は画面収録権限があっても `"could not create image from rect"` で失敗することがある。
  - 全画面 `screencapture -x <path>` は安定して成功するため、実寸計測や見た目確認は全画面撮影 → クロップ/差分確認を使う。
- **ウィンドウ位置取得**: System Events でウィンドウ座標を取得できる。
- **右クリック合成 (`CGEvent`)**:
  - `mouseEventSource` で `rightMouseDown` / `rightMouseUp` を post して右クリックメニュー表示を検証できる。
  - **透明ガラス領域は合成クリックが素通りする**: `NSGlassEffectView` のみの余白・空きスロットへの `CGEvent` 右クリックは背面アプリに届くことがある。検証時は不透明なレコード画像上を狙うか、ウィンドウを `AXRaise` してから送信する(実ユーザー操作では問題ない)。
- **NSMenu 内の項目選択**:
  - 開いた `NSMenu` 内の項目選択は合成マウスクリックでは拾えず不安定。
  - メニューが開いた状態で **矢印キー + Return の `CGEvent`** なら選択できる。あるいは「メニュー表示確認」と「項目アクション検証」を分離して行う。
