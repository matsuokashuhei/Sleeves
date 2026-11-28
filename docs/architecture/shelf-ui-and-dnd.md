# シェルフ UI・配置・D&D・複数ウィンドウ・データ永続化の設計メモ

## 1. 自由配置（スパース）モデル

- 各 `MediaEntry` が永続化プロパティ `slotIndex`（0 始まりの行優先 index、`albums.json` に保存、デフォルト `-1` = 未配置）を持ち、その値がそのままグリッド位置になる。途中に空きスロットがあってよい。
- 旧フォーマット（キー無し）・重複・衝突は読み込み時に `ShelfPlacement.normalized` がファイル順のまま先頭の空きスロットへ割り当て、変更があった場合のみ `albums.json` へ即保存する。`entries` 配列は常に `slotIndex` 昇順。
- スロット計算の純ロジックは `apps/macos/Shared/MediaEntry.swift` の `enum ShelfPlacement`（`normalized` / `paddedSlots` / `firstEmptySlot` / `place` / `reorder` / `insertionShift` / `slotCenter` / `nearestEmptySlot` / `topDragStripHeight`）に集約し、`SleevesTests` から直接テストしている。
- `slotIndex >= capacity` のエントリは登録を保持したまま非表示（グリッドを広げれば同じスロット位置に再表示）。
  - `slotIndex` は行優先の通し番号のため、**列数 (`columns`) 変更はリフロー**、**行数 (`rows`) 変更は表示/非表示枚数の増減**となる。
- **満杯判定**: `[0, capacity)` に空きスロットが無いこと（`ShelfStore.firstEmptySlot` → `ShelfPlacement.firstEmptySlot`）。`entries.count` では判定しない（非表示エントリがあっても表示上の空きがあれば追加を受理）。

## 2. ドラッグ&ドロップと GhostPanel

### スロット計算・ドロップゾーン

- `.onDrag`（開始時に `draggedID` 記録）+ 各セル背面の左右半分に分けた `.dropDestination(for: String.self)` ゾーン。
  - **空きスロット上**: 左右どちらの半分でも `ShelfPlacement.place` で配置（他レコードは動かない）。
  - **占有セル上**: 左 = 直前 / 右 = 直後の順序挿入として `ShelfPlacement.reorder` がスライド再割当て（ギャップの向こうや非表示エントリは動かない）。
  - **新規レコード（外部テキスト/URL）**: `registerFetched(atSlot:)` → `ShelfPlacement.insertionShift`。左半分 = `index`、右半分 = `index + 1`（`>= capacity` なら最近傍空きスロット）。余白ドロップは `ShelfPlacement.nearestEmptySlot`。
  - fetch 待ちの半透明表示は `pendingAddSlot`（着地予定スロット index）で管理。
- 半透明ハイライト (`dropTargetOpacity`) は `isTargeted && willMove` のみ。`isTargeted(false)` ではシミュレーションを走らせず、その半分がセットした分だけ消す（`dropTargetAfter` で左右区別を記録し、同一スロット半分間の移動での瞬断を防止）。
- `DropDelegate(onDrop)` は `dropExited` が呼ばれない経路がありハイライトが残るため不採用。`isTargeted` はセッション終了時に必ず `false` が届く。

### GhostPanel と遅延確定

- ドラッグ表示は画面座標で動く別ウィンドウ `GhostPanel`（`styleMask=[.borderless, .nonactivatingPanel]`, `ignoresMouseEvents`, `level=CGWindowLevelForKey(.draggingWindow)`, 元ウィンドウの子ウィンドウ）に一本化。
  - ウィンドウ内 `NSView` オーバーレイだとウィンドウ外へ出た瞬間にクリップされるため別ウィンドウにする。
  - `.onDrag(preview:)` に透明 1px を渡してシステムのドラッグ画像を無効化（スライドバック二重表示の防止）。
- ゴーストはアプリ全体で 1 個 (`GhostController.shared`)。
  - シェルフ間ドロップ時はドロップ先が `takeOver` で所有権を引き継ぎ、ポインタ追従 (`trackingEnabled`) を切ったうえで着地スロットへ飛ばす。
  - 所有権ガード (`ghost.owner == nil || ghost.owner == shelfID`) は `startDrag` のアートワークロード完了時、`flyGhost` 完了時、元シェルフの終了検知の 3 箇所にある。
