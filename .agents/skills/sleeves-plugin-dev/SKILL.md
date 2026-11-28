---
name: sleeves-plugin-dev
description: "Sleevesのシェルフエフェクトプラグインおよびシェルフ構造スタイル(Store/Ledge/Rack/Wall等)を実装・改修・レビューするときに使う開発ガイド。10種フックの合成順、effectivePadding/effectiveSpacing/slotVisualRectの不変条件、WoodMaterial、スタイル追加手順を定義する。"
---

# Sleeves プラグイン & シェルフスタイル開発ガイド

## 1. 構成と基本ルール

- **基盤**: `apps/macos/Sleeves/Plugins/ShelfPlugins.swift` (`ShelfPlugin` プロトコル + `ShelfPluginRegistry`)
- **永続化モデル**: `apps/macos/Shared/ShelfPluginModel.swift`
- **合成点**: `apps/macos/Sleeves/ShelfView.swift` (`AlbumSlotView` / グリッド `.background`・`.overlay`)
- **適用順・表示順**: `ShelfPluginRegistry.all` の並び = 適用順 = 設定画面の表示順。
- **設定画面ペイン分類**: `category` (`record` / `wall` / `shelf` / `lighting` / `placement`) に基づく。サイドメニューとほぼ 1 対 1 だが、末尾の「Arrangement (飾り方)」ペインのみ `placement` (Lean Depth) と `lighting` (Ambient Light / Sleeve Gloss) の 2 カテゴリを束ねる。
- **無効化不可プラグイン**: `canDisable = false` (現状 `wall` のみ) は常時有効。設定画面に ON/OFF トグルを出さず、`resolve` / `resolveShelf` でも `settings` の `enabled` を無視する。`ShelfSettings` デコード時に `wall` の stale な `enabled=false` は `true` へ正規化する。
- **ログ**: 各プラグインは `logAppliedOnce` でプロセス内 1 回だけ解決値を `notice` ログに出す(セル描画ごとのスパム防止)。
- **決定論的ばらつき**: セル座標ハッシュ(`sin` ハッシュ)を使い、再描画・再起動で見た目が変わらないようにする。
- **ジャケット角丸**: `ShelfPluginLayout.jacketCornerRadii` / `jacketShape(cellIndex:)` で角ごとに 1pt または 2pt (`sin` ハッシュ)。セルの `clipShape` / `contentShape`、オーバーレイクリップ、ドラッグゴーストのパスマスク(非反転座標なので上下 swap)すべてがこれを共有する。

## 2. フック一覧(全10種・既定はすべて no-op)

### セル単位フック `(a) → (b) → (c) → (d)`

`applyingJacketPlugins` / `applyingCellPlugins` が合成する。

- **(a) `transformJacket`**: ジャケット**画像のみ**の修飾(色調・フィルタ等: SunFade / Yellowing 全体効果)。後段オーバーレイには掛からない。
  - **禁止**: 幾何変形(3D 回転等)をここに積むと、オーバーレイが面からずれて浮く(CAC-9 の教訓)。
- **(b) `jacketOverlay`**: ジャケット面上に描くオーバーレイ(SleeveGloss / EdgeWear / RingWear / Scuffs / Yellowing シミ)。変形前の平面で `ZStack` + `clipShape(jacketShape(cellIndex:))` 重畳され、(c) の変形に追従する。
  - **必須**: 各オーバーレイには `.allowsHitTesting(false)` を付ける(タップ再生・D&D・右クリックを奪わないため)。
- **(c) `transformJacketSurface`**: ジャケット + 全オーバーレイの合成物を 1 枚の面として変形するフック(LeanDepth の `rotation3DEffect` 等)。`rotation3DEffect` はレイアウト境界(=ヒット領域)を変えない。
- **(d) `transformCell`**: セル全体(面 + 既定影 + ホバー)を包む装飾(LeanDepth の接地影等)。

### グリッド・棚レベルフック `(e) 〜 (j)`

`ShelfPluginRegistry.resolveShelf` が解決し、`ShelfView` のグリッド `.background` / `.overlay` 等へ適用する。

- **(e) `shelfBackdrop`**: グリッド背面への描画(WallPlugin の壁 + 経年、AmbientLightPlugin の暖色被せ / 周辺減光)。padding 適用済み grid の `.background` にレジストリ順で重畳。
- **(f) `shelfOverlay`**: グリッド前面への描画(StoreShelfPlugin の棚板 + 前柵、LedgeShelfPlugin のレッジ、RackShelfPlugin の内壁・仕切り・棚板・外枠・台輪)。grid の `.overlay` にレジストリ順で重畳(合成側が `.allowsHitTesting(false)` を付与)。
- **(g) `shelfPaddingInset(values:)` / `shelfPaddingInsets(values:)`**: 外周余白への加算要求(既定 0)。辺別要求が必要な場合はタプル版 `shelfPaddingInsets` をオーバーライドする(例: RackShelfPlugin は外枠 `frameThickness`、上辺 `depth`、下辺 `plinthBoost` を要求)。
  - レジストリは有効プラグインの辺ごとの最大値を `resolvePaddingInset` で解決し、`effectivePadding(settings:)` が「導出余白 + inset」を返す。
