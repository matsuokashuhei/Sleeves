//
//  RackShelfPlugin.swift
//  Sleeves
//
//  プラグイン「レコードラック」(構造系、shelfStyle=.rack)。
//  masterwal KOROVA RECORD RACK 風の箱型キュービックキャビネット:
//  グリッド全面を木の箱に見立て、各スロットは箱の開口になる。
//  ジャケットはセルいっぱいの大きさで、開口がセルより広い
//  分(各辺の残り=leftover)だけ内壁の奥に納まって見える。
//  空きスロットには暗い背板が残り、キュービーの奥行きと
//  して見える(この棚の見た目の肝)。
//  壁と経年表現はスタイル非依存のWallPluginが担当する。
//
//  幾何モデル(2026-11 再改訂):
//  不変にするのは「レコード同士の見た目の距離」だけ: ジャケットの
//  見える端同士の間の空気(部材に覆われない隙間)が常に
//  Shelf/Record Spacing設定値で、レコードは部材に覆われない。
//  内部部材(縦仕切り・横棚板)はその設定間隔にshelfSpacingInsetで
//  要求した専有帯を加えた実効間隔の中に置くので、contextの
//  columnSpacing/rowSpacingはeffectiveSpacing(設定値+
//  このプラグインのshelfSpacingInset要求)の実効値で、
//  レコードピッチだけがinset分だけ広がる(レコード同士の見た目の
//  隙間=残りは設定値のまま)。
//
//  キュービー開口(aperture)はセルrectを各辺の「残り」分だけ
//  外側へ広げた矩形(部材の内縁まで広がる。実家具と同じく
//  開口同士の距離=部材の太さになる)。開口はレコードより
//  大きくなり、レコードは暗い奥行きの中に納まって見える。
//  残りは負にしないので、開口がセルより小さくなることはない
//  (=部材がジャケットを覆わない)。各辺の残り:
//   - 内部境界(縦仕切り): max(0, (columnSpacing−dividerFace)/2)
//     ずつ左右へ。columnSpacingは実効値(設定値+divider設定値)
//     なのでdividerFace=設定値、残りは設定columnSpacing/2ずつで
//     一定(=dividerOffset。部材が太くなっても残りは減らない)
//   - 内部境界(横棚板): max(0, (rowSpacing−shelfFace)/2)ずつ上下へ。
//     同じくshelfFace=設定値、残りは設定rowSpacing/2ずつで一定
//     (=shelfOffset)
//   - 外側境界(外枠): max(0, edgePadding−sideFace) /
//     max(0, topPadding−topFace) /
//     max(0, bottomPadding−bottomFace−plinthH)
//
//  各部材の前面は「配置領域」(縦仕切り=実効columnSpacing、
//  横棚板=実効rowSpacing、外枠=各辺のpadding)の内側に収める。
//  ここでのpaddingは導出値ではなくeffectivePadding
//  (ShelfPluginRegistry.effectivePadding = 各辺で
//  導出値+プラグインのshelfPaddingInset要求の合計)。
//  このプラグインはshelfPaddingInsetでframeThicknessを要求する
//  ため、外枠は間隔由来の余白(導出値)とは別に設定太さぶんの
//  専有帯を外周へ持つ。導出値はそのまま残るので、枠が太く
//  なっても開口の残り(=配置領域−前面)は導出値の余白として
//  確保され続け、枠は設定値どおりの厚さで描ける
//  (=Frame ThicknessをSpacing系スライダーから切り離す機構。
//  グリッドがinset分だけ広がるだけでレコード位置は不変):
//   - 縦仕切り: 実効前面幅 = min(設定太さ, 実効columnSpacing)、
//     実効列間隔の中央に配置、全高。spacing insetにより実効上は
//     設定太さそのもので、残りには設定columnSpacingの半分が
//     左右へ残る(=Divider ThicknessをSpacing系スライダーから
//     切り離す機構。ピッチはinset分だけ広がる)
//   - 横棚板: 実効前面幅 = min(設定太さ, 実効rowSpacing)、
//     実効行間隔の中央に配置、全幅。同様に残りは設定
//     rowSpacing/2ずつ
//   - 外枠: 実効前面幅 = min(設定太さ, 各辺のpadding)、窓端寄せ
//     (側板は左右窓端、天板は上端、底板は下端寄せで台輪の上)。
//     inset要求によりpadding=導出値+設定太さなので実効上は
//     設定太さそのものになり、導出値ぶんの帯が残りとして残る
//     (下辺は台輪がその帯の一部を使う)
//   - 台輪: 窓下端に置く張り出しベース。高さ =
//     min(bottomPadding×0.35, bottomPadding−bottomFace)
//     (bottomFaceはクランプ後の実効幅)
//
//  配置領域−前面=残り領域は開口に組み込み、キュービーの内壁
//  (開口縁から奥へ退がる暗い側面=内壁リング・背板・AOの
//  シェーディング)として見せる。設定太さが配置領域を超えた分
//  (excess)は表示しない(前面はmin(太さ,配置領域)で頭打ち)。
//  外枠・縦仕切り・横棚板はexcessをクランプで捨てる代わりに
//  shelfPaddingInset/shelfSpacingInsetでグリッド自体を専有帯
//  ぶん広げるため、通常excessは発生しない。
//
//  端ケース:
//   - 内部部材の太さ=0: その軸のspacing inset要求も0なので
//     実効間隔=設定値。前面なし、残り=設定値/2ずつ両開口が
//     中央で接する(壁共有=キュービーが隣接して見える)
//   - 設定間隔=0かつ部材太さ>0: 実効間隔=部材太さ、前面=間隔
//     いっぱい、残り0で開口=セルが部材面に接する
//   - 設定間隔=0かつ部材太さ=0: 前面・残りとも0で開口=セルが
//     隣接キュービーと接する
//
//  縦仕切り×横棚板の十字部は横部材が覆う: 全高の縦部材系→
//  全幅の横部材系の順で描く。
//
//  座標はすべて「padding適用済みグリッドの左上原点」
//  (=ShelfStructureContextの定義するフレーム)で計算する。
//
//  shelfBackdrop(各マスの奥):
//   - 背板: 選択木材と同系統だが暗く落ちた面で開口全体を埋める
//     (空きスロットでは暗い開口全体が見える)。
//     木目を描いた上に黒の半透明レイヤを掛け、上端・角がより
//     暗い周辺減光を添える(キュービー内部へは光が回り込まない
//     表現)
//
//  shelfOverlay(開口の内壁+部材前面):
//   - (a) 内壁リング: 開口の内縁に沿って幅revealの内壁。
//     天井面(上)は最も暗く、側壁(左右)は中間の暗さの奥行き
//     グラデ、床面(下)は手前がわずかに明るい(床が光を拾う)
//     方向別シェーディング
//   - (b) 開口内側の稜: 内壁と背板/LPの隙間を示す1.5ptの細帯+
//     開口内へ落ちる柔らかい陰影(AO。上辺が最も強く数ptで
//     フェード)
//   - (c) 縦仕切り前面: 列間隔の中央に実効幅の縦目部材
//     (両開口側の稜に細いハイライト+数ptの陰影)
//   - (d) 横棚板前面: 行間隔の中央に同様の横目部材。
//     十字部はこの横部材が縦部材を覆う
//   - (e) 外枠: 左右側板(窓端寄せ、縦目)→天板(同。全幅で
//     側板の上に被さる。上端に2-3ptの明るい上面スリバ)→
//     底板+台輪(台輪は窓端に置きその上に底板を積む。
//     上端の微かなハイライト+下端を暗く締める)
//
//  オーバーレイは合成側(ShelfView.shelfGrid)が
//  .allowsHitTesting(false) で重ねるので、再生タップ・D&D・
//  右クリックメニュー・ドロップゾーンは従来通り動く。
//  shelfStyle=.rackが選択されていないときはレジストリの
//  resolveShelfで除外される。
//  未保存時の既定は有効(defaultEnabled=true。構造系なので
//  スタイルを選んだ時点で棚らしい見た目になる)。
//

