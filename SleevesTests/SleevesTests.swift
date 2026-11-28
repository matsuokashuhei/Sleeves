//
//  SleevesTests.swift
//  SleevesTests
//
//  Created by Shuhei Matsuoka on 2026/10/18.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing

/// MediaURLParser(Shared/MediaEntry.swift)の純ロジックテスト。
/// MediaEntry.swift はこのターゲットに直接コンパイルされるため @testable 不要。
struct MediaURLParserTests {

    // MARK: - 素のID

    @Test func bareNumericIDIsAlbum() {
        let parsed = MediaURLParser.parse("1440842296")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
        #expect(parsed?.country == "jp")
    }

    @Test func tinyNumberIsRejected() {
        // 100_000以下はカタログIDとして扱わない
        #expect(MediaURLParser.parse("42") == nil)
    }

    @Test func nonNumericTextIsRejected() {
        #expect(MediaURLParser.parse("hello") == nil)
        #expect(MediaURLParser.parse("") == nil)
    }

    // MARK: - アルバムURL

    @Test func albumURLWithSlug() {
        let parsed = MediaURLParser.parse("https://music.apple.com/jp/album/brown-sugar/1440842296")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
        #expect(parsed?.country == "jp")
    }

    @Test func albumURLWithoutSlug() {
        let parsed = MediaURLParser.parse("https://music.apple.com/jp/album/1440842296")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
    }

    @Test func albumURLCountryCode() {
        let parsed = MediaURLParser.parse("https://music.apple.com/us/album/thriller/269572838")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "269572838")
        #expect(parsed?.country == "us")
    }

    @Test func albumURLWithoutCountry() {
        // 国コードなしパスはデフォルト jp
        let parsed = MediaURLParser.parse("https://music.apple.com/album/brown-sugar/1440842296")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
        #expect(parsed?.country == "jp")
    }

    @Test func albumURLWithTrackParam() {
        // ?i= はクエリなのでパス解析の対象外。アルバムIDが取れる
        let parsed = MediaURLParser.parse("https://music.apple.com/jp/album/brown-sugar/1440842296?i=1440842467")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
    }

    // MARK: - プレイリストURL

    @Test func playlistURL() {
        let parsed = MediaURLParser.parse("https://music.apple.com/jp/playlist/lo-fi-japan/pl.38eb70f47b834187a21cf4e8e5833f35")
        #expect(parsed?.kind == .playlist)
        #expect(parsed?.id == "pl.38eb70f47b834187a21cf4e8e5833f35")
        #expect(parsed?.country == "jp")
    }

    @Test func playlistURLWithoutSlug() {
        let parsed = MediaURLParser.parse("https://music.apple.com/us/playlist/pl.38eb70f47b834187a21cf4e8e5833f35")
        #expect(parsed?.kind == .playlist)
        #expect(parsed?.id == "pl.38eb70f47b834187a21cf4e8e5833f35")
        #expect(parsed?.country == "us")
    }

    // MARK: - music:// とスキーム省略

    @Test func musicSchemeDeepLink() {
        let parsed = MediaURLParser.parse("music://music.apple.com/jp/album/brown-sugar/1440842296")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
    }

    @Test func schemelessAppleMusicURL() {
        let parsed = MediaURLParser.parse("music.apple.com/jp/album/brown-sugar/1440842296")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
    }

    // MARK: - 拒否ケース

    @Test func nonAppleHostIsRejected() {
        #expect(MediaURLParser.parse("https://example.com/jp/album/x/1440842296") == nil)
    }

    @Test func unknownPathIsRejected() {
        #expect(MediaURLParser.parse("https://music.apple.com/jp/artist/dangelo/123456789") == nil)
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        let parsed = MediaURLParser.parse("  https://music.apple.com/jp/album/brown-sugar/1440842296\n")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "1440842296")
    }
}

/// ShelfPlacement(Shared/MediaEntry.swift)の自由配置ロジックテスト。
/// スロットは0始まりの行優先index。各エントリのslotIndexは一意
private func placementEntry(_ id: String, slot: Int) -> MediaEntry {
    MediaEntry(
        kind: .album, id: id, title: id, artist: "", country: "jp",
        url: "", artworkURL: "", addedAt: .distantPast, slotIndex: slot
    )
}

private func slotsByID(_ entries: [MediaEntry]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.slotIndex) })
}

struct ShelfPlacementTests {

    // MARK: - 正規化(読み込み時マイグレーション)

    @Test func normalizeAssignsFirstFreeSlotsInFileOrder() {
        // 旧フォーマット(全員-1): ファイル順のまま先頭から0,1,2
        let entries = [placementEntry("a", slot: -1),
                       placementEntry("b", slot: -1),
                       placementEntry("c", slot: -1)]
        let result = ShelfPlacement.normalized(entries)
        #expect(result.changed)
        #expect(result.entries.map(\.slotIndex) == [0, 1, 2])
        #expect(result.entries.map(\.id) == ["a", "b", "c"])
    }

