#if DEBUG
import Foundation
import os

/// 展示モード (Showcase Mode) 用の素材解決と仮想エントリ生成を行う純ロジック。
/// UI・ShelfManager・UserDefaults に依存しないため、SleevesTests から直接検証できる。
/// Release ビルドでは `#if DEBUG` により完全に除外される。
enum ShowcaseCatalog {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "Showcase")

    /// 展示用ジャケットとして読み込む画像拡張子（小文字）
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png"]

    /// 展示用エントリ ID の接頭辞（本物データの ID と衝突しない名前空間）
    static let entryIDPrefix = "showcase:"

    /// 展示素材ディレクトリを上書きする環境変数名
    static let directoryEnvKey = "SLEEVES_SHOWCASE_DIR"

    /// このエントリが展示モードの仮想エントリかどうか
    static func isShowcaseEntry(_ entry: MediaEntry) -> Bool {
        isShowcaseEntryID(entry.id)
    }

    /// この ID が展示モードの仮想エントリ ID かどうか
    static func isShowcaseEntryID(_ id: String) -> Bool {
        id.hasPrefix(entryIDPrefix)
    }

    /// リポジトリルート直下の `Docs/materials` を `#filePath` から解決する。
    /// このファイルは `<repo>/Shared/ShowcaseCatalog.swift` に配置されているため、
    /// 2階層上がリポジトリルートになる。
    static func defaultMaterialsDirectory(sourceFile: String = #filePath) -> URL {
        URL(fileURLWithPath: sourceFile)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Docs/materials", isDirectory: true)
    }

    /// 展示素材ディレクトリを解決する。
    /// 環境変数 `SLEEVES_SHOWCASE_DIR` が指定されていればそれを優先し、
    /// 未指定・空文字ならリポジトリの `Docs/materials` を返す。
    static func resolveMaterialsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sourceFile: String = #filePath
    ) -> URL {
        if let raw = environment[directoryEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return defaultMaterialsDirectory(sourceFile: sourceFile)
    }

    /// 指定ディレクトリ内の画像ファイル (`.jpg`/`.jpeg`/`.png`) をファイル名昇順で読み込み、
    /// 展示用の仮想 `MediaEntry` 配列を生成する。
    /// ディレクトリが存在しない・読めない場合はエラーログを出して空配列を返す。
    static func loadEntries(from directory: URL) -> [MediaEntry] {
        let fm = FileManager.default
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("showcase materials read failed: dir=\(directory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return []
        }

        let imageURLs = items
            .filter { url in
                guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                    return false
                }
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? true
                return isRegular
            }
            .sorted { a, b in
                let cmp = a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return a.lastPathComponent < b.lastPathComponent
            }

        let entries = imageURLs.enumerated().map { index, url in
            MediaEntry(
                kind: .album,
                provider: .appleMusic,
                id: "\(entryIDPrefix)\(url.lastPathComponent)",
                title: url.deletingPathExtension().lastPathComponent,
                artist: "",
                country: "",
                url: "",
                artworkURL: url.absoluteString,
                addedAt: Date(timeIntervalSince1970: 0),
                slotIndex: index
            )
        }
        logger.notice("showcase materials loaded: dir=\(directory.path, privacy: .public) count=\(entries.count, privacy: .public)")
        return entries
    }

    /// 展示用エントリのローカル画像ファイル URL を返す。
    /// 展示用エントリでない場合や file URL でない場合は nil。
    static func localArtworkURL(for entry: MediaEntry) -> URL? {
        guard isShowcaseEntry(entry),
              let url = URL(string: entry.artworkURL),
              url.isFileURL else {
            return nil
        }
        return url
    }
}
#endif
