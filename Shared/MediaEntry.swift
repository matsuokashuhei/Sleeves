import Foundation

/// シェルフに並ぶ1項目(アルバム or プレイリスト)。
struct MediaEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case album
        case playlist
    }

    /// 配信元サービス。旧フォーマット(キー無し)はApple Musicとして読む
    enum Provider: String, Codable {
        case appleMusic
        case spotify
    }

    private enum CodingKeys: String, CodingKey {
        case kind, provider, id, title, artist, country, url, artworkURL, addedAt, slotIndex
    }

    let kind: Kind
    var provider: Provider = .appleMusic
    /// アルバム: 数字列のカタログID / プレイリスト: "pl.xxx"
    /// Spotify: base62(22文字前後)のID
    let id: String
    var title: String
    /// アルバム: アーティスト名 / プレイリスト: キュレーター名
    var artist: String
    /// Apple Musicのストアフロント。Spotifyにはその概念が無いので ""
    var country: String
    /// Apple Music / SpotifyのURL
    var url: String
    var artworkURL: String
    var addedAt: Date
    /// グリッド上の配置スロット(0始まりの行優先index)。
    /// -1 = 未配置(旧フォーマットのalbums.jsonや、永続化前のfetch直後の
    /// エントリ)。読み込み時にShelfStoreが正規化して必ず0以上にする。
    /// 表示スロット数(capacity)以上の値も有効: そのレコードは登録を保持した
    /// まま非表示になり、グリッドを広げるとその位置に再び現れる
    /// (従来の「縮小しても登録は消さない」と同じセマンティクス)。
    /// なおindexは「行優先の通し番号」なので、列数(columns)を変えると
    /// 同じslotIndexが別のグリッド位置へ再解釈される=配置がリフローする。
    /// 行数(rows)の変更はcapacityの増減で、スロット位置は維持されて
    /// 表示/非表示の枚数だけが変わる
    var slotIndex: Int = -1
}

extension MediaEntry {
    /// 後方互換デコード。旧フォーマットにはslotIndexキーが無いので、
    /// キー欠落・型不正・負値はすべて未配置(-1)として読む
    /// (settings.jsonの未知キー無視と同じ方針)。
    /// extensionに置くことでメンバワイズinit(デフォルト値slotIndex=-1付き)
    /// を潰さない。encodeはシンセサイズされたまま(CodingKeysで全キーを
    /// 列挙してあるのでslotIndexも保存される)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        // providerは新設キー。旧フォーマット(キー欠落)・未知値・型不正は
        // slotIndexと同じ方針でappleMusicに倒す
        provider = (try? container.decode(Provider.self, forKey: .provider)) ?? .appleMusic
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        country = try container.decode(String.self, forKey: .country)
        url = try container.decode(String.self, forKey: .url)
        artworkURL = try container.decode(String.self, forKey: .artworkURL)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        let raw = (try? container.decodeIfPresent(Int.self, forKey: .slotIndex)) ?? nil
        slotIndex = raw.map { $0 >= 0 ? $0 : -1 } ?? -1
    }
}

/// レコードのスロット配置に関する純ロジック(自由配置モデル)。
/// UI・永続化に依存しない計算だけをここに置き、SleevesTestsから
/// 直接検証できるようにする(このファイルはテストターゲットにも
/// コンパイルされる)。
///
/// モデル: スロットは0..<capacityのグリッド位置(行優先index)。
/// 各エントリのslotIndexは一意(読み込み時のnormalizedが保証する)。
/// slotIndex >= capacity のエントリは登録を保持したまま非表示。
enum ShelfPlacement {