    @Test func normalizeResolvesCollisionKeepingFileOrder() {
        // bとcが同じスロット: 先に現れたbが2を保持、cは空きの0へ。
        // 結果はslotIndex昇順に並ぶ
        let entries = [placementEntry("a", slot: 1),
                       placementEntry("b", slot: 2),
                       placementEntry("c", slot: 2)]
        let result = ShelfPlacement.normalized(entries)
        #expect(result.changed)
        #expect(slotsByID(result.entries) == ["a": 1, "b": 2, "c": 0])
        #expect(result.entries.map(\.id) == ["c", "a", "b"])
    }

    @Test func normalizeUnchangedWhenAlreadyValid() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 3)]
        let result = ShelfPlacement.normalized(entries)
        #expect(!result.changed)
        #expect(result.entries == entries)
    }

    // MARK: - paddedSlots

    @Test func paddedSlotsHonorsSlotIndexWithGaps() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 3)]
        let slots = ShelfPlacement.paddedSlots(entries, capacity: 5)
        #expect(slots.map(\.?.id) == ["a", nil, nil, "b", nil])
    }

    @Test func paddedSlotsHidesOutOfRangeEntries() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("hidden", slot: 9)]
        let slots = ShelfPlacement.paddedSlots(entries, capacity: 4)
        #expect(slots.compactMap(\.?.id) == ["a"])
    }

    // MARK: - 密配置の並び替え(旧moveと同じ結果)

    @Test func denseReorderBeforeMatchesOldMove() {
        // cをaの直前へ → 順序[c,a,b]、スロットは0,1,2のまま
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1),
                       placementEntry("c", slot: 2)]
        let result = ShelfPlacement.reorder(
            entries: entries, draggedID: "c", targetSlotIndex: 0, after: false
        )
        #expect(result?.map(\.id) == ["c", "a", "b"])
        #expect(result?.map(\.slotIndex) == [0, 1, 2])
    }

    @Test func denseReorderAfterMatchesOldMove() {
        // aをcの直後へ → 順序[b,c,a]
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1),
                       placementEntry("c", slot: 2)]
        let result = ShelfPlacement.reorder(
            entries: entries, draggedID: "a", targetSlotIndex: 2, after: true
        )
        #expect(result?.map(\.id) == ["b", "c", "a"])
        #expect(result?.map(\.slotIndex) == [0, 1, 2])
    }

    // MARK: - ギャップありのスライド

    @Test func gapReorderSlidesOnlyBetweenRecords() {
        // a@0, b@3, c@5。cの直前へaをドロップ → 占有位置[0,3,5]は不変で
        // 順序が[b,a,c]に: b@0, a@3, c@5(間のレコードだけ1スロットずつスライド)
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 3),
                       placementEntry("c", slot: 5)]
        let result = ShelfPlacement.reorder(
            entries: entries, draggedID: "a", targetSlotIndex: 5, after: false
        )
        #expect(slotsByID(result ?? []) == ["a": 3, "b": 0, "c": 5])
    }

    @Test func gapReorderKeepsRecordsBeyondGap() {
        // a@0, b@3, c@5, d@8。bをaの直前へ → [b,a,c,d] →
        // b@0, a@3, c@5, d@8(c,dは動かない)
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 3),
                       placementEntry("c", slot: 5),
                       placementEntry("d", slot: 8)]
        let result = ShelfPlacement.reorder(
            entries: entries, draggedID: "b", targetSlotIndex: 0, after: false
        )
        #expect(slotsByID(result ?? []) == ["a": 3, "b": 0, "c": 5, "d": 8])
    }

    @Test func hiddenOutOfRangeEntryStaysPutDuringReorder() {
        // capacity外の非表示エントリは最大側=順序末尾なので動かない
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1),
                       placementEntry("h", slot: 9)]
        let result = ShelfPlacement.reorder(
            entries: entries, draggedID: "a", targetSlotIndex: 1, after: true
        )
        #expect(slotsByID(result ?? []) == ["a": 1, "b": 0, "h": 9])
    }

    // MARK: - 空きスロットへの配置(他は動かない)

    @Test func placeToEmptySlotMovesOnlyDragged() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 3)]
        let result = ShelfPlacement.place(
            entries: entries, draggedID: "a", atSlot: 7, capacity: 10
        )
        #expect(slotsByID(result ?? []) == ["a": 7, "b": 3])
    }

    @Test func placeToSameSlotIsNoOp() {
        let entries = [placementEntry("a", slot: 0)]
        #expect(ShelfPlacement.place(entries: entries, draggedID: "a", atSlot: 0, capacity: 10) == nil)
    }

    @Test func placeToOccupiedSlotIsRejected() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 3)]
        #expect(ShelfPlacement.place(entries: entries, draggedID: "a", atSlot: 3, capacity: 10) == nil)
    }

    // MARK: - no-op(自分自身・隣接の同順位置)

    @Test func dropOnSelfIsNoOp() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1)]
        #expect(ShelfPlacement.reorder(
            entries: entries, draggedID: "a", targetSlotIndex: 0, after: false
        ) == nil)
        #expect(ShelfPlacement.reorder(
            entries: entries, draggedID: "a", targetSlotIndex: 0, after: true
        ) == nil)
    }

    @Test func dropOnAdjacentSameOrderIsNoOp() {
        // a@0をb@1の直前へ = 元と同じ順序
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1)]
        #expect(ShelfPlacement.reorder(
            entries: entries, draggedID: "a", targetSlotIndex: 1, after: false
        ) == nil)
        // b@1をa@0の直後へ = 元と同じ順序
        #expect(ShelfPlacement.reorder(
            entries: entries, draggedID: "b", targetSlotIndex: 0, after: true
        ) == nil)
    }

    // MARK: - 挿入シフト

    @Test func insertAtEmptySlotPlacesExactly() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 2)]
        let result = ShelfPlacement.insertionShift(
            entries: entries, inserting: placementEntry("x", slot: -1), at: 1, capacity: 10
        )
        #expect(slotsByID(result ?? []) == ["a": 0, "b": 2, "x": 1])
    }

    @Test func insertShiftRightPushesOccupiedRun() {
        // a@0,b@1,c@2。s=1へ挿入 → ラン[0,2]の右に空きがあるので
        // b,cが+1へ、xは1へ
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1),
                       placementEntry("c", slot: 2)]
        let result = ShelfPlacement.insertionShift(
            entries: entries, inserting: placementEntry("x", slot: -1), at: 1, capacity: 10
        )
        #expect(slotsByID(result ?? []) == ["a": 0, "b": 2, "c": 3, "x": 1])
    }

    @Test func insertShiftLeftFallbackWhenRightBlocked() {
        // capacity4でa@1,b@2,c@3(ランの右が詰まり、左の0が空き)。
        // s=2へ挿入 → 占有[1..2]が-1へ、xは2へ、右のcは動かない
        let entries = [placementEntry("a", slot: 1),
                       placementEntry("b", slot: 2),
                       placementEntry("c", slot: 3)]
        let result = ShelfPlacement.insertionShift(
            entries: entries, inserting: placementEntry("x", slot: -1), at: 2, capacity: 4
        )
        #expect(slotsByID(result ?? []) == ["a": 0, "b": 1, "c": 3, "x": 2])
    }

    @Test func insertShiftKeepsHiddenEntries() {
        // 非表示(slotIndex>=capacity)のエントリはシフト対象外
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("h", slot: 9)]
        let result = ShelfPlacement.insertionShift(
            entries: entries, inserting: placementEntry("x", slot: -1), at: 0, capacity: 4
        )
        #expect(slotsByID(result ?? []) == ["a": 1, "h": 9, "x": 0])
    }

    @Test func insertShiftReturnsNilWhenFull() {
        // capacity2で両方占有 → 左右どちらにもずらせない
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1)]
        #expect(ShelfPlacement.insertionShift(
            entries: entries, inserting: placementEntry("x", slot: -1), at: 0, capacity: 2
        ) == nil)
    }

    // MARK: - 最近傍空きスロット

    @Test func nearestEmptySlotResolvesByDistance() {
        // 2列グリッド(cell=10, gap=0): 0,1が上段、2,3が下段。
        // a@0のみ占有。スロット0の中心へのドロップ → 最近傍の空きは1
        let entries = [placementEntry("a", slot: 0)]
        let found = ShelfPlacement.nearestEmptySlot(
            entries: entries, capacity: 4, columns: 2,
            cell: 10, columnSpacing: 0, rowSpacing: 0,
            at: CGPoint(x: 5, y: 5)
        )
        #expect(found == 1)
        // スロット3の中心(15,15)付近 → 3
        let far = ShelfPlacement.nearestEmptySlot(
            entries: entries, capacity: 4, columns: 2,
            cell: 10, columnSpacing: 0, rowSpacing: 0,
            at: CGPoint(x: 14, y: 16)
        )
        #expect(far == 3)
    }

    @Test func nearestEmptySlotReturnsNilWhenFull() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1)]
        #expect(ShelfPlacement.nearestEmptySlot(
            entries: entries, capacity: 2, columns: 2,
            cell: 10, columnSpacing: 0, rowSpacing: 0,
            at: CGPoint(x: 5, y: 5)
        ) == nil)
    }

    @Test func nearestEmptySlotUsesVisualCenterWhenOffset() {
        // slotOffsetを渡すと距離判定はピッチ中心ではなく
        // 見た目の中心(ピッチ+オフセット)で行われる。
        // 2列1行(cell=10, gap=0、全空き): ピッチ中心は
        // スロット0=(5,5)、スロット1=(15,5)。点(8,5)は
        // オフセット無しならスロット0が最近傍(d=3<7)だが、
        // スロット0へ+6・スロット1へ−7のオフセットを掛けると
        // 見た目中心は(11,5)/(8,5)になりスロット1へ変わる
        #expect(ShelfPlacement.nearestEmptySlot(
            entries: [], capacity: 2, columns: 2,
            cell: 10, columnSpacing: 0, rowSpacing: 0,
            at: CGPoint(x: 8, y: 5)
        ) == 0)
        #expect(ShelfPlacement.nearestEmptySlot(
            entries: [], capacity: 2, columns: 2,
            cell: 10, columnSpacing: 0, rowSpacing: 0,
            at: CGPoint(x: 8, y: 5)
        ) { i in
            CGSize(width: i == 0 ? 6 : -7, height: 0)
        } == 1)
    }

    // MARK: - firstEmptySlot(満杯判定)

    @Test func firstEmptySlotFindsHeadGap() {
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("b", slot: 3)]
        #expect(ShelfPlacement.firstEmptySlot(entries: entries, capacity: 4) == 1)
    }

    @Test func firstEmptySlotIgnoresHiddenEntries() {
        // slotIndex >= capacity の非表示エントリは占有として数えない:
        // count >= capacity でも空きがあれば満杯ではない
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("h", slot: 9)]
        #expect(ShelfPlacement.firstEmptySlot(entries: entries, capacity: 4) == 1)
    }

    @Test func firstEmptySlotBoundaryCapacities() {
        let full = [placementEntry("a", slot: 0),
                    placementEntry("b", slot: 1)]
        #expect(ShelfPlacement.firstEmptySlot(entries: full, capacity: 2) == nil)
        // capacity=0 は常に空きなし、capacity=1 の空シェルフはスロット0
        #expect(ShelfPlacement.firstEmptySlot(entries: [], capacity: 0) == nil)
        #expect(ShelfPlacement.firstEmptySlot(entries: [], capacity: 1) == 0)
        #expect(ShelfPlacement.firstEmptySlot(entries: [placementEntry("a", slot: 0)], capacity: 1) == nil)
    }

    // MARK: - capacity=0/1 の境界

    @Test func capacityZeroRejectsEverything() {
        let entries = [placementEntry("a", slot: 0)]
        #expect(ShelfPlacement.paddedSlots(entries, capacity: 0).isEmpty)
        #expect(ShelfPlacement.firstEmptySlot(entries: [], capacity: 0) == nil)
        #expect(ShelfPlacement.nearestEmptySlot(
            entries: [], capacity: 0, columns: 1,
            cell: 10, columnSpacing: 0, rowSpacing: 0, at: CGPoint(x: 0, y: 0)) == nil)
        #expect(ShelfPlacement.insertionShift(
            entries: [], inserting: placementEntry("x", slot: -1), at: 0, capacity: 0) == nil)
        #expect(ShelfPlacement.place(
            entries: entries, draggedID: "a", atSlot: 0, capacity: 0) == nil)
    }

    @Test func capacityOneInsertShift() {
        // capacity=1: 空なら置ける、占有ならどちらにもずらせない
        #expect(ShelfPlacement.insertionShift(
            entries: [], inserting: placementEntry("x", slot: -1), at: 0, capacity: 1
        )?.map(\.slotIndex) == [0])
        let occupied = [placementEntry("a", slot: 0)]
        #expect(ShelfPlacement.insertionShift(
            entries: occupied, inserting: placementEntry("x", slot: -1), at: 0, capacity: 1
        ) == nil)
    }

    // MARK: - normalized の混在ケース

    @Test func normalizeMixedUnsetAndValidSlots() {
        // -1と有効slotIndexの混在: 有効なbは2を保持、aは空きの先頭0へ
        let entries = [placementEntry("a", slot: -1),
                       placementEntry("b", slot: 2)]
        let result = ShelfPlacement.normalized(entries)
        #expect(result.changed)
        #expect(slotsByID(result.entries) == ["a": 0, "b": 2])
    }

    @Test func normalizePreservesOutOfCapacitySlots() {
        // slotIndex >= capacity(グリッド縮小で非表示になったエントリ)は
        // 正規化で再配置しない。値が有効かつ一意ならそのまま保持する
        let entries = [placementEntry("a", slot: 0),
                       placementEntry("h", slot: 9)]
        let result = ShelfPlacement.normalized(entries)
        #expect(!result.changed)
        #expect(slotsByID(result.entries) == ["a": 0, "h": 9])
    }

    // MARK: - slotIndex=-1混入(防御)

    @Test func reorderWithUnplacedEntryKeepsItsSlot() {
        // 未配置(-1)が混ざっていても占有位置集合は[-1,0,1]のまま動く:
        // a@0をb@1の直後へ → 順序[x,b,a] → x@-1,b@0,a@1
        let entries = [placementEntry("x", slot: -1),
                       placementEntry("a", slot: 0),
                       placementEntry("b", slot: 1)]
        let result = ShelfPlacement.reorder(
            entries: entries, draggedID: "a", targetSlotIndex: 1, after: true
        )
        #expect(slotsByID(result ?? []) == ["x": -1, "a": 1, "b": 0])
    }

    @Test func placeWithUnplacedEntry() {
        let entries = [placementEntry("x", slot: -1)]
        let result = ShelfPlacement.place(
            entries: entries, draggedID: "x", atSlot: 2, capacity: 5
        )
        #expect(slotsByID(result ?? []) == ["x": 2])
    }

    // MARK: - topDragStripHeight(上辺ドラッグ帯の高さ)

    @Test func topDragStripHeightKeepsTopPaddingForZeroAndDownwardOffset() {
        // オフセット無し(デフォルト)・明示ゼロ・下方向(dy > 0)ではtopPaddingを維持
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 14, columns: 4) == 14)
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 14, columns: 4) { _ in
            CGSize(width: 5, height: 0)
        } == 14)
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 14, columns: 4) { _ in
            CGSize(width: 0, height: 6)
        } == 14)
    }

    @Test func topDragStripHeightShrinksForUpwardOffset() {
        // Record Rackでdepth > rowSpacing/2により1段目が上(dy < 0)へずれるケース:
        // ドラッグ帯は1段目レコードの見た目上端(topPadding + dy)まで縮む
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 40, columns: 5) { _ in
            CGSize(width: 0, height: -12)
        } == 28)
    }

    @Test func topDragStripHeightMatchesHighestRisingColumn() {
        // 列ごとに異なるオフセットがある場合は、最も上へせり上がった列に合わせる
        let dys: [CGFloat] = [4, -3, -9, -1]
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 20, columns: dys.count) { c in
            CGSize(width: 0, height: dys[c])
        } == 11)
    }

    @Test func topDragStripHeightBoundaries() {
        // 極端な負オフセット(topPadding + dy < 0)は0へクランプ
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 10, columns: 3) { _ in
            CGSize(width: 0, height: -15)
        } == 0)
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 10, columns: 3) { _ in
            CGSize(width: 0, height: -10)
        } == 0)
        // topPadding <= 0 は常に0
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 0, columns: 4) == 0)
        #expect(ShelfPlacement.topDragStripHeight(topPadding: -6, columns: 4) == 0)
        #expect(ShelfPlacement.topDragStripHeight(topPadding: -6, columns: 0) == 0)
        // columns <= 0 はtopPaddingを返す(slotOffsetを呼ばない)
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 14, columns: 0) { _ in
            CGSize(width: 0, height: -10)
        } == 14)
        #expect(ShelfPlacement.topDragStripHeight(topPadding: 14, columns: -2) { _ in
            CGSize(width: 0, height: -10)
        } == 14)
    }
}