import SwiftUI
import os

struct RackShelfPlugin: ShelfPlugin {

    private static let logger = Logger(
        subsystem: "com.cacheandbuffer.Sleeves", category: "Plugins")

    /// パラメータID。PluginState.valuesの永続化キーになるので
    /// 一度決めたら変更しない(変えると保存済みの値が効かなくなる)
    private enum Param {
        /// 木材の色。選択肢idの文字列で永続化
        static let wood = "rack-wood"
        /// 外枠(左右側板+天板+底板)の設定太さ(pt)。この値は
        /// shelfPaddingInsetの要求値でもあり、effectivePaddingが
        /// 間隔由来の余白へこの太さを**加算**するので実効前面幅は
        /// 通常設定値そのものになる(minクランプは安全側の残置)
        static let frameThickness = "rack-frame-thickness"
        /// 縦仕切りの設定太さ(pt)。この値はshelfSpacingInsetの
        /// column要求値でもあり、effectiveSpacingがcolumnSpacingへ
        /// この太さを**加算**するので実効前面幅は通常設定値
        /// そのものになり、残りは左右の開口へ設定columnSpacing/2
        /// ずつ組み込まれる(minクランプは安全側の残置)
        static let dividerThickness = "rack-divider-thickness"
        /// 横棚板の設定太さ(pt)。この値はshelfSpacingInsetの
        /// row要求値でもあり、effectiveSpacingがrowSpacingへこの
        /// 太さを**加算**するので実効前面幅は通常設定値そのものに
        /// なり、残りは上下の開口へ設定rowSpacing/2ずつ組み込まれる
        /// (minクランプは安全側の残置)
        static let shelfThickness = "rack-shelf-thickness"
    }

    /// デフォルト値
    /// 素材はStoreShelfPluginの棚板・LedgeShelfPluginのレッジと
    /// 共通のWoodMaterial。rawValueは永続化値なので変えない
    private static let defaultWood = WoodMaterial.walnut
    static let defaultFrameThickness: Double = 16
    static let defaultDividerThickness: Double = 8
    static let defaultShelfThickness: Double = 8
    /// 内壁幅(pt)。かつてRevealスライダーだったが設定は廃止し、
    /// 内壁リングと開口AOの描画に使う定数として残す
    private static let innerWallWidth: CGFloat = 5

    /// 内壁の方向別シェーディング(外側=手前面→内側=奥の黒opacity)。
    /// 天井面は最も暗く、側壁は中間、床面は手前がわずかに明るい
    private static let wallTopOuter: Double = 0.45
    private static let wallTopInner: Double = 0.75
    private static let wallSideOuter: Double = 0.32
    private static let wallSideInner: Double = 0.62
    private static let wallBottomOuter: Double = 0.12
    private static let wallBottomInner: Double = 0.50
    /// 開口内側の稜: 内壁と背板/LPの隙間を示す細帯とAO。
    /// AOは上辺が最も強く(天井面からの落ち影)、数ptでフェードする
    private static let gapLineOpacity: Double = 0.50
    private static let gapLineWidth: CGFloat = 1.5
    private static let aoTopDepth: CGFloat = 9
    private static let aoTopOpacity: Double = 0.32
    private static let aoSideDepth: CGFloat = 6
    private static let aoSideOpacity: Double = 0.20
    private static let aoBottomDepth: CGFloat = 5
    private static let aoBottomOpacity: Double = 0.16
    /// 部材前面の開口側の稜: 1ptの薄いハイライト(角が光を拾う)+
    /// 内側へフェードする陰影グラデ(面が開口へ向かって僅かに落ちる)
    private static let edgeShadeDepth: CGFloat = 3
    private static let edgeShadeOpacity: Double = 0.28
    private static let edgeHighlightOpacity: Double = 0.12
    /// 稜のハイライト色(温かみのある白。LedgeShelfPluginと同じ)
    private static let edgeHighlight = Color(red: 1, green: 0.96, blue: 0.88)
    /// 背板の暗がり(木目の上に掛ける黒)と周辺減光
    private static let backTopOpacity: Double = 0.55
    private static let backBottomOpacity: Double = 0.42
    private static let backVignetteTop: Double = 0.30
    private static let backVignetteSide: Double = 0.22
    private static let backVignetteBottom: Double = 0.16
    /// 天板上端の上面スリバ(上面が光を拾う表現)
    private static let topSliverOpacity: Double = 0.30
    /// 台輪(張り出しベース): 高さはbottomPaddingの3.5割と
    /// bottomPadding−底板実効幅(底板の上に残る空き)の小さい方に
    /// クランプ(枠が太いと台輪が潰れる)。本体より一段暗く、
    /// 上端に微かなハイライト、下端を暗く締める
    private static let plinthRatio: CGFloat = 0.35
    private static let plinthDarken: Double = 0.18
    private static let plinthTopOpacity: Double = 0.15
    private static let plinthBottomOpacity: Double = 0.30

