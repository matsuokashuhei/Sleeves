//
//  ShelfShareView.swift
//  Sleeves
//
//  右上ツールバーの共有ボタン用: 現在のシェルフの見た目を
//  オフスクリーンで再現するスナップショットビュー。
//  ImageRendererでNSImage化してNSSharingServicePickerへ渡す
//  (レンダリングとピッカー表示はShelfView.shareShelf)。
//
//  ShelfViewのshelfGridと同じレイアウト計算・同じ合成を行うが、
//   - ScrollViewの画面サイズクランプはしない(自然サイズ=
//     全スロットが収まる大きさでレンダリングする)
//   - ツールバーカプセル・信号ボタン・ホバー再生ボタン・
//     ドロップゾーン・ウィンドウドラッグ帯・外部ドロップ
//     オーバーレイは含めない
//  セルはAlbumSlotViewと同じ合成順(clipShape→jacketPlugins→
//  shadow→cellPlugins)だが、ホバー/タップ/.task/PlaybackMonitorを
//  持つAlbumSlotViewは再利用できないため、静的な専用セル
//  (ShareSlotView)を使う。
//
//  アートワークはImageRendererがビュー内の非同期ロード(.task)を
//  待たないため、呼び出し側がレンダリング前に全件awaitして
//  entry.id→NSImageの辞書で渡す。
//

import SwiftUI
import AppKit

/// シェルフのスナップショット。storeから切り離した値だけを受け取る
/// (@ObservedObjectを持たない = オフスクリーン1回描画なので
///  変更監視は要らない)
struct ShelfShareView: View {

    /// 共有アイテムに画像と一緒に添えるアプリのURL。
    /// TODO: App Store公開後に製品ページURLへ差し替える仮置き
    static let appURL = URL(string: "https://cacheandbuffer.com")!

    /// 表示中シェルフの設定(グリッド幾何とプラグインのソース)。
    /// 表示時点のstore.settingsをそのまま渡す
    let settings: ShelfSettings
    /// 表示中スロット。store.paddedSlots()の結果をそのまま渡す
    /// (slotIndex >= capacityの非表示エントリは含まれない)。
    /// 空きスロットはnil=スペースだけ確保して何も描かない
    let slots: [MediaEntry?]
    /// entry.id → ジャケット画像(レンダリング前に全件await済み)
    let artworks: [String: NSImage]