/// Spotify URL/URIのパース(MediaURLParser)テスト。
/// MediaEntry.swiftはテストターゲットに直接コンパイルされる
struct SpotifyURLParserTests {

    @Test func spotifyAlbumURL() {
        let parsed = MediaURLParser.parse("https://open.spotify.com/album/4LH4d3cOWNNsVw41Gqt2kv")
        #expect(parsed?.kind == .album)
        #expect(parsed?.provider == .spotify)
        #expect(parsed?.id == "4LH4d3cOWNNsVw41Gqt2kv")
    }

    @Test func spotifyPlaylistURL() {
        let parsed = MediaURLParser.parse("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")
        #expect(parsed?.kind == .playlist)
        #expect(parsed?.provider == .spotify)
        #expect(parsed?.id == "37i9dQZF1DXcBWIGoYBM5M")
    }

    @Test func spotifyIntlPrefixedURL() {
        let parsed = MediaURLParser.parse("https://open.spotify.com/intl-ja/album/4LH4d3cOWNNsVw41Gqt2kv")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "4LH4d3cOWNNsVw41Gqt2kv")
    }

    @Test func spotifyURLWithTrackingQuery() {
        // ?si=... の共有トラッキングパラメータはパス解析の対象外
        let parsed = MediaURLParser.parse("https://open.spotify.com/album/4LH4d3cOWNNsVw41Gqt2kv?si=abc123")
        #expect(parsed?.kind == .album)
        #expect(parsed?.id == "4LH4d3cOWNNsVw41Gqt2kv")
    }

    @Test func schemelessSpotifyURL() {
        // スキーム省略もmusic.apple.comと同じくhttps://補完される
        let parsed = MediaURLParser.parse("open.spotify.com/album/4LH4d3cOWNNsVw41Gqt2kv")
        #expect(parsed?.kind == .album)
        #expect(parsed?.provider == .spotify)
        #expect(parsed?.id == "4LH4d3cOWNNsVw41Gqt2kv")
    }

    @Test func spotifyURIForms() {
        let album = MediaURLParser.parse("spotify:album:4LH4d3cOWNNsVw41Gqt2kv")
        #expect(album?.kind == .album)
        #expect(album?.provider == .spotify)
        #expect(album?.id == "4LH4d3cOWNNsVw41Gqt2kv")
        let playlist = MediaURLParser.parse("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        #expect(playlist?.kind == .playlist)
        #expect(playlist?.id == "37i9dQZF1DXcBWIGoYBM5M")
    }

    @Test func spotifyNonAlbumPlaylistTypesRejected() {
        // track/artist/episode/show等は対象外
        #expect(MediaURLParser.parse("https://open.spotify.com/track/4LH4d3cOWNNsVw41Gqt2kv") == nil)
        #expect(MediaURLParser.parse("https://open.spotify.com/artist/4LH4d3cOWNNsVw41Gqt2kv") == nil)
        #expect(MediaURLParser.parse("https://open.spotify.com/episode/4LH4d3cOWNNsVw41Gqt2kv") == nil)
        #expect(MediaURLParser.parse("spotify:track:4LH4d3cOWNNsVw41Gqt2kv") == nil)
    }

    @Test func spotifyInvalidIDRejected() {
        // 短すぎるID・非base62文字を含むIDは拒否
        #expect(MediaURLParser.parse("https://open.spotify.com/album/abc") == nil)
        #expect(MediaURLParser.parse("https://open.spotify.com/album/4LH4d3cOWNNsVw41Gqt2k-") == nil)
        #expect(MediaURLParser.parse("spotify:album:") == nil)
    }

    @Test func appleMusicURLsKeepAppleProvider() {
        // 既存経路のproviderはappleMusicのまま
        #expect(MediaURLParser.parse("https://music.apple.com/jp/album/x/1440842296")?.provider == .appleMusic)
        #expect(MediaURLParser.parse("1440842296")?.provider == .appleMusic)
    }
}