    let id = "rack-shelf"
    let displayName = "Record Rack"
    let category: ShelfPluginCategory = .shelf
    /// 構造系プラグインは既定で有効(スタイルを選んだ時点で
    /// 棚らしい見た目にする)
    let defaultEnabled = true
    /// 箱型キュービックキャビネットはrackスタイルの支え構造
    let shelfStyle: ShelfSettings.ShelfStyle? = .rack

    init() {
        Self.logger.info("plugin registered: rack-shelf ('Record Rack')")
    }

    var parameterSpecs: [PluginParameterSpec] {
        [
            .options(.init(
                id: Param.wood,
                label: "Wood",
                choices: WoodMaterial.allCases.map { .init($0) },
                defaultValue: Self.defaultWood.rawValue
            )),
            .slider(.init(
                id: Param.frameThickness,
                label: "Frame Thickness",
                range: 0...64,
                step: 1,
                defaultValue: Self.defaultFrameThickness
            )),
            .slider(.init(
                id: Param.dividerThickness,
                label: "Divider Thickness",
                range: 0...64,
                step: 1,
                defaultValue: Self.defaultDividerThickness
            )),
            .slider(.init(
                id: Param.shelfThickness,
                label: "Shelf Thickness",
                range: 0...64,
                step: 1,
                defaultValue: Self.defaultShelfThickness
            )),
        ]
    }

    // MARK: - (e) グリッド背面(キュービーの背板)