- **(h) `shelfSpacingInset(values:)`**: レコード間隔への加算要求(既定 `(column: 0, row: 0)`)。内部部材(縦仕切り・横棚板)用の追加ピッチを宣言する(例: RackShelfPlugin は `(dividerThickness, shelfThickness)`)。
  - レジストリは成分ごとの最大値を `resolveSpacingInset` で解決し、`effectiveSpacing(settings:)` が「設定値 + inset」を返す。
- **(i) `slotContentOffset`**: スロットごとのレコード平行移動量(既定 `.zero`。RackShelfPlugin は開口中央・床の上へずらす)。`ShelfView` と `ShelfShareView` の両方で `.offset` 適用する(グリッドのピッチ・余白・ウィンドウサイズは不変)。
  - 複数スロットで読む経路では `settings` からの再解決を避け、1 回解決した `[ResolvedShelfStructure]` を `slotContentOffset(slot:resolved:)` へ渡す。
- **(j) `shelfTransparentRegions`**: ウィンドウコンテンツを透明に抜く矩形群(既定 `[]`)。`ShelfView`(グリッドのフレーム直後・オーバーレイ手前 + ガラス背景)と `ShelfShareView` の両方へ `WindowNotchShape` の `clipShape` を掛ける。
  - **注意**: 切り欠き内部は SwiftUI のヒット判定も消えるため、操作に必要な領域は宣言しないこと。`clamped` (`ScrollView` 化)時はスクロールで座標がずれるため切り欠きを無効化する。
  - オーバーレイ手前で `clipShape` するのは、ドラッグ帯・ツールバー・ドロップ受けのヒット判定を温存するため。

## 3. 必ず守る座標・レイアウト不変条件

1. **余白を読む側**(グリッド計算・`resolveShelf`・画面座標変換)は必ず `ShelfPluginRegistry.effectivePadding(settings:)` を使う(生の導出値を使うと部材とレコードがずれる)。
2. **レコードピッチを読む側**(グリッド計算・`resolveShelf`・スロット矩形・最近傍空きスロット等)は必ず `ShelfPluginRegistry.effectiveSpacing(settings:)` を使う。
3. **レコードの見た目位置を読む側**(ヒット判定・ドロップゾーン座標・ゴースト着地・最近傍空きスロット)はピッチ位置(`slotRect`)ではなくオフセット済みの `ShelfView.slotVisualRect` を使う。
4. **上辺ドラッグ帯**: `ShelfPlacement.topDragStripHeight` に 1 段目のオフセットを渡し、`dy < 0` で上へせり上がったレコードと重ならないよう縮める(0 ならオーバーレイ省略)。

## 4. シェルフ構造スタイル (`ShelfSettings.ShelfStyle`)

構造プラグインは排他選択(`"store"` / `"ledge"` / `"rack"`。未設定・未知値は `.store`)。

- **新スタイルの追加手順**:
  1. `ShelfSettings.ShelfStyle` に case を追加。
  2. `var shelfStyle: ShelfSettings.ShelfStyle?` で該当スタイルを返す構造プラグインを実装し、`ShelfPluginRegistry.all` へ登録。
  3. ピッカー・フィルタ・`resolve` / `resolveShelf` はすべて自動で連動する(非選択スタイルの構造プラグインは有効フラグに関わらず除外され、設定画面にも出ない)。
- **壁との分離**: 壁はスタイル非依存の `WallPlugin(id="wall")` に分離済み。旧 `settings.json` の `store-shelf` に残った壁キー(`wall` / `aging-*`)は `ShelfSettings.wallParamKeys` でデコード時に `wall` へ移行し、さらに `aging-warmth` / `aging-vignette` は `ambient-light` (`warmth` / `vignette`)へ第2段移行される。
- **木材テクスチャ共通化**: `apps/macos/Sleeves/Plugins/Shelf/WoodMaterial.swift` の `WoodMaterial` (`pine` / `oak` / `walnut` / `mahogany` / `black` + アセット名 + フォールバック縦グラデ)と `WoodTexture` (`Canvas` 先頭で 1 回 resolve → `paint`)を `StoreShelfPlugin` / `LedgeShelfPlugin` / `RackShelfPlugin` で共有する。
  - `WoodTexture.paint` は `baseScale` + `repeats` (`true` でタイル繰り返し、`false` で aspect-fill)をサポート。seed の `sin` ハッシュで切り出し位置をずらす際は、未描画領域が出ないよう画像端を rect 外へはみ出させる。
- **LedgeShelfPlugin (`ledge-shelf`)**: 全スロット直下に木製レッジ(空きスロットにも土台を描画)。幅はセル幅比 1/3〜11/10、厚さは `min(設定値, rowSpacing - 2, bottomPadding)` クランプ、`lip` でジャケット下端へ前唇を重ねる、`variation` でスロットごとの中心ずれ/傾きを付与。
- **RackShelfPlugin (`rack-shelf`)**: 箱型キュービックキャビネット(背板=`shelfBackdrop`、内壁・仕切り・棚板・外枠・台輪=`shelfOverlay`)。`depth > 0` で最上部 `[0, depth)` にキャビネット上面、各開口下縁に床を描画。台輪は左右 `plinthInset` (定数 16pt > 窓角丸 ≈14pt) だけ幅狭にし、脇の帯を `shelfTransparentRegions` で透明抜きしてデスクトップを透かす。木目は `baseScale=0.5, repeats=true`。