    /// 読み込んだ配列を正規化する。
    /// - slotIndexが未配置(-1)・重複・他エントリと衝突しているものには、
    ///   ファイル内の順序を保ったまま先頭から空きスロットを割り当てる
    ///   (=旧密配置と同じ見え方へのマイグレーション)
    /// - 結果はslotIndex昇順に並べる(保存JSONが読み順=表示順になる)
    /// - slotIndexが有効で一意なエントリは触らない(capacity超過の
    ///   非表示エントリもその位置のまま保持する)
    /// 戻り値のchangedは「内容か並びが変わったか」で、trueのときだけ
    /// 呼び出し側がalbums.jsonへ即座に保存する
    static func normalized(_ entries: [MediaEntry]) -> (entries: [MediaEntry], changed: Bool) {
        var taken = Set<Int>()
        var nextFree = 0
        var result = entries
        for i in result.indices {
            let slot = result[i].slotIndex
            if slot >= 0, !taken.contains(slot) {
                taken.insert(slot)
            } else {
                while taken.contains(nextFree) { nextFree += 1 }
                result[i].slotIndex = nextFree
                taken.insert(nextFree)
            }
        }
        result.sort { $0.slotIndex < $1.slotIndex }
        return (result, result != entries)
    }

    /// capacity個のスロット配列を作り、0 <= slotIndex < capacity の
    /// エントリをそのスロット位置に置く(途中に空きがあってもよい)。
    /// slotIndex >= capacity のエントリは含まれない(登録は保持・非表示)。
    /// 重複slotIndexは正規化済み前提だが、万一あれば先勝ちで処理する
    static func paddedSlots(_ entries: [MediaEntry], capacity: Int) -> [MediaEntry?] {
        var slots = [MediaEntry?](repeating: nil, count: max(0, capacity))
        for entry in entries where entry.slotIndex >= 0 && entry.slotIndex < slots.count {
            if slots[entry.slotIndex] == nil {
                slots[entry.slotIndex] = entry
            }
        }
        return slots
    }

    /// 先頭から数えて最初の空きスロット(capacity内)。
    /// 空きが無ければnil(=満杯)。entries.count < capacityなら必ず見つかる
    static func firstEmptySlot(entries: [MediaEntry], capacity: Int) -> Int? {
        let occupied = Set(entries.map(\.slotIndex).filter { $0 >= 0 && $0 < capacity })
        return (0..<max(0, capacity)).first { !occupied.contains($0) }
    }

    /// 空きスロットへの内部ドラッグドロップ(自由配置)。
    /// ドラッグしたエントリのslotIndexをsに変えるだけで、他のレコードは
    /// 一切動かない。同じスロット・対象が占有済み・範囲外・ID不明ならnil
    /// (変化なし/拒否)。返す配列はslotIndex昇順
    static func place(entries: [MediaEntry], draggedID: String, atSlot s: Int, capacity: Int) -> [MediaEntry]? {
        guard s >= 0, s < capacity,
              let i = entries.firstIndex(where: { $0.id == draggedID }),
              entries[i].slotIndex != s,
              paddedSlots(entries, capacity: capacity)[s] == nil else { return nil }
        var result = entries
        result[i].slotIndex = s
        result.sort { $0.slotIndex < $1.slotIndex }
        return result
    }