/// MediaEntry.providerの後方互換デコードテスト
struct MediaEntryProviderTests {

    private func decode(_ json: String) -> MediaEntry? {
        try? JSONDecoder().decode(MediaEntry.self, from: Data(json.utf8))
    }

    @Test func missingProviderKeyDecodesAsAppleMusic() {
        // 旧フォーマット(providerキー無し)はappleMusicに倒す
        let entry = decode(#"{"kind":"album","id":"1440842296","title":"t","artist":"a","country":"jp","url":"u","artworkURL":"","addedAt":0}"#)
        #expect(entry?.provider == .appleMusic)
        // slotIndexも同時に後方互換(未配置=-1)
        #expect(entry?.slotIndex == -1)
    }

    @Test func spotifyProviderDecodes() {
        let entry = decode(#"{"kind":"playlist","provider":"spotify","id":"37i9dQZF1DXcBWIGoYBM5M","title":"t","artist":"Spotify","country":"","url":"https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M","artworkURL":"","addedAt":0,"slotIndex":2}"#)
        #expect(entry?.provider == .spotify)
        #expect(entry?.slotIndex == 2)
    }

    @Test func unknownProviderValueDecodesAsAppleMusic() {
        // 未知のprovider値はappleMusicに倒す(slotIndexの方針と同じ)
        let entry = decode(#"{"kind":"album","provider":"deezer","id":"1","title":"t","artist":"a","country":"jp","url":"u","artworkURL":"","addedAt":0}"#)
        #expect(entry?.provider == .appleMusic)
    }

    @Test func providerRoundTrips() throws {
        var entry = placementEntry("s", slot: 0)
        entry.provider = .spotify
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MediaEntry.self, from: data)
        #expect(decoded.provider == .spotify)
        #expect(decoded == entry)
    }
}

/// SpotifyのページHTML(og:メタタグ)パース純ロジックのテスト
struct SpotifyPageParserTests {

    // MARK: - metaContent

    @Test func metaContentFindsStandardTag() {
        let html = #"<html><head><meta property="og:description" content="Pink Floyd · album · 1973 · 10 songs"/></head></html>"#
        #expect(SpotifyPageParser.metaContent(in: html, property: "og:description") == "Pink Floyd · album · 1973 · 10 songs")
    }

    @Test func metaContentFindsReversedAttributeOrder() {
        // contentがpropertyより先に来る形も拾う
        let html = #"<meta content="Playlist · Spotify · 50 items" property="og:description" data-rh="true">"#
        #expect(SpotifyPageParser.metaContent(in: html, property: "og:description") == "Playlist · Spotify · 50 items")
    }

    @Test func metaContentPicksRequestedPropertyOnly() {
        let html = """
        <meta property="og:title" content="Today's Top Hits"/>
        <meta property="og:description" content="Playlist · Spotify · 50 items"/>
        <meta property="og:image" content="https://example.com/x.jpg"/>
        """
        #expect(SpotifyPageParser.metaContent(in: html, property: "og:title") == "Today's Top Hits")
        #expect(SpotifyPageParser.metaContent(in: html, property: "og:description") == "Playlist · Spotify · 50 items")
        #expect(SpotifyPageParser.metaContent(in: html, property: "og:image") == "https://example.com/x.jpg")
    }

    @Test func metaContentDecodesEntities() {
        let html = #"<meta property="og:title" content="Tom &amp; Jerry &#8212; &quot;Show&quot;"/>"#
        #expect(SpotifyPageParser.metaContent(in: html, property: "og:title") == "Tom & Jerry — \"Show\"")
    }

    @Test func metaContentReturnsNilWhenMissing() {
        #expect(SpotifyPageParser.metaContent(in: "<html></html>", property: "og:description") == nil)
    }

    // MARK: - artist(fromOgDescription:)

    @Test func artistFromAlbumDescription() {
        // " · "(U+00B7)区切りの先頭セグメント
        #expect(SpotifyPageParser.artist(
            fromOgDescription: "Pink Floyd · album · 1973 · 10 songs", kind: .album
        ) == "Pink Floyd")
    }