    var body: some View {
        // グリッドの間隔・余白はshelfGridと同じくsettingsから計算する
        // (間隔はeffectiveSpacing=設定値+プラグインのspacing inset、
        //  余白はeffectivePadding=導出値+プラグインのpadding inset)。
        // 違いはScrollViewクランプをしないことだけ —
        // 画像は自然サイズ(全スロット収まる大きさ)で作る
        let cell = settings.artworkSize.points
        let columnCount = settings.columns
        let rowCount = settings.rows
        // 間隔はshelfGridと同じeffectiveSpacingを使う。生の設定値だと
        // spacing insetを要求した構造プラグインの部材とレコード位置が
        // スナップショット上でずれる
        let spacing = ShelfPluginRegistry.effectiveSpacing(settings: settings)
        let columnSpacing = spacing.column
        let rowSpacing = spacing.row
        // 余白はshelfGridと同じeffectivePaddingを使う。生の導出値だと
        // 構造プラグインの部材とレコード位置がスナップショット上でずれる
        let padding = ShelfPluginRegistry.effectivePadding(settings: settings)
        let edgePadding = padding.edge
        let topPadding = padding.top
        let bottomPadding = padding.bottom
        let columns = Array(
            repeating: GridItem(.fixed(cell), spacing: columnSpacing),
            count: columnCount
        )
        let width = CGFloat(columnCount) * cell
            + CGFloat(columnCount - 1) * columnSpacing
            + edgePadding * 2
        let height = CGFloat(rowCount) * cell
            + CGFloat(rowCount - 1) * rowSpacing
            + topPadding + bottomPadding

        // 棚レベルプラグイン(壁・棚板・前柵)の解決もshelfGridと同じ。
        // 合成は下のpadding適用済みグリッドの .background/.overlay で行う
        let resolvedShelf = ShelfPluginRegistry.resolveShelf(
            settings: settings,
            cellSize: cell,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing,
            edgePadding: edgePadding,
            topPadding: topPadding,
            bottomPadding: bottomPadding
        )
        // スロットごとのコンテンツオフセットもshelfGridと同じ。
        // 構造プラグインがレコードをずらす場合(Record Rackの
        // 開口中央/床上配置)、スナップショットも同じ見た目の
        // 位置に描く
        let slotOffsets = (0..<slots.count).map {
            ShelfPluginRegistry.slotContentOffset(
                slot: $0, resolved: resolvedShelf)
        }

        LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(slots.indices, id: \.self) { index in
                Group {
                    if let entry = slots[index] {
                        ShareSlotView(
                            entry: entry,
                            slotIndex: index,
                            settings: settings,
                            image: artworks[entry.id]
                        )
                    } else {
                        // 空きスロットは何も描かず、スペースだけ確保する
                        Color.clear
                    }
                }
                .frame(width: cell, height: cell)
                .offset(slotOffsets[index])
            }
        }
        .padding(EdgeInsets(
            top: topPadding,
            leading: edgePadding,
            bottom: bottomPadding,
            trailing: edgePadding
        ))
        // 棚レベルプラグイン: 背面に壁、前面に棚板+前柵をレジストリ順に
        // 重畳する。ヒットテストはオフスクリーン描画なので意味を持たないが、
        // 合成構造をshelfGridと揃えるため同じ修飾を付ける
        .background {
            let backdrops = resolvedShelf.compactMap {
                $0.plugin.shelfBackdrop(context: $0.context)
            }
            ZStack {
                ForEach(backdrops.indices, id: \.self) { backdrops[$0] }
            }
        }
        .overlay {
            let overlays = resolvedShelf.compactMap {
                $0.plugin.shelfOverlay(context: $0.context)
            }
            ZStack {
                ForEach(overlays.indices, id: \.self) { overlays[$0] }
            }
            .allowsHitTesting(false)
        }
        // 自然サイズで固定。ImageRendererはこのフレームをそのまま
        // 画像サイズ(scale=2でRetinaのピクセル数)として描く
        .frame(width: width, height: height)
        // 窓の透明切り欠き(shelfTransparentRegions。例: Record Rackの
        // 台座両脇)はスナップショットにも同じ形で反映する
        .clipShape(WindowNotchShape(
            regions: ShelfPluginRegistry.transparentRegions(
                resolved: resolvedShelf)))
    }
}

/// スナップショット用の1セル。AlbumSlotViewと同じ合成順で描くが、
/// ホバー/タップ/PlaybackMonitor/.taskを持たない静的ビュー。
/// アートワークは呼び出し側が事前に取得したものを受け取るだけ
private struct ShareSlotView: View {

    let entry: MediaEntry
    /// グリッド内の行優先スロット位置(0始まり)。プラグインの
    /// 空間効果とジャケット角丸の決定論的疑似乱数の種に使う
    let slotIndex: Int
    let settings: ShelfSettings
    /// 事前取得済みのジャケット。無ければグレーのプレースホルダ
    let image: NSImage?

    /// AlbumSlotView.jacketと同じ構造。違いは読み込み中の
    /// ProgressViewを出さず、画像が無いときは静的な
    /// jacketShapeのグレー塗りだけを置くこと(オフスクリーン
    /// レンダリングで非同期ロードは起きない)
    private var jacket: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ShelfPluginLayout.jacketShape(cellIndex: slotIndex)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(ShelfPluginLayout.jacketShape(cellIndex: slotIndex))
    }

    var body: some View {
        // AlbumSlotViewと同じく、有効なプラグインをレジストリ順に解決する
        let plugins = ShelfPluginRegistry.resolve(
            settings: settings,
            cellSize: settings.artworkSize.points,
            cellIndex: slotIndex
        )
        jacket
            // (a) ジャケット修飾 + (b) オーバーレイ + (c) 面の変形
            .applyingJacketPlugins(plugins, cellIndex: slotIndex)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            // (d) セル単位の装飾(影・光等)
            .applyingCellPlugins(plugins)
    }
}