    /// 占有スロット上への内部ドラッグドロップ(スライド並び替え)。
    /// 従来のmoveの一般化:
    /// - E = 全エントリをslotIndex昇順に並べた「占有順序」、
    ///   P = 占有スロット位置の集合(不変)
    /// - ドラッグしたエントリをEから外し、ドロップ先の占有エントリの
    ///   直前(左半分)/直後(右半分)の順序位置へ挿入する
    /// - 新しい順序のi番目にPのi番目のスロットを再割当てする
    /// 結果、ドラッグ元とドロップ先の間のレコードが1スロットずつ
    /// スライドし、ギャップの向こう側や範囲外のレコードは動かない。
    /// 密配置(P=[0,1,2,...])では旧moveと完全一致する。
    /// slotIndex >= capacity の非表示エントリは最大側=順序末尾に位置する
    /// ため、表示中レコード間の並び替えでは位置が変わらない。
    /// 変化が無い場合(自分自身・隣接の同順位置へのドロップ)はnil。
    /// 返す配列はslotIndex昇順
    static func reorder(entries: [MediaEntry], draggedID: String, targetSlotIndex: Int, after: Bool) -> [MediaEntry]? {
        let sorted = entries.sorted { $0.slotIndex < $1.slotIndex }
        guard let dragged = sorted.first(where: { $0.id == draggedID }) else { return nil }
        var order = sorted.filter { $0.id != draggedID }
        let rank: Int
        if let target = order.firstIndex(where: { $0.slotIndex == targetSlotIndex }) {
            rank = target + (after ? 1 : 0)
        } else {
            // 対象スロットの占有者がドラッグ自身(除去済み)か、
            // 占有の無いスロット: 自身の順位に戻すので変化なしになる
            rank = order.filter { $0.slotIndex < targetSlotIndex }.count
        }
        order.insert(dragged, at: rank)
        let positions = sorted.map(\.slotIndex)
        var changed = false
        for i in order.indices where order[i].slotIndex != positions[i] {
            order[i].slotIndex = positions[i]
            changed = true
        }
        return changed ? order : nil
    }

    /// 新規エントリの挿入シフト(外部ドラッグ/シェルフ間転送)。
    /// 挿入スロット s(0..<capacity)への配置:
    /// - s が空き → 新規エントリをそのままsに置く(他は動かない)
    /// - s が占有 → sを含む連続占有ラン[a,b]を調べる。
    ///   b+1 < capacity(ランの右に空き)なら占有エントリ[s..b]を各+1へ
    ///   シフトして新規をsへ。右が詰まっているなら、ランの左端a>0なら
    ///   a-1が空きなので占有エントリ[a..s]を各-1へシフトして新規をsへ
    ///   (新規は対象レコードの位置に入り、対象以下が左へずれる)。
    ///   entries.count < capacity なら必ずどちらかが成功する。
    /// 戻り値は新規を含む配列(slotIndex昇順)。sが範囲外、または
    /// どちらにもずらせない(=満杯)場合はnil
    static func insertionShift(entries: [MediaEntry], inserting newEntry: MediaEntry, at s: Int, capacity: Int) -> [MediaEntry]? {
        guard s >= 0, s < capacity else { return nil }
        let occupancy = paddedSlots(entries, capacity: capacity)
        var placed = newEntry
        placed.slotIndex = s
        var result: [MediaEntry]
        if occupancy[s] == nil {
            result = entries + [placed]
        } else {
            // sを含む連続占有ラン[a,b]
            var a = s
            while a - 1 >= 0, occupancy[a - 1] != nil { a -= 1 }
            var b = s
            while b + 1 < capacity, occupancy[b + 1] != nil { b += 1 }
            if b + 1 < capacity {
                // 右に空き: [s..b] を各+1
                result = entries.map { e in
                    var e = e
                    if e.slotIndex >= s, e.slotIndex <= b { e.slotIndex += 1 }
                    return e
                } + [placed]
            } else if a > 0 {
                // 右は詰まり、左に空き: [a..s] を各-1
                result = entries.map { e in
                    var e = e
                    if e.slotIndex >= a, e.slotIndex <= s { e.slotIndex -= 1 }
                    return e
                } + [placed]
            } else {
                return nil
            }
        }
        result.sort { $0.slotIndex < $1.slotIndex }
        return result
    }

    /// スロットindexの中心のグリッド座標(スロット矩形系・左上原点)。
    /// ShelfView.slotRectと同じ幾何: セル間隔込みの格子の中心
    static func slotCenter(index: Int, columns: Int, cell: CGFloat, columnSpacing: CGFloat, rowSpacing: CGFloat) -> CGPoint {
        let col = index % columns
        let row = index / columns
        return CGPoint(
            x: CGFloat(col) * (cell + columnSpacing) + cell / 2,
            y: CGFloat(row) * (cell + rowSpacing) + cell / 2
        )
    }