    @Test func artistFromPlaylistDescription() {
        // 先頭が"Playlist"なら2番目セグメントがキュレーター
        #expect(SpotifyPageParser.artist(
            fromOgDescription: "Playlist · Spotify · 50 items · 33.6M saves", kind: .playlist
        ) == "Spotify")
    }

    @Test func artistFromNonstandardPlaylistDescription() {
        // "Playlist · ..."形式でなければ"Spotify"に倒す
        #expect(SpotifyPageParser.artist(
            fromOgDescription: "50 items · 33.6M saves", kind: .playlist
        ) == "Spotify")
        #expect(SpotifyPageParser.artist(
            fromOgDescription: "", kind: .playlist
        ) == "Spotify")
    }

    @Test func artistFromShortDescription() {
        // セグメント不足の変則: アルバムは先頭そのもの、空なら空
        #expect(SpotifyPageParser.artist(
            fromOgDescription: "Single Artist", kind: .album
        ) == "Single Artist")
        #expect(SpotifyPageParser.artist(
            fromOgDescription: "", kind: .album
        ) == "")
    }

    // MARK: - decodeHTMLEntities

    @Test func decodesNamedAndNumericEntities() {
        #expect(SpotifyPageParser.decodeHTMLEntities("&amp;") == "&")
        #expect(SpotifyPageParser.decodeHTMLEntities("&lt;&gt;") == "<>")
        #expect(SpotifyPageParser.decodeHTMLEntities("&quot;") == "\"")
        #expect(SpotifyPageParser.decodeHTMLEntities("&#39;") == "'")
        #expect(SpotifyPageParser.decodeHTMLEntities("&#x27;") == "'")
        #expect(SpotifyPageParser.decodeHTMLEntities("&apos;") == "'")
    }

    @Test func doesNotDoubleDecodeAmpersand() {
        // &amp;lt; → "&lt;"(エスケープ済みリテラル)であって"<"ではない
        #expect(SpotifyPageParser.decodeHTMLEntities("&amp;lt;") == "&lt;")
    }
}

