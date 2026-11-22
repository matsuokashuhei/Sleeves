# 木製キュービー棚(Wooden Shelf)実装 — 引き継ぎ指示書

この文書は「レコード店の木製格子棚」実装の現時点での状態を、
次の作業を引き受けるエージェントへ引き継ぐためのもの。
**まだコミットしていない作業中ブランチ(main)の変更**なので、
まず `git status` / `git diff` で現状を確認すること。

## 背景とゴール

- PR #30 で「アクリル前柵のあるレコード店棚」(StoreShelfPlugin)を実装済み。
- 今回、ユーザーの参考写真(レコード店の木製キュービー棚: 明るい木の
  格子 + 各マス正面に細い金属ロッド + 奥に木の背板)を再現する
  構造系プラグインを新規実装した。
- Store Shelf と Wooden Shelf は「Shelf Style」ピッカーで着せ替え可能。
  ユーザーは3つ目の棚スタイルも計画中(排他トグルではなく単一選択
  ピッカー方式を要求された)。
- ユーザーの反復フィードバックを反映済み:
  1. ロッドは既定1本・位置は下側(セル高の2/3)
  2. 上下(水平板)は厚く・左右(縦仕切り)は細い → 別パラメータ化
  3. 木の質感強化(平目の木輪=山型入れ子弧を含む)
  4. 部材を太くしてもレコードに重ならないこと → グリッド幾何を
     動的にする structureSpacing フックを新設(重要な設計変更)
  5. ビンテージ感5種を「Age」スライダー1本に集約して実装

## 変更ファイル一覧

- **新規** `Sleeves/Plugins/Shelf/WoodenShelfPlugin.swift`(約1300行。実装の本体)
- `Sleeves/Plugins/ShelfPlugins.swift`
  - `ShelfPlugin.exclusiveGroup: String?`(既定nil)+
    `ShelfPluginGroups.shelfStyle = "shelf-style"`
  - `ShelfStructureSpacing` 構造体(既定12/14/8/8)+
    プロトコルフック `(g) structureSpacing(values:)`
  - `ShelfPluginRegistry.resolveSpacing(settings:)`
    (有効プラグインの要求を各項目maxで合成。排他も先着規則)
  - `resolve`/`resolveShelf` 両方で排他グループ先着1つ適用+
    スキップ時1回だけnoticeログ
- `Sleeves/Plugins/Shelf/StoreShelfPlugin.swift`: `exclusiveGroup` 追加のみ
- `Sleeves/SettingsView.swift`: 排他グループのプラグインをトグルではなく
  「Shelf Style」ピッカー(None+各displayName)で表示。選択で該当
  メンバーだけenabled=true・他false・即永続化・`shelf style changed`
  ログ・stale値のpruningも実施。選択中メンバーのパラメータUIを
  ピッカー直下に表示
- `Sleeves/ShelfView.swift`: 固定定数(12/14/8/8)を廃止し
  `private var spacing: ShelfStructureSpacing` =
  `ShelfPluginRegistry.resolveSpacing(settings:)` をグリッド・
  ドロップ位置・ゴースト座標・ウィンドウサイズに一貫使用
- `Sleeves/Localizable.xcstrings`: 新キー
  Shelf Style / None / Wooden Shelf / Wood / Pine / Oak / Rods /
  Wood Grain / Back Shade / Divider Thickness / Age(すべて6言語)
- `AGENTS.md`: 排他グループ機構とstructureSpacingの知見を追記済み
- `project.pbxproj`: xcodegen再生成済み(手編集なし)

## WoodenShelfPlugin の構造

id=`wooden-shelf`、displayName=`Wooden Shelf`、defaultEnabled=false、
exclusiveGroup=shelf-style。

- `shelfBackdrop`: 木の背板(部材より暗い同系色の縦グラデ、上ほど暗い)
  + 縦木目スジ + 節の滲み + 下部パティーナ