    /// グリッド座標 point に最も近い空きスロット(スロット中心との
    /// ユークリッド距離。同距離ならindex小さい方=昇順走査で先勝ち)。
    /// 余白ドロップ・最終スロット右半分のドロップ先解決に使う。
    /// 空きスロットが無ければnil(=満杯として拒否)。
    /// slotOffsetには構造プラグインのコンテンツオフセット
    /// (見た目の中心=ピッチ中心+オフセット)を渡す。既定はゼロオフセット。
    /// (CGSize.zeroではなくwidth/heightで書く: テストターゲット側
    ///  ではCGSize.zeroが解決できない環境があるため)
    static func nearestEmptySlot(entries: [MediaEntry], capacity: Int, columns: Int, cell: CGFloat, columnSpacing: CGFloat, rowSpacing: CGFloat, at point: CGPoint, slotOffset: (Int) -> CGSize = { _ in CGSize(width: 0, height: 0) }) -> Int? {
        guard capacity > 0, columns > 0 else { return nil }
        let occupied = Set(entries.map(\.slotIndex).filter { $0 >= 0 && $0 < capacity })
        var best: (index: Int, distance2: CGFloat)?
        for i in 0..<capacity where !occupied.contains(i) {
            let o = slotOffset(i)
            let pitch = slotCenter(index: i, columns: columns, cell: cell, columnSpacing: columnSpacing, rowSpacing: rowSpacing)
            let center = CGPoint(x: pitch.x + o.width, y: pitch.y + o.height)
            let dx = center.x - point.x
            let dy = center.y - point.y
            let d2 = dx * dx + dy * dy
            if best == nil || d2 < best!.distance2 {
                best = (i, d2)
            }
        }
        return best?.index
    }

    /// 上辺のウィンドウ移動用ドラッグ帯(WindowDragGesture)の高さ。
    /// 既定はtopPaddingだが、構造プラグインのslotContentOffsetで1段目
    /// (0..<columns)のレコードが上方向(dy < 0)へせり上がる場合は、
    /// ドラッグ帯がレコード上端へ被ってクリック/D&Dを奪わないよう
    /// 見た目の上端(topPadding + dy)まで縮める。
    /// dy >= 0(下方向・オフセット無し)ではtopPaddingのまま維持し、
    /// 負値は0へクランプする。
    /// (CGSize.zeroではなくwidth/heightで書く: テストターゲット互換)
    static func topDragStripHeight(topPadding: CGFloat, columns: Int, slotOffset: (Int) -> CGSize = { _ in CGSize(width: 0, height: 0) }) -> CGFloat {
        guard topPadding > 0 else { return 0 }
        guard columns > 0 else { return topPadding }
        var height = topPadding
        for c in 0..<columns {
            height = min(height, topPadding + slotOffset(c).height)
        }
        return max(0, height)
    }
}

/// Apple Music / SpotifyのURL・ID文字列を解析する。
/// 受け付ける形式:
///   1440842296
///   https://music.apple.com/jp/album/brown-sugar/1440842296  (?i=, music://も可)
///   https://music.apple.com/jp/playlist/lo-fi-japan/pl.38eb70f47b834187a21cf4e8e5833f35
///   https://open.spotify.com/album/<id>  (?si=, intl-XXプレフィックスも可)
///   https://open.spotify.com/playlist/<id>
///   spotify:album:<id> / spotify:playlist:<id>
enum MediaURLParser {

    struct Parsed {
        let kind: MediaEntry.Kind
        let provider: MediaEntry.Provider
        /// Apple Musicのストアフロント。Spotifyでは未使用("")
        let country: String
        let id: String
    }

    static func parse(_ raw: String) -> Parsed? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // spotify: URI形式
        if text.lowercased().hasPrefix("spotify:") {
            return parseSpotifyURI(text)
        }