/// AppIconImageProcessor(Shared/AppIconImageProcessor.swift)の純ロジックテスト
struct AppIconImageProcessorTests {

    private struct RGBA: Equatable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }

    /// テスト用画像を生成して PNG (または EXIF orientation 付き JPEG/TIFF/PNG) にエンコードする。
    /// draw ブロックは CGContext (左下原点, width×height) に描画する。
    private func makeImageData(
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation? = nil,
        type: String = "public.png",
        draw: (CGContext) -> Void
    ) -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(ctx)
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
        let options: [CFString: Any]? = orientation.map { [kCGImagePropertyOrientation: $0.rawValue] }
        CGImageDestinationAddImage(dest, image, options as CFDictionary?)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// PNG データをデコードし、指定ピクセル座標(左上原点 x, y)の RGBA 値を返す
    private func decodeAndSample(_ pngData: Data, x: Int, y: Int) -> (width: Int, height: Int, pixel: RGBA)? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = y * bytesPerRow + x * 4
        let pixel = RGBA(r: buffer[offset], g: buffer[offset + 1], b: buffer[offset + 2], a: buffer[offset + 3])
        return (width, height, pixel)
    }

    // MARK: - centerSquareCropRect

    @Test func centerSquareCropRectSquare() {
        #expect(AppIconImageProcessor.centerSquareCropRect(width: 200, height: 200) == CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test func centerSquareCropRectLandscape() {
        #expect(AppIconImageProcessor.centerSquareCropRect(width: 300, height: 100) == CGRect(x: 100, y: 0, width: 100, height: 100))
    }

    @Test func centerSquareCropRectPortrait() {
        #expect(AppIconImageProcessor.centerSquareCropRect(width: 100, height: 300) == CGRect(x: 0, y: 100, width: 100, height: 100))
    }

    @Test func centerSquareCropRectInvalidSizes() {
        #expect(AppIconImageProcessor.centerSquareCropRect(width: 0, height: 100) == .zero)
        #expect(AppIconImageProcessor.centerSquareCropRect(width: 100, height: 0) == .zero)
        #expect(AppIconImageProcessor.centerSquareCropRect(width: -10, height: 100) == .zero)
        #expect(AppIconImageProcessor.centerSquareCropRect(width: 100, height: -5) == .zero)
    }

    // MARK: - normalizeSquarePNG

    @Test func normalizeSquareImageProduces824PNG() {
        let input = makeImageData(width: 100, height: 100) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let png = AppIconImageProcessor.normalizeSquarePNG(from: input)
        #expect(png != nil)
        let sampled = png.flatMap { decodeAndSample($0, x: 412, y: 412) }
        #expect(sampled?.width == 824)
        #expect(sampled?.height == 824)
        #expect(sampled?.pixel == RGBA(r: 0, g: 0, b: 255, a: 255))
    }

    @Test func normalizeLandscapeCropsCenterSquare() {
        // 横長 300×100: 左赤・中央緑・右青 → 中央正方形(緑)のみ残る
        let input = makeImageData(width: 300, height: 100) { ctx in
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 200, y: 0, width: 100, height: 100))
        }
        let png = AppIconImageProcessor.normalizeSquarePNG(from: input)
        #expect(png != nil)
        let leftEdge = png.flatMap { decodeAndSample($0, x: 20, y: 412) }
        let center = png.flatMap { decodeAndSample($0, x: 412, y: 412) }
        let rightEdge = png.flatMap { decodeAndSample($0, x: 804, y: 412) }
        #expect(center?.width == 824)
        #expect(center?.height == 824)
        #expect(leftEdge?.pixel == RGBA(r: 0, g: 255, b: 0, a: 255))
        #expect(center?.pixel == RGBA(r: 0, g: 255, b: 0, a: 255))
        #expect(rightEdge?.pixel == RGBA(r: 0, g: 255, b: 0, a: 255))
    }

    @Test func normalizePortraitCropsCenterSquare() {
        // 縦長 100×300: 下赤・中央緑・上青(CGContext座標) → 中央正方形(緑)のみ残る
        let input = makeImageData(width: 100, height: 300) { ctx in
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 100, width: 100, height: 100))
            ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 200, width: 100, height: 100))
        }
        let png = AppIconImageProcessor.normalizeSquarePNG(from: input)
        #expect(png != nil)
        let topEdge = png.flatMap { decodeAndSample($0, x: 412, y: 20) }
        let center = png.flatMap { decodeAndSample($0, x: 412, y: 412) }
        let bottomEdge = png.flatMap { decodeAndSample($0, x: 412, y: 804) }
        #expect(center?.width == 824)
        #expect(center?.height == 824)
        #expect(topEdge?.pixel == RGBA(r: 0, g: 255, b: 0, a: 255))
        #expect(center?.pixel == RGBA(r: 0, g: 255, b: 0, a: 255))
        #expect(bottomEdge?.pixel == RGBA(r: 0, g: 255, b: 0, a: 255))
    }

    @Test func normalizeAppliesExifOrientation6BeforeCropping() {
        // 生ピクセルは横長 300×100、EXIF orientation=6 (90°CW → 正立時は縦長 100×300)。
        // 生の中央1/3(x: 100..<200)の上半分(y: 50..<100)を緑、下半分(y: 0..<50)を青にする。
        // 90°CW で正立させると、生の上半分が正立の右半分へ、生の下半分が正立の左半分へ写る。
        // TIFF 形式で書き出すことで EXIF orientation タグを確実に保持する。
        let input = makeImageData(width: 300, height: 100, orientation: .right, type: "public.tiff") { ctx in
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
            ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 100, y: 50, width: 100, height: 50))
            ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 50))
        }
        let png = AppIconImageProcessor.normalizeSquarePNG(from: input)
        #expect(png != nil)
        let leftHalf = png.flatMap { decodeAndSample($0, x: 200, y: 412) }
        let rightHalf = png.flatMap { decodeAndSample($0, x: 624, y: 412) }
        #expect(leftHalf?.width == 824)
        #expect(leftHalf?.height == 824)
        #expect(leftHalf?.pixel == RGBA(r: 0, g: 0, b: 255, a: 255))
        #expect(rightHalf?.pixel == RGBA(r: 0, g: 255, b: 0, a: 255))
    }

    @Test func normalizePreservesTransparency() {
        let input = makeImageData(width: 100, height: 100) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 25, y: 25, width: 50, height: 50))
        }
        let png = AppIconImageProcessor.normalizeSquarePNG(from: input)
        #expect(png != nil)
        let corner = png.flatMap { decodeAndSample($0, x: 10, y: 10) }
        let center = png.flatMap { decodeAndSample($0, x: 412, y: 412) }
        #expect(corner?.pixel.a == 0)
        #expect(center?.pixel == RGBA(r: 255, g: 0, b: 0, a: 255))
    }

    @Test func normalizeRejectsEmptyOrInvalidData() {
        #expect(AppIconImageProcessor.normalizeSquarePNG(from: Data()) == nil)
        #expect(AppIconImageProcessor.normalizeSquarePNG(from: Data("not an image".utf8)) == nil)
        let valid = makeImageData(width: 10, height: 10) { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        #expect(AppIconImageProcessor.normalizeSquarePNG(from: valid, targetSize: 0) == nil)
        #expect(AppIconImageProcessor.normalizeSquarePNG(from: valid, targetSize: -1) == nil)
    }
}