- **遅延確定**: `perform` / `transferDrop` では `ShelfPlacement` をシミュレートするだけにとどめ、`flyGhost` の着地 (`onLanded`) でその時点の `entries` に対して再シミュレート＋ `ShelfStore.applyPlacement(_:)` で確定する（シェルフ間転送も着地で `applyPlacement` + 元シェルフ `remove`）。`perform` 時点で確定すると飛行中にレコードが二重表示されるため。
- **追従と禁止事項**:
  - `leftMouseDragged` はドラッグセッションに吸収されるため、60fps タイマー（`.common` モード）で `NSEvent.mouseLocation` をポーリングし、パネルの `frame` を命令的に動かす。
  - **禁止**: ドラッグ中の高頻度な `@State` 更新（`body` 再評価で走行中クロージャが破棄され `EXC_BAD_ACCESS` でクラッシュする）。
- **終了検知**: `leftMouseUp` / `mouseMoved` のローカルモニタで検知するが、`mouseUp` は `perform` より先に届くため **50ms 遅延**で判定する（即判定するとドロップをキャンセル誤認する）。
- **座標変換**:
  - ゴースト自体は画面座標で管理し、飛行先のみ `slotScreenCenter` でスロット中心（`slotVisualRect`）→ 画面座標に変換する（グリッド上端 = ウィンドウ上端のためタイトルバー帯の控除は不要）。
  - 外部ドロップや右クリックのウィンドウ座標 → グリッド座標には `overlayGridPoint` と `slotInsertion` を使う（いずれも `windowBox.window` を参照し、非 key ウィンドウでも狂わないようにする）。

### 外部ドラッグ（Music 等）のモーフィング

- `NSDraggingItem.setDraggingFrame` は値を書き換えても描画サイズが元画像の約 128pt 角のまま変わらない（実機確認済み）。`contents` 差し替えのみ反映される。
- そのため `ExternalDropOverlayView` ではシステム画像を `contents = nil` で隠し、ウィンドウ内ドラッグと同じ `GhostPanel` で描画する。

## 3. ウィンドウ余白・タイトルバー・クローム・右クリック

### 余白とウィンドウサイズ

- `settings.json` に永続化されるのは `columnSpacing`（既定 12、0〜64）と `rowSpacing`（既定 14、0〜96）のみ（スライダーは transient 更新 + 400ms デバウンス保存）。
- 余白は `ShelfSettings` の導出値: `edgePadding = columnSpacing`、`topPadding = max(4, rowSpacing)`（4pt 下限は `WindowDragStrip` 帯確保）、`bottomPadding = rowSpacing`（下限なし）。
  - プラグインからの追加要求があるため、参照側は必ず `ShelfPluginRegistry.effectivePadding` / `effectiveSpacing` を使う。
- コンテンツは `.ignoresSafeArea()` でウィンドウ上端まで広げ、`.windowStyle(.hiddenTitleBar)` でタイトルバー下のセパレータ線を消す。
- `.windowResizability(.contentSize)` は理想サイズにタイトルバー帯 32pt を足すため、ビュー側に `.padding(.bottom, -32)` を付けてウィンドウとグリッドの高さを一致させている。
- 上辺のウィンドウ移動は AppKit ベースの `WindowDragStrip`（`apps/macos/Sleeves/WindowGlass.swift`、`acceptsFirstMouse = true`、`NSWindow.performDrag(with:)`）で行う（SwiftUI の `WindowDragGesture` は複数シェルフ時に効かなくなるため置換）。右上ツールバー表示領域 (`excludedRect`) と可視の標準信号ボタンは `hitTest` で `nil` を返す。

### 信号ボタン・右上ツールバー・Liquid Glass

- シェルフ操作は右上のカプセル型ツールバー（共有ボタン + 3 点リーダー `Menu`: New Shelf / Settings… / Delete Shelf…）に集約。
  - 共有は `ShelfShareView` を画像レンダリングし、`NSSharingServicePicker`（`SharePickerDelegate` を `@State` で生存保持）で開く。