        // 素の数字ID → アルバム扱い
        if let id = Int(text), id > 100_000 {
            return Parsed(kind: .album, provider: .appleMusic, country: "jp", id: String(id))
        }

        if text.contains("music.apple.com") {
            if text.hasPrefix("music://") {
                text = text.replacingOccurrences(of: "music://", with: "https://")
            } else if !text.hasPrefix("http") {
                text = "https://" + text
            }
        }

        // music.apple.comと同じくスキーム省略を補完する
        // (これが無いとURL.hostが取れずparse失敗になる)
        if text.contains("open.spotify.com"), !text.hasPrefix("http") {
            text = "https://" + text
        }

        guard let url = URL(string: text),
              let host = url.host?.lowercased() else { return nil }

        if host == "open.spotify.com" {
            return parseSpotifyWebURL(url)
        }

        guard host.hasSuffix("music.apple.com") else { return nil }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        var country = "jp"
        var index = 0
        if parts[0].count == 2 {
            country = parts[0].lowercased()
            index = 1
        }
        guard index < parts.count else { return nil }

        switch parts[index] {
        case "album":
            // {slug}/{数字ID} または {数字ID}
            let rest = Array(parts[(index + 1)...])
            guard let number = rest.reversed().first(where: { Int($0).map { $0 > 100_000 } == true }) else {
                return nil
            }
            return Parsed(kind: .album, provider: .appleMusic, country: country, id: number)
        case "playlist":
            let rest = Array(parts[(index + 1)...])
            guard let plID = rest.first(where: { $0.hasPrefix("pl.") && $0.count > 3 }) else {
                return nil
            }
            return Parsed(kind: .playlist, provider: .appleMusic, country: country, id: plID)
        default:
            return nil
        }
    }

    // MARK: - Spotify

    /// `spotify:album:<id>` / `spotify:playlist:<id>` のURI形式
    private static func parseSpotifyURI(_ text: String) -> Parsed? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0].lowercased() == "spotify" else { return nil }
        guard let kind = spotifyKind(parts[1]), isValidSpotifyID(parts[2]) else { return nil }
        return Parsed(kind: kind, provider: .spotify, country: "", id: parts[2])
    }

    /// `https://open.spotify.com/<type>/<id>` と `intl-<locale>/` プレフィックス付き。
    /// クエリ(?si=等)はURLのpathに含まれないので自然に無視される
    private static func parseSpotifyWebURL(_ url: URL) -> Parsed? {
        let parts = url.path.split(separator: "/").map(String.init)
        var index = 0
        if parts.first?.hasPrefix("intl-") == true { index = 1 }
        guard index + 1 < parts.count else { return nil }
        guard let kind = spotifyKind(parts[index]), isValidSpotifyID(parts[index + 1]) else { return nil }
        return Parsed(kind: kind, provider: .spotify, country: "", id: parts[index + 1])
    }

    private static func spotifyKind(_ type: String) -> MediaEntry.Kind? {
        switch type.lowercased() {
        case "album": return .album
        case "playlist": return .playlist
        default: return nil  // track/artist/episode/show等は対象外
        }
    }

    /// SpotifyのID。実際は22文字のbase62だが緩く検証する
    /// (固定22を必須にしない。文字種だけは厳密に見る)
    private static func isValidSpotifyID(_ id: String) -> Bool {
        guard id.count >= 15, id.count <= 30 else { return false }
        return id.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }
}

/// アプリ内ドラッグのペーストボード文字列(JSON)。
/// エントリそのものを載せるので、別シェルフのウィンドウへのドロップは
/// カタログ再取得なしで移せる(アートワークもシェルフ間共有)。
/// sourceShelfIDが自分と同じならシェルフ内の並び替え、違うなら
/// シェルフ間の移動として扱う。
struct ShelfDragPayload: Codable {
    let sourceShelfID: String
    let entry: MediaEntry