    func shelfBackdrop(context: ShelfStructureContext) -> AnyView? {
        let wood = resolvedWood(context: context)
        let members = resolvedMembers(context: context)
        let cell = context.cellSize
        return AnyView(
            Canvas { gc, size in
                guard size.width > 0, size.height > 0, cell > 0 else { return }
                // 木目テクスチャはループの外で1回だけ解決する
                // (素材は部材前面と共通のWoodMaterial)
                let texture = WoodTexture(material: wood, in: gc)
                if !texture.isAvailable { logMissingTextureOnce(material: wood) }
                for r in 0..<context.gridRows {
                    for c in 0..<context.gridColumns {
                        let slot = r * context.gridColumns + c
                        // 背板は開口(セルrectを残り分だけ広げた
                        // aperture)全体を埋める。間隔/余白の残り領域は
                        // 開口に組み込まれるので、この暗い面がキュービーの
                        // 奥行きとして見える(部材前面の下までは届かない
                        // — 開口の外縁は部材の内縁で止まる)
                        let rect = apertureRect(
                            column: c, row: r, context: context,
                            members: members)
                        guard rect.width > 0, rect.height > 0 else {
                            continue
                        }
                        // 背板: 同じ木材の暗く落ちた面。
                        // 切り出し位置はスロットごとにずらす
                        // (テクスチャ欠落時はWoodTexture内でグラデに退く)
                        texture.paint(
                            context: gc, path: Path(rect),
                            rect: rect, seed: Double(slot))
                        // 上がより暗い半透明レイヤ(奥行き)
                        gc.fill(
                            Path(rect),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .black.opacity(Self.backTopOpacity),
                                    .black.opacity(Self.backBottomOpacity),
                                ]),
                                startPoint: CGPoint(x: 0, y: rect.minY),
                                endPoint: CGPoint(x: 0, y: rect.maxY)))
                        // 周辺減光: 上端・角がより暗い(内部へ光が
                        // 回り込まない)。4辺の帯が角で重なり角が沈む
                        // (帯の深さは開口サイズ比例)
                        let topH = rect.height * 0.40
                        let topBand = CGRect(
                            x: rect.minX, y: rect.minY,
                            width: rect.width, height: topH)
                        gc.fill(
                            Path(topBand),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .black.opacity(Self.backVignetteTop),
                                    .clear,
                                ]),
                                startPoint: CGPoint(x: 0, y: topBand.minY),
                                endPoint: CGPoint(x: 0, y: topBand.maxY)))
                        let bottomH = rect.height * 0.25
                        let bottomBand = CGRect(
                            x: rect.minX, y: rect.maxY - bottomH,
                            width: rect.width, height: bottomH)
                        gc.fill(
                            Path(bottomBand),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .black.opacity(Self.backVignetteBottom),
                                    .clear,
                                ]),
                                startPoint: CGPoint(x: 0, y: bottomBand.maxY),
                                endPoint: CGPoint(x: 0, y: bottomBand.minY)))
                        let sideW = rect.width * 0.22
                        let leadingBand = CGRect(
                            x: rect.minX, y: rect.minY,
                            width: sideW, height: rect.height)
                        gc.fill(
                            Path(leadingBand),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .black.opacity(Self.backVignetteSide),
                                    .clear,
                                ]),
                                startPoint: CGPoint(x: leadingBand.minX, y: 0),
                                endPoint: CGPoint(x: leadingBand.maxX, y: 0)))
                        let trailingBand = CGRect(
                            x: rect.maxX - sideW, y: rect.minY,
                            width: sideW, height: rect.height)
                        gc.fill(
                            Path(trailingBand),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .black.opacity(Self.backVignetteSide),
                                    .clear,
                                ]),
                                startPoint: CGPoint(x: trailingBand.maxX, y: 0),
                                endPoint: CGPoint(x: trailingBand.minX, y: 0)))
                    }
                }
            }
            // 背面なのでセルのヒット判定には影響しないが、空き領域への
            // タップを食わないよう保険を掛ける(WallPluginと同じ)
            .allowsHitTesting(false)
        )
    }

    // MARK: - (f) グリッド前面(開口の内壁+部材前面)

    func shelfOverlay(context: ShelfStructureContext) -> AnyView? {
        let wood = resolvedWood(context: context)
        let reveal = resolvedReveal(context: context)
        let members = resolvedMembers(context: context)
        let cell = context.cellSize
        logAppliedOnce(
            wood: wood, reveal: reveal, members: members,
            columns: context.gridColumns, rows: context.gridRows)
        return AnyView(
            Canvas { gc, size in
                guard size.width > 0, size.height > 0, cell > 0 else { return }
                let texture = WoodTexture(material: wood, in: gc)
                if !texture.isAvailable { logMissingTextureOnce(material: wood) }

                // (a) 内壁リング + (b) 開口内側の隙間ラインとAO。
                // 開口(aperture)の内側に描く。開口はセルrectを残り分
                // だけ広げた矩形なので、残り領域はキュービーの内壁
                // (開口縁から奥へ退がる暗い側面)として見える。
                // revealがその辺の残り(leftover)を超える分だけ
                // ジャケット端を覆う従来挙動はそのまま(残りが
                // reveal以上ならリングはジャケットに届かない)
                for r in 0..<context.gridRows {
                    for c in 0..<context.gridColumns {
                        let slot = Double(r * context.gridColumns + c)
                        let rect = apertureRect(
                            column: c, row: r, context: context,
                            members: members)
                        guard rect.width > 0, rect.height > 0 else {
                            continue
                        }
                        paintInnerWalls(
                            texture, in: gc, rect: rect,
                            reveal: reveal, seed: slot)
                        paintApertureAO(gc, rect: rect, reveal: reveal)
                    }
                }

                // (c) 縦仕切り前面: 列間隔の中央に実効幅の縦目部材
                // (全高。上下端と十字部は後から描く横部材・外枠が
                // 被さる)。間隔−前面の残りは左右の開口へ半分ずつ
                // 組み込まれている(部材の内縁=両開口の外縁)。
                // 間隔0なら前面幅0で描かれず、開口が隣接キュービーと
                // 接する(壁共有)
                if context.columnSpacing > 0 {
                    for c in 0..<(context.gridColumns - 1) {
                        let gapX = context.edgePadding
                            + CGFloat(c + 1) * cell
                            + CGFloat(c) * context.columnSpacing
                        let faceX = gapX + members.dividerOffset
                        paintMember(
                            texture, in: gc,
                            rect: CGRect(
                                x: faceX, y: 0,
                                width: members.dividerFace,
                                height: size.height),
                            vertical: true, seed: Double(c),
                            openingEdges: [.leading, .trailing])
                    }
                }

                // (d) 横棚板前面: 行間隔の中央に実効幅の横目部材
                // (全幅。両端は後から描く外枠が被さり、十字部はこの
                // 横部材が縦部材を覆う)
                if context.rowSpacing > 0 {
                    for r in 0..<(context.gridRows - 1) {
                        let gapY = context.topPadding
                            + CGFloat(r + 1) * cell
                            + CGFloat(r) * context.rowSpacing
                        let faceY = gapY + members.shelfOffset
                        paintMember(
                            texture, in: gc,
                            rect: CGRect(
                                x: 0, y: faceY,
                                width: size.width,
                                height: members.shelfFace),
                            vertical: false, seed: 100 + Double(r),
                            openingEdges: [.top, .bottom])
                    }
                }

                // (e) 外枠: 側板→天板→底板+台輪の順で、被さる側を
                // 後に描く。各部材は窓端寄せで、内側の残りは端スロット
                // 開口へ組み込まれている(部材の内縁=開口の外縁)
                if context.edgePadding > 0 {
                    // 左側板: [0, sideFace)=前面(窓端寄せ、縦目)
                    paintMember(
                        texture, in: gc,
                        rect: CGRect(
                            x: 0, y: 0,
                            width: members.sideFace,
                            height: size.height),
                        vertical: true, seed: 200,
                        openingEdges: [.trailing])
                    // 右側板: [width−sideFace, width)=前面
                    paintMember(
                        texture, in: gc,
                        rect: CGRect(
                            x: size.width - members.sideFace, y: 0,
                            width: members.sideFace,
                            height: size.height),
                        vertical: true, seed: 201,
                        openingEdges: [.leading])
                }
                if context.topPadding > 0 {
                    // 天板: [0, topFace)=前面(全幅で側板の上に被さる)
                    paintMember(
                        texture, in: gc,
                        rect: CGRect(
                            x: 0, y: 0,
                            width: size.width, height: members.topFace),
                        vertical: false, seed: 300,
                        openingEdges: [.bottom])
                    // 上面スリバ: 天板の上端2-3ptが上面の光を拾う
                    let sliverH = min(3, members.topFace)
                    if sliverH > 0 {
                        let sliver = CGRect(
                            x: 0, y: 0, width: size.width, height: sliverH)
                        gc.fill(
                            Path(sliver),
                            with: .linearGradient(
                                Gradient(colors: [
                                    Self.edgeHighlight.opacity(
                                        Self.topSliverOpacity),
                                    Self.edgeHighlight.opacity(
                                        Self.topSliverOpacity * 0.3),
                                ]),
                                startPoint: CGPoint(x: 0, y: sliver.minY),
                                endPoint: CGPoint(x: 0, y: sliver.maxY)))
                    }
                }
                if context.bottomPadding > 0 {
                    // 下端の窓端寄せ帯: 窓端から台輪(plinth)→底板
                    // (bottomFace)。底板の上〜最下段開口の残りは
                    // 開口へ組み込まれている
                    let boardY = size.height
                        - members.plinthH - members.bottomFace
                    paintMember(
                        texture, in: gc,
                        rect: CGRect(
                            x: 0, y: boardY,
                            width: size.width, height: members.bottomFace),
                        vertical: false, seed: 301,
                        openingEdges: [.top])
                    if members.plinthH > 0 {
                        let plinth = CGRect(
                            x: 0, y: size.height - members.plinthH,
                            width: size.width, height: members.plinthH)
                        texture.paint(
                            context: gc, path: Path(plinth),
                            rect: plinth, seed: 302)
                        // ベースは本体より一段暗い板
                        gc.fill(
                            Path(plinth),
                            with: .color(.black.opacity(Self.plinthDarken)))
                        // 上端の微かなハイライト(張り出しの天面が
                        // 光を拾う)+下端を暗く締める(床への落ち影)
                        gc.fill(
                            Path(CGRect(
                                x: 0, y: plinth.minY,
                                width: size.width, height: 1)),
                            with: .color(Self.edgeHighlight.opacity(
                                Self.plinthTopOpacity)))
                        let footH = min(3, members.plinthH)
                        let foot = CGRect(
                            x: 0, y: plinth.maxY - footH,
                            width: size.width, height: footH)
                        gc.fill(
                            Path(foot),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .clear,
                                    .black.opacity(Self.plinthBottomOpacity),
                                ]),
                                startPoint: CGPoint(x: 0, y: foot.minY),
                                endPoint: CGPoint(x: 0, y: foot.maxY)))
                    }
                }
            }
            // 部材前面・内壁がジャケットのタップ再生・D&D・
            // 右クリック・ドロップゾーンのヒット判定を食わない
            // ようにする(必須)
            .allowsHitTesting(false)
        )
    }

    // MARK: - (g) 外周余白への追加要求(inset)

    /// 外枠の実効前面幅は各辺のpaddingにクランプされる
    /// (resolvedMembers参照)。paddingの導出値
    /// (edge=columnSpacing、top=max(4,rowSpacing)、bottom=rowSpacing)
    /// はSpacing系スライダーで小さくできるため、そのままだと
    /// 設定したFrame Thicknessより薄い枠しか描けなかった。
    /// ここでframeThicknessを外周余白への追加分(inset)として
    /// 要求すると、effectivePaddingが 導出値+inset にグリッドを
    /// 広げ、枠は設定太さどおり専有帯に描ける
    /// (=Frame ThicknessをSpacing系から切り離す。導出値は残る
    /// ので開口の残り=奥行き感は枠の太さに依らない)。
    /// 縦仕切り/横棚板はレコード間隔のクランプなのでこちらではなく
    /// shelfSpacingInsetで要求する
    func shelfPaddingInset(values: [String: PluginParameterValue]) -> CGFloat {
        max(0, CGFloat(values[Param.frameThickness]?.number
            ?? Self.defaultFrameThickness))
    }

    // MARK: - (h) レコード間隔への追加要求(spacing inset)

    /// 縦仕切り・横棚板の実効前面幅は実効間隔(配置領域)に
    /// クランプされる(resolvedMembers参照)。間隔の設定値
    /// (columnSpacing/rowSpacing)はレコード同士の隙間そのもの
    /// なので、部材の太さが間隔を食うと開口の残り(recess)が
    /// 減ってしまう(=Shelf/Divider Thicknessを上げるとレコード
    /// 間の空気が痩せる問題)。ここでdividerThickness/
    /// shelfThicknessをレコード間隔への追加分(inset)として
    /// 要求すると、effectiveSpacingが設定間隔+insetにレコード
    /// ピッチを広げ、部材は専有の帯に設定太さどおり描ける。
    /// 間隔由来の残りは設定値ぶんのまま保持されるので、
    /// 部材の太さとSpacing系スライダーが独立する
    /// (=Shelf/Divider ThicknessをSpacing系から切り離す機構。
    ///  ピッチはinset分だけ広がりウィンドウも大きくなるが、
    ///  レコード同士の見た目の隙間=残りは設定値のまま)。
    /// dividerOffset/shelfOffsetは (実効間隔−前面)/2 なので、
    /// このプラグインがinsetを要求する限り実効上は設定間隔の
    /// 半分(=colSet/2・rowSet/2)になる。外枠は外周余白側の
    /// shelfPaddingInsetで要求済みなのでここでは要求しない
    func shelfSpacingInset(
        values: [String: PluginParameterValue]
    ) -> (column: CGFloat, row: CGFloat) {
        (
            column: max(0, CGFloat(values[Param.dividerThickness]?.number
                ?? Self.defaultDividerThickness)),
            row: max(0, CGFloat(values[Param.shelfThickness]?.number
                ?? Self.defaultShelfThickness))
        )
    }

    // MARK: - 描画パーツ

    /// スロット(c, r)の矩形(padding適用済みフレーム座標)。
    /// ジャケットが表示される領域で、キュービー開口(aperture)は
    /// これを各辺の残り分だけ外側へ広げたもの(apertureRect参照)
    private func slotRect(
        column c: Int, row r: Int, context: ShelfStructureContext
    ) -> CGRect {
        CGRect(
            x: context.edgePadding
                + CGFloat(c) * (context.cellSize + context.columnSpacing),
            y: context.topPadding
                + CGFloat(r) * (context.cellSize + context.rowSpacing),
            width: context.cellSize, height: context.cellSize)
    }

    /// スロット(c, r)のキュービー開口(aperture)の矩形。
    /// セルrectを各辺の残り(配置領域−前面)分だけ外側へ広げる:
    /// 内部境界は間隔の残りの半分ずつ、外側境界はpaddingの残り
    /// 全部。残りは負にならないので開口がセルより小さくなることは
    /// ない(=部材がジャケットを覆わない)。開口の外縁は隣接部材の
    /// 内縁と一致し、太さ0では両開口が配置領域の中央で接する
    private func apertureRect(
        column c: Int, row r: Int, context: ShelfStructureContext,
        members: MemberLayout
    ) -> CGRect {
        let cell = slotRect(column: c, row: r, context: context)
        let leading = c == 0 ? members.sideLeftover : members.dividerOffset
        let trailing = c == context.gridColumns - 1
            ? members.sideLeftover : members.dividerOffset
        let top = r == 0 ? members.topLeftover : members.shelfOffset
        let bottom = r == context.gridRows - 1
            ? members.bottomLeftover : members.shelfOffset
        return CGRect(
            x: cell.minX - leading,
            y: cell.minY - top,
            width: cell.width + leading + trailing,
            height: cell.height + top + bottom)
    }

    /// 実効寸法一式。部材前面は配置領域(縦仕切り=実効
    /// columnSpacing、横棚板=実効rowSpacing、外枠=各辺の
    /// padding)にクランプした実効幅で、その中へ所定位置
    /// (間隔=中央、外枠=窓端寄せ)へ配置する。
    /// 配置領域−前面=残り(leftover)は開口へ組み込まれる量
    /// (apertureRectが各辺へ加える幅)をまとめたもの。
    /// 設定値−配置領域の超過分(excess)は表示しない。
    /// 間隔はeffectiveSpacing(設定値+このプラグインの
    /// shelfSpacingInset要求=設定値+divider/shelfRaw)、paddingは
    /// effectivePadding(導出値+このプラグインのshelfPaddingInset
    /// 要求=導出値+frameRaw)が渡ってくるので、内部部材と外枠の
    /// 実効幅は通常設定値そのものになり、残りには設定間隔・
    /// 導出値の余白がそのまま残る
    private struct MemberLayout {
        /// 外枠の設定値(生値。ログ表示用)
        let frameRaw: CGFloat
        /// 縦仕切りの設定値(生値。ログ表示用)
        let dividerRaw: CGFloat
        /// 横棚板の設定値(生値。ログ表示用)
        let shelfRaw: CGFloat
        /// 縦仕切りの実効前面幅 = min(設定値, 実効columnSpacing)。
        /// columnSpacingはeffectiveSpacingの実効値(設定値+
        /// このプラグインのspacing inset=設定値+divider設定値)
        /// なので通常は設定値そのものになる
        let dividerFace: CGFloat
        /// 横棚板の実効前面幅 = min(設定値, 実効rowSpacing)。
        /// rowSpacingも同じく実効値なので通常は設定値そのもの
        let shelfFace: CGFloat
        /// 左右側板の実効前面幅 = min(設定値, edgePadding)。
        /// edgePaddingはeffectivePadding(導出値+inset要求)で
        /// inset=frameThicknessなので通常は設定値そのもの
        let sideFace: CGFloat
        /// 天板の実効前面幅 = min(設定値, topPadding)。
        /// topPaddingも同じくeffectivePaddingなので通常は設定値そのもの
        let topFace: CGFloat
        /// 底板の実効前面幅 = min(設定値, bottomPadding)。
        /// bottomPaddingも同じくeffectivePaddingなので通常は設定値そのもの
        let bottomFace: CGFloat
        /// 台輪の高さ = min(bottomPadding×plinthRatio,
        /// bottomPadding−bottomFace)。底板の下(窓端)に置く張り出し
        /// ベースで、枠が太いと潰れる(bottomFace=bottomPaddingなら0)
        let plinthH: CGFloat
        /// 縦仕切り前面の実効列間隔内オフセット(中央配置) =
        /// (実効columnSpacing−dividerFace)/2。左右それぞれの開口へ
        /// 組み込まれる残りでもある。spacing insetにより通常は
        /// 設定columnSpacing/2になる(部材が太くなっても残りが
        /// 減らない=残りは設定間隔由来で一定)
        let dividerOffset: CGFloat
        /// 横棚板前面の実効行間隔内オフセット(中央配置) =
        /// (実効rowSpacing−shelfFace)/2。上下それぞれの開口へ
        /// 組み込まれる残りでもある。同様に通常は設定
        /// rowSpacing/2になる
        let shelfOffset: CGFloat
        /// 側板の内側〜端スロット開口へ組み込まれる残り =
        /// edgePadding−sideFace
        let sideLeftover: CGFloat
        /// 天板の下〜最上段開口へ組み込まれる残り =
        /// topPadding−topFace
        let topLeftover: CGFloat
        /// 底板の上〜最下段開口へ組み込まれる残り =
        /// bottomPadding−plinthH−bottomFace
        let bottomLeftover: CGFloat
    }

    /// (a) 開口(aperture)の内壁リング。開口の内縁に沿って幅
    /// revealの内壁を描き、ジャケットが内壁の奥へ納まる見え方に
    /// する(revealがその辺の残りleftoverを超える分だけジャケット
    /// 端を覆う従来挙動。残り≥revealならリングはジャケットに
    /// 届かない)。
    /// 内壁の下地も同じ木材(端組織は暗く見える)にし、方向別に
    /// シェーディングを掛ける: 天井面(上)は最も暗く、側壁(左右)は
    /// 中間の暗さで手前→奥へ落ちるグラデ、床面(下)は手前が
    /// わずかに明るい(床面が光を拾う)
    private func paintInnerWalls(
        _ texture: WoodTexture, in gc: GraphicsContext,
        rect: CGRect, reveal: CGFloat, seed: Double
    ) {
        guard reveal > 0, rect.width > 0, rect.height > 0 else { return }
        // 帯幅は開口の寸法にクランプする(revealが開口を超えて
        // 帯同士が潰れないように。開口が極小なら帯は開口いっぱいに
        // 留まる)
        let vBand = min(reveal, rect.height)
        let hBand = min(reveal, rect.width)
        let top = CGRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: vBand)
        let bottom = CGRect(
            x: rect.minX, y: rect.maxY - vBand,
            width: rect.width, height: vBand)
        let leading = CGRect(
            x: rect.minX, y: rect.minY,
            width: hBand, height: rect.height)
        let trailing = CGRect(
            x: rect.maxX - hBand, y: rect.minY,
            width: hBand, height: rect.height)
        // 天井面: 手前(開口縁)→奥で暗くなる
        texture.paint(
            context: gc, path: Path(top), rect: top, seed: seed * 4)
        gc.fill(
            Path(top),
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(Self.wallTopOuter),
                    .black.opacity(Self.wallTopInner),
                ]),
                startPoint: CGPoint(x: 0, y: top.minY),
                endPoint: CGPoint(x: 0, y: top.maxY)))
        // 床面: 奥→手前で明るくなる(床面が光を拾う)
        texture.paint(
            context: gc, path: Path(bottom), rect: bottom, seed: seed * 4 + 1)
        gc.fill(
            Path(bottom),
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(Self.wallBottomInner),
                    .black.opacity(Self.wallBottomOuter),
                ]),
                startPoint: CGPoint(x: 0, y: bottom.minY),
                endPoint: CGPoint(x: 0, y: bottom.maxY)))
        // 側壁: 中間の暗さで手前→奥へ落ちる(奥行きのグラデ)
        paintVerticalGrain(
            texture, in: gc, rect: leading, seed: seed * 4 + 2)
        gc.fill(
            Path(leading),
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(Self.wallSideOuter),
                    .black.opacity(Self.wallSideInner),
                ]),
                startPoint: CGPoint(x: leading.minX, y: 0),
                endPoint: CGPoint(x: leading.maxX, y: 0)))
        paintVerticalGrain(
            texture, in: gc, rect: trailing, seed: seed * 4 + 3)
        // trailing側壁: 開口縁(rect.maxX=手前)がouterで、奥
        // (rect.maxX−hBand)へ行くほどinnerへ暗くなる。
        // leading/天井/床と同じ「手前=明→奥=暗」の向きに揃える
        gc.fill(
            Path(trailing),
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(Self.wallSideOuter),
                    .black.opacity(Self.wallSideInner),
                ]),
                startPoint: CGPoint(x: trailing.maxX, y: 0),
                endPoint: CGPoint(x: trailing.minX, y: 0)))
    }

    /// (b) 開口(aperture)の内側稜: 内壁リングの内側(背板/LPとの
    /// 境界)の隙間を示す細帯と、開口内へ落ちる柔らかい陰影(AO)。
    /// 上辺が最も強く数ptでフェードアウトする(天井面からの落ち影)。
    /// 内壁幅0でも描く(開口の前縁の陰としてジャケット端に掛かる)。
    /// rectには開口(aperture rect)を渡す
    private func paintApertureAO(
        _ gc: GraphicsContext, rect: CGRect, reveal: CGFloat
    ) {
        let inner = rect.insetBy(dx: reveal, dy: reveal)
        guard inner.width > 0, inner.height > 0 else { return }
        // 隙間の細帯: 内壁と中身の境界の暗い切れ目
        gc.stroke(
            Path(inner),
            with: .color(.black.opacity(Self.gapLineOpacity)),
            lineWidth: Self.gapLineWidth)
        // AO: 上辺が最強
        let topH = min(Self.aoTopDepth, inner.height * 0.3)
        if topH > 0 {
            let band = CGRect(
                x: inner.minX, y: inner.minY,
                width: inner.width, height: topH)
            gc.fill(
                Path(band),
                with: .linearGradient(
                    Gradient(colors: [
                        .black.opacity(Self.aoTopOpacity), .clear,
                    ]),
                    startPoint: CGPoint(x: 0, y: band.minY),
                    endPoint: CGPoint(x: 0, y: band.maxY)))
        }
        let sideW = min(Self.aoSideDepth, inner.width * 0.2)
        if sideW > 0 {
            let leading = CGRect(
                x: inner.minX, y: inner.minY,
                width: sideW, height: inner.height)
            gc.fill(
                Path(leading),
                with: .linearGradient(
                    Gradient(colors: [
                        .black.opacity(Self.aoSideOpacity), .clear,
                    ]),
                    startPoint: CGPoint(x: leading.minX, y: 0),
                    endPoint: CGPoint(x: leading.maxX, y: 0)))
            let trailing = CGRect(
                x: inner.maxX - sideW, y: inner.minY,
                width: sideW, height: inner.height)
            gc.fill(
                Path(trailing),
                with: .linearGradient(
                    Gradient(colors: [
                        .black.opacity(Self.aoSideOpacity), .clear,
                    ]),
                    startPoint: CGPoint(x: trailing.maxX, y: 0),
                    endPoint: CGPoint(x: trailing.minX, y: 0)))
        }
        let bottomH = min(Self.aoBottomDepth, inner.height * 0.15)
        if bottomH > 0 {
            let band = CGRect(
                x: inner.minX, y: inner.maxY - bottomH,
                width: inner.width, height: bottomH)
            gc.fill(
                Path(band),
                with: .linearGradient(
                    Gradient(colors: [
                        .black.opacity(Self.aoBottomOpacity), .clear,
                    ]),
                    startPoint: CGPoint(x: 0, y: band.maxY),
                    endPoint: CGPoint(x: 0, y: band.minY)))
        }
    }

    /// 部材前面の開口側の稜がどちら側かを示す辺
    private enum OpeningEdge {
        case top, bottom, leading, trailing
    }

    /// (c)(d)(e)の部材前面: 木目(verticalなら縦目)を描き、
    /// 開口側の稜に1ptの薄いハイライト+数ptの陰影グラデを入れる。
    /// 幅/高さが0以下なら何も描かない(間隔0でも破綻しない)
    private func paintMember(
        _ texture: WoodTexture, in gc: GraphicsContext,
        rect: CGRect, vertical: Bool, seed: Double,
        openingEdges: [OpeningEdge]
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        if vertical {
            paintVerticalGrain(texture, in: gc, rect: rect, seed: seed)
        } else {
            texture.paint(
                context: gc, path: Path(rect), rect: rect, seed: seed)
        }
        shadeOpeningEdges(gc, rect: rect, edges: openingEdges)
    }

    /// 部材前面の開口側の稜へ陰影を入れる: 稜線1ptの薄い
    /// ハイライト(角が光を拾う表現)+部材内側へフェードする
    /// 陰影グラデ(面が開口へ向かって僅かに落ちる見え方)
    private func shadeOpeningEdges(
        _ gc: GraphicsContext, rect: CGRect, edges: [OpeningEdge]
    ) {
        let light = Self.edgeHighlight.opacity(Self.edgeHighlightOpacity)
        let shade = Color.black.opacity(Self.edgeShadeOpacity)
        for edge in edges {
            switch edge {
            case .top:
                gc.fill(
                    Path(CGRect(
                        x: rect.minX, y: rect.minY,
                        width: rect.width, height: 1)),
                    with: .color(light))
                let h = min(Self.edgeShadeDepth, max(0, rect.height - 1))
                if h > 0 {
                    let band = CGRect(
                        x: rect.minX, y: rect.minY + 1,
                        width: rect.width, height: h)
                    gc.fill(
                        Path(band),
                        with: .linearGradient(
                            Gradient(colors: [shade, .clear]),
                            startPoint: CGPoint(x: 0, y: band.minY),
                            endPoint: CGPoint(x: 0, y: band.maxY)))
                }
            case .bottom:
                gc.fill(
                    Path(CGRect(
                        x: rect.minX, y: rect.maxY - 1,
                        width: rect.width, height: 1)),
                    with: .color(light))
                let h = min(Self.edgeShadeDepth, max(0, rect.height - 1))
                if h > 0 {
                    let band = CGRect(
                        x: rect.minX, y: rect.maxY - 1 - h,
                        width: rect.width, height: h)
                    gc.fill(
                        Path(band),
                        with: .linearGradient(
                            Gradient(colors: [shade, .clear]),
                            startPoint: CGPoint(x: 0, y: band.maxY),
                            endPoint: CGPoint(x: 0, y: band.minY)))
                }
            case .leading:
                gc.fill(
                    Path(CGRect(
                        x: rect.minX, y: rect.minY,
                        width: 1, height: rect.height)),
                    with: .color(light))
                let w = min(Self.edgeShadeDepth, max(0, rect.width - 1))
                if w > 0 {
                    let band = CGRect(
                        x: rect.minX + 1, y: rect.minY,
                        width: w, height: rect.height)
                    gc.fill(
                        Path(band),
                        with: .linearGradient(
                            Gradient(colors: [shade, .clear]),
                            startPoint: CGPoint(x: band.minX, y: 0),
                            endPoint: CGPoint(x: band.maxX, y: 0)))
                }
            case .trailing:
                gc.fill(
                    Path(CGRect(
                        x: rect.maxX - 1, y: rect.minY,
                        width: 1, height: rect.height)),
                    with: .color(light))
                let w = min(Self.edgeShadeDepth, max(0, rect.width - 1))
                if w > 0 {
                    let band = CGRect(
                        x: rect.maxX - 1 - w, y: rect.minY,
                        width: w, height: rect.height)
                    gc.fill(
                        Path(band),
                        with: .linearGradient(
                            Gradient(colors: [shade, .clear]),
                            startPoint: CGPoint(x: band.maxX, y: 0),
                            endPoint: CGPoint(x: band.minX, y: 0)))
                }
            }
        }
    }

    /// 縦部材(縦仕切り・側板・開口の側壁)用に木目を
    /// 90°回転して描く。テクスチャは横目で登録されているので、
    /// rect中心にGraphicsContextを90°回し、縦横を入れ替えたrectで
    /// 貼ると画面座標では縦目になる(クリップも回転後の座標系で
    /// 掛ける)
    private func paintVerticalGrain(
        _ texture: WoodTexture, in gc: GraphicsContext,
        rect: CGRect, seed: Double
    ) {
        var g = gc
        g.translateBy(x: rect.midX, y: rect.midY)
        g.rotate(by: .degrees(90))
        g.translateBy(x: -rect.midX, y: -rect.midY)
        let rotated = CGRect(
            x: rect.midX - rect.height / 2,
            y: rect.midY - rect.width / 2,
            width: rect.height, height: rect.width)
        texture.paint(context: g, path: Path(rotated), rect: rotated, seed: seed)
    }

    // MARK: - パラメータ解決

    private func resolvedWood(context: ShelfStructureContext) -> WoodMaterial {
        let raw = context.text(Param.wood, default: Self.defaultWood.rawValue)
        return WoodMaterial(rawValue: raw) ?? Self.defaultWood
    }

    /// 内壁の実効幅(固定値)。開口に収まる範囲へクランプする
    /// (cellSize/6まで。それ以上だと開口が潰れて見える)
    private func resolvedReveal(context: ShelfStructureContext) -> CGFloat {
        max(0, min(Self.innerWallWidth, context.cellSize / 6))
    }

    /// 部材の実効寸法一式。前面幅は配置領域(間隔/padding)へ
    /// クランプし、配置オフセットと開口へ組み込まれる残り
    /// (leftover)を導く。間隔/余白・設定太さが0や負でも負rectや
    /// ゼロ除算を出さない(すべて下限0にクランプ)。設定値が配置
    /// 領域を超えた分は捨てる(表示しない)。
    /// contextのcolumnSpacing/rowSpacingはeffectiveSpacing
    /// (設定値+このプラグインのshelfSpacingInset要求=設定値+
    /// divider/shelf設定値)なので、縦仕切り/横棚板の前面は
    /// 通常設定太さそのものになり、オフセット(残り)は設定間隔の
    /// 半分で一定になる。contextのpaddingはeffectivePadding
    /// (導出値+このプラグインのshelfPaddingInset要求)なので、
    /// 外枠は専有帯に設定太さどおり描け、残りには導出値の
    /// 余白が残る
    private func resolvedMembers(
        context: ShelfStructureContext
    ) -> MemberLayout {
        let frameRaw = max(0, CGFloat(context.number(
            Param.frameThickness, default: Self.defaultFrameThickness)))
        let dividerRaw = max(0, CGFloat(context.number(
            Param.dividerThickness, default: Self.defaultDividerThickness)))
        let shelfRaw = max(0, CGFloat(context.number(
            Param.shelfThickness, default: Self.defaultShelfThickness)))
        let colGap = max(0, context.columnSpacing)
        let rowGap = max(0, context.rowSpacing)
        let edgePad = max(0, context.edgePadding)
        let topPad = max(0, context.topPadding)
        let bottomPad = max(0, context.bottomPadding)

        // 実効前面幅: 配置領域にクランプ(それより大きくしない =
        // レコードを覆わない)
        let dividerFace = min(dividerRaw, colGap)
        let shelfFace = min(shelfRaw, rowGap)
        let sideFace = min(frameRaw, edgePad)
        let topFace = min(frameRaw, topPad)
        let bottomFace = min(frameRaw, bottomPad)
        // 台輪: bottomPaddingの3.5割と底板(クランプ後)の上の残りの
        // 小さい方(窓下端より外には出られないので、底板がpadding
        // いっぱいなら潰れて0になる)
        let plinthH = max(0, min(
            bottomPad * Self.plinthRatio,
            bottomPad - bottomFace))
        return MemberLayout(
            frameRaw: frameRaw,
            dividerRaw: dividerRaw,
            shelfRaw: shelfRaw,
            dividerFace: dividerFace,
            shelfFace: shelfFace,
            sideFace: sideFace,
            topFace: topFace,
            bottomFace: bottomFace,
            plinthH: plinthH,
            dividerOffset: (colGap - dividerFace) / 2,
            shelfOffset: (rowGap - shelfFace) / 2,
            sideLeftover: edgePad - sideFace,
            topLeftover: topPad - topFace,
            bottomLeftover: bottomPad - plinthH - bottomFace)
    }

    /// テクスチャアセットの読み込み失敗をプロセス内で1回だけ記録する
    /// (解決は描画のたびに走るので毎回ログは出さない)
    private static var didLogMissingTexture = false
    private func logMissingTextureOnce(material: WoodMaterial) {
        guard !Self.didLogMissingTexture else { return }
        Self.didLogMissingTexture = true
        Self.logger.error("rack-shelf: wood texture missing asset=\(material.assetName, privacy: .public) (fallback: gradient)")
    }

    /// プロセス内で最初の1回だけ解決値を記録する
    /// (描画のたびに呼ばれるので、毎回ログは出さない。
    ///  有効/無効とパラメータ確定のログはSettingsView側が出す)
    private static var didLogApplied = false
    private func logAppliedOnce(
        wood: WoodMaterial, reveal: CGFloat, members: MemberLayout,
        columns: Int, rows: Int
    ) {
        guard !Self.didLogApplied else { return }
        Self.didLogApplied = true
        Self.logger.notice("rack-shelf applied: wood=\(wood.rawValue, privacy: .public) frame=\(members.frameRaw, privacy: .public)->face:\(members.sideFace, privacy: .public)/\(members.topFace, privacy: .public)/\(members.bottomFace, privacy: .public) leftover:\(members.sideLeftover, privacy: .public)/\(members.topLeftover, privacy: .public)/\(members.bottomLeftover, privacy: .public) plinth:\(members.plinthH, privacy: .public) divider=\(members.dividerRaw, privacy: .public)->face:\(members.dividerFace, privacy: .public) leftover:\(members.dividerOffset, privacy: .public) shelf=\(members.shelfRaw, privacy: .public)->face:\(members.shelfFace, privacy: .public) leftover:\(members.shelfOffset, privacy: .public) reveal=\(reveal, privacy: .public) columns=\(columns, privacy: .public) rows=\(rows, privacy: .public)")
    }
}