- **自動表示/非表示 (`ChromeVisibilityController`)**: ウィンドウがアクティブでマウスが動いたら表示、3 秒無操作または非アクティブで非表示（`window.acceptsMouseMovedEvents = true` 必須、タイマー張り直しは 250ms 間引き）。メニュー表示中・アラート表示中・共有ピッカー表示中は `setHold(_:active:)` で隠しタイマーを止める。
- **信号ボタン**: Apple 標準（閉じる/最小化のみ、ズームは常時非表示）。左上 9pt → 13pt へ 4pt 内側寄せ（`applyTrafficLightInset` を `NSWindow.didUpdateNotification` で冪等再適用）。
- **Liquid Glass**:
  - 信号ボタン背面: `NSGlassEffectView`（ヒットテスト `nil`、外接矩形 + 5pt の角丸カプセル、`tintColor = .black.opacity(0.45)`）。
  - 右上ツールバー: `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())`、上 8pt / 右 18pt / 高さ 24pt / アイコン 14pt（信号ボタンと中心 Y = 20pt を揃える）。
  - 左右に離れており片方が AppKit レイヤーのため `GlassEffectContainer` は使わない。

### 右クリックメニューと削除確認

- SwiftUI の `.contextMenu` はセルの `.onTapGesture`（クリック再生）と競合してレコード上で開かないため、`NSEvent.addLocalMonitorForEvents` で右クリックを拾って `NSMenu` を出す（`makeContextMenuMonitor`、アクション保持用の `ClosureActionTarget` を生存させる）。
- メニューは**レコード上のみ**（`Delete Record`）。空きスロット・余白・クローム上 (`isOverChrome`) では出さない。
- 削除確認は `DeleteConfirmationDialog`（`NSPanel` + SwiftUI、チェックボックスを最下部に置くため `NSAlert` ではなく自前化）を `NSApp.runModal(for:)` で表示。Return = Delete / Escape = Cancel。`ShelfSettings.confirmDelete`（既定 `true`）が `false` なら即削除。

## 4. 複数シェルフ

- 1 シェルフ = 1 ウィンドウ。`ShelfManager`（`apps/macos/Shared/`）が `shelves.json` と各 `ShelfStore(shelfID:)` を管理。
- 新シェルフは `⇧⌘N`（`CommandGroup(replacing: .newItem)`）または右上メニューから作成。新シェルフおよび読み込み失敗時の fallback は空で始まる（プリセットシードは廃止）。
- `WindowGroup(id: "shelf", for: String.self)` に `.restorationBehavior(.disabled)` + `.defaultLaunchBehavior(.presented)` を付け、自前復元（`openMissingShelfWindows`）に一本化（設定画面単独復元でシェルフ窓が 0 枚になる問題や二重オープンを防止）。
- フォーカス追跡: `WindowConfigurator` の `didBecomeKey` 通知で `ShelfManager.focusedStore` を更新し、`Window(id: "settings")`（`SettingsView`）がこれを編集する。`ShelfView` は `ShelfManager.shared` を `@ObservedObject` で監視せず、`$shelfIDs` のみ `.onReceive` で購読して `canDeleteShelf` を更新する。
- クローズ済みウィンドウのモニタ再登録防止: `WindowConfigurator.View` は `NSWindow.willCloseNotification` で `isClosing = true` を立て、`updateNSView` で `guard !view.isClosing` により再登録を遮断する。
- `PlaybackMonitor` のポーリングは参照カウント式（`.onAppear` で +1、`.onDisappear` で -1、0 で停止）。
- シェルフ間ドラッグはペーストボードに `ShelfDragPayload` (`sourceShelfID` + `MediaEntry` の JSON) を載せる。元ウィンドウの終了検知は `entries` 所属ではなく `ghost.owner` で移動済みを判定する。

## 5. データ永続化と旧バージョン移行

- シェルフ一覧: `~/Library/Application Support/Sleeves/shelves.json`（シェルフ ID 配列、先頭がプライマリ `"main"`）。
- 各シェルフのデータ・設定: `~/Library/Application Support/Sleeves/Shelves/<shelfID>/{albums,settings}.json`（旧ルートの `albums.json` / `settings.json` は起動時に `Shelves/main/` へ自動移行）。
- アートワーク: `~/Library/Application Support/Sleeves/Artwork/<id>.jpg`（全シェルフ共有。削除時は `ShelfManager.isEntryUsedElsewhere` で他シェルフの使用を確認）。
- 非サンドボックスで上記ディレクトリを使用。
- 旧アプリ名 `Records` 時代の `~/Library/Application Support/Records` は初回起動時に `ShelfStore.migrateLegacyDataDirectoryIfNeeded` で自動移行される（新旧両方ある場合や失敗時は旧を残して続行）。