    func encode() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// ペーストボード文字列を解釈する。外部アプリのテキスト(URL等)は
    /// この型のキーを持たないのでデコード失敗し、nil=外部扱いになる
    static func decode(_ text: String) -> ShelfDragPayload? {
        guard text.hasPrefix("{"), let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ShelfDragPayload.self, from: data)
    }
}

/// Spotifyの公開ページHTMLからメタ情報を取り出す純ロジック。
/// SpotifyCatalogClient(ネットワーク側)から分離してここに置くのは、
/// このファイルがテストターゲットに直接コンパイルされるため
/// (Shared/MediaEntry.swift はSleevesTestsのsourcesに含まれる)。
enum SpotifyPageParser {

    /// HTML中の `<meta property="<property>" content="..."/>` の
    /// content属性値を返す。属性の順序(contentが先/後)や他の属性の
    /// 有無に影響されないよう、タグを拾ってから属性単位で解釈する。
    /// content値のHTMLエンティティはデコード済みで返す。
    /// 見つからなければnil
    static func metaContent(in html: String, property: String) -> String? {
        guard let tagPattern = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        for match in tagPattern.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard attributeValue(in: tag, name: "property") == property else { continue }
            if let content = attributeValue(in: tag, name: "content") {
                return decodeHTMLEntities(content)
            }
        }
        return nil
    }

    /// og:description からアーティスト/キュレーター名を取り出す。
    /// " · "(U+00B7)区切りのセグメント列:
    /// - アルバム: `"Pink Floyd · album · 1973 · 10 songs"` → 先頭セグメント
    /// - プレイリスト: `"Playlist · Spotify · 50 items · 33.6M saves"` →
    ///   先頭が"Playlist"なら2番目セグメント。それ以外は"Spotify"に倒す
    static func artist(fromOgDescription desc: String, kind: MediaEntry.Kind) -> String {
        let segments = desc.components(separatedBy: "\u{00B7}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch kind {
        case .album:
            return segments.first ?? ""
        case .playlist:
            if segments.count >= 2, segments[0] == "Playlist" { return segments[1] }
            return "Spotify"
        }
    }

    /// 主要なHTMLエンティティと数値参照(&#NNN;/&#xHH;)をデコードする。
    /// `&amp;` は必ず最後に処理する(先にやると `&amp;lt;` が `<` に
    /// 二重デコードされる)
    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        if let pattern = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#) {
            let range = NSRange(result.startIndex..., in: result)
            // 後ろから置き換えて前方のrangeを狂わせない
            for match in pattern.matches(in: result, range: range).reversed() {
                guard let whole = Range(match.range, in: result),
                      let numRange = Range(match.range(at: 1), in: result) else { continue }
                let token = result[numRange]
                let scalar: UInt32?
                if token.hasPrefix("x") {
                    scalar = UInt32(token.dropFirst(), radix: 16)
                } else {
                    scalar = UInt32(token)
                }
                if let scalar, let uni = Unicode.Scalar(scalar) {
                    result.replaceSubrange(whole, with: Character(uni).description)
                }
            }
        }
        for (entity, replacement) in [
            ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"),
            ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&"),
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    /// `<meta ...>`タグ文字列から指定属性の値を拾う。
    /// `"..."`/`'...'` の両方の引用形式に対応
    private static func attributeValue(in tag: String, name: String) -> String? {
        for quote in ["\"", "'"] {
            // 属性名の直前に空白を要求する(data-content等の別属性名に
            // 部分一致しないため)
            if let pattern = try? NSRegularExpression(
                pattern: "\\s\(name)\\s*=\\s*\(quote)([^\(quote)]*)\(quote)",
                options: [.caseInsensitive]
            ), let match = pattern.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
               let valueRange = Range(match.range(at: 1), in: tag) {
                return String(tag[valueRange])
            }
        }
        return nil
    }
}