- `shelfOverlay`(Canvas, allowsHitTesting(false)):
  1. セル内側の陰(上20%強め/左右7%/下端接触影)
  2. キュービー4隅の汚れ(放射グラデ)
  3. 水平板: 全幅通し。色相ばらつき+パティーナ+稜線+剥げ+木目
     (柾目帯・木輪の入れ子弧・波打つ濃淡スジ)+節+傷+輪ジミ
  4. 手垢の艶(キュービー中央下の板面)
  5. 保持ロッド(カプセル、縦仕切りに潜るので先に描く)
  6. 縦仕切り: 横板間に分節。縦版の同系効果+縦傷
  7. 仕切り面の釘穴・ロッド端の黒ずみ
  8. 内部板の見切りにホコリ線
- 幾何: 内部部材は帯中央に置き両側に見切り(背板が見える隙間)。
  `structureSpacing` で 行間=板厚+4, 列間=仕切り+4,
  edge=max(板厚,仕切り)+2, top=板厚+2 を要求 →
  太くすると棚全体が大きくなりレコードに触れない(ユーザー明確要求)

パラメータ(永続化キー。変えないこと):
`wood`(pine/oak/walnut, 既定pine), `board-thickness`(8-16, 12),
`divider-thickness`(4-12, 8), `rods`(0-2, 1), `grain`(0-1, 0.6),
`age`(0-1, 0.5), `back-shade`(0-1, 0.35)

## 鉄則(AGENTS.mdより抜粋、必ず守る)

- すべてのUIアクション/非同期/エラー経路に `os.Logger`
  (subsystem `com.cacheandbuffer.Sleeves`、補間は `\(v, privacy: .public)`)
- ファイル追加・削除・リネーム後は必ず
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate`
  (pbxproj手編集禁止)
- ビルド:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Sleeves.xcodeproj -scheme Sleeves -configuration Debug -derivedDataPath .build build`
- 起動は必ず `pkill -x Sleeves` してから
  `open .build/Build/Products/Debug/Sleeves.app`
- ログ確認:
  `/usr/bin/log show --last 2m --style compact --info --predicate 'subsystem == "com.cacheandbuffer.Sleeves"'`
- 全画面 `screencapture -x <file>` は使える(`-R` は失敗することがある)
- プラグインのばらつきは決定論的(sinハッシュ `hash01` / 波ノイズ `wave01`。
  乱数や状態は持たない)

## 現在の実機状態

- 検証のため `~/Library/Application Support/Sleeves/Shelves/shelf-d5d34649/settings.json`
  を直接編集し、wooden-shelf を enabled にしてある
  (store-shelf は enabled=false、パラメータ値は保持)
- ユーザーの最新設定値(随時いじっている):
  `wood=walnut, board-thickness=16, divider-thickness=10, rods=1,
   grain=1.0, age=0.5, back-shade=0.15`
  ※grain=0.7は検証目的でこちらが設定した値が残っている可能性あり
- 確認済みログ: `wooden-shelf applied: wood=walnut thickness=16 divider=10
  rods=1 grain=1 age=0.5 backShade=0.15 grid=8x4`、
  `structure spacing resolved: col=16 row=20 edge=18 top=18`

## 未対応・注意点

- **未コミット**。ユーザーから指示があればPR作成(コミット規則は
  AGENTS.md/システム指示のGit節に従う。日本語の短い件名がこの
  リポジトリの流儀)
- ユーザーは「3つ目の棚スタイル」を計画中。追加時は
  `exclusiveGroup = ShelfPluginGroups.shelfStyle` を指定するだけで
  ピッカーに自動で並ぶ設計にしてある
- Age/Grain等の効果の強さの最終バランスはユーザーが調整中のため、
  定数の微調整依頼が来る可能性あり
- `resolveSpacing` はレイアウト計算のたびに呼ばれる(値変化時のみ
  noticeログ)。頻繁呼び出し前提の軽量さを維持すること
