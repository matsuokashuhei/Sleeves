import Foundation
import os

/// Spotifyの公開エンドポイントからアルバム/プレイリストのメタデータを取得する。
/// 認証・APIキーは不要(実機検証済み):
/// - タイトル+アートワーク: `https://open.spotify.com/oembed?url=<canonical>`
/// - アーティスト/キュレーター名: `https://open.spotify.com/<type>/<id>`
///   のページHTMLの `og:description`(" · "区切り。純ロジックは
///   SpotifyPageParser — Shared/MediaEntry.swift)。
///   ブラウザ系UAにはogタグ無しのJSシェルが返るため非ブラウザUAで取る(実測)
enum SpotifyCatalogClient {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "Spotify")

    /// MediaCatalogClient.CatalogErrorと同等のLocalizedError
    /// (localized文字列は英語が既存スタイル)
    enum CatalogError: LocalizedError {
        case notFound
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return String(localized: "Not found on Spotify.")
            case .network(let detail):
                return String(localized: "Could not fetch from Spotify: \(detail)")
            }
        }
    }

    /// oEmbedレスポンスの必要分だけのデコード型。
    /// thumbnail_urlは正方形のジャケット画像(アートワークとして使う)
    private struct OEmbedResponse: Decodable {
        let title: String
        let thumbnailURL: String?

        private enum CodingKeys: String, CodingKey {
            case title
            case thumbnailURL = "thumbnail_url"
        }
    }

    /// parse済みのSpotify URLからエントリを作る。
    /// (1) oEmbedでタイトル+サムネイル、(2) ページHTMLのog:descriptionで
    /// アーティスト/キュレーター名を取る。og側が失敗してもoEmbedが
    /// 取れていれば artist="" で縮退して返す
    static func fetch(_ parsed: MediaURLParser.Parsed) async throws -> MediaEntry {
        let kind = parsed.kind.rawValue  // "album" | "playlist"
        let canonical = "https://open.spotify.com/\(kind)/\(parsed.id)"
        logger.notice("fetch start kind=\(kind, privacy: .public) id=\(parsed.id, privacy: .public) url=\(canonical, privacy: .public)")
        do {
            let oembed = try await fetchOEmbed(canonical: canonical)
            // og:descriptionの取得失敗は致命的ではない — タイトルと
            // アートワークがあればレコードとして成立するのでartist=""で縮退する
            var artist = ""
            do {
                artist = try await fetchArtist(canonical: canonical, kind: parsed.kind)
            } catch {
                logger.error("og:description fetch failed; artist degraded to empty id=\(parsed.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            let entry = MediaEntry(
                kind: parsed.kind,
                provider: .spotify,
                id: parsed.id,
                title: oembed.title,
                artist: artist,
                country: "",
                url: canonical,
                artworkURL: oembed.thumbnailURL ?? "",
                addedAt: .now
            )
            logger.notice("fetch ok title=\(entry.title, privacy: .public) artist=\(entry.artist, privacy: .public) artwork=\(entry.artworkURL, privacy: .public)")
            return entry
        } catch {
            logger.error("fetch failed id=\(parsed.id, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// oEmbedでタイトル+サムネイルURLを取得する。
    /// 非200はnotFound(ページが無い=解決不能)として扱う
    private static func fetchOEmbed(canonical: String) async throws -> OEmbedResponse {
        var components = URLComponents(string: "https://open.spotify.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: canonical)]
        guard let url = components.url else {
            throw CatalogError.network("failed to build oEmbed URL")
        }
        logger.notice("oEmbed GET \(url.absoluteString, privacy: .public)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.network("no HTTP response")
        }
        guard http.statusCode == 200 else {
            logger.error("oEmbed status=\(http.statusCode, privacy: .public) url=\(canonical, privacy: .public)")
            throw CatalogError.notFound
        }
        guard let decoded = try? JSONDecoder().decode(OEmbedResponse.self, from: data) else {
            throw CatalogError.network("oEmbed response not decodable")
        }
        return decoded
    }

    /// ページHTMLの og:description からアーティスト/キュレーター名を取る。
    /// 注意: ブラウザ系User-AgentだとJSシェル(ogタグ無し)が返る —
    /// og:タグはクローラー系/UA無し系のリクエストにだけ出る(2026-11-21実測)。
    /// そのためUAは非ブラウザのものを明示する
    private static func fetchArtist(canonical: String, kind: MediaEntry.Kind) async throws -> String {
        guard let url = URL(string: canonical) else {
            throw CatalogError.network("bad canonical URL")
        }
        var request = URLRequest(url: url)
        request.setValue("curl/8.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CatalogError.network("page HTTP \(status)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw CatalogError.network("page not UTF-8")
        }
        guard let desc = SpotifyPageParser.metaContent(in: html, property: "og:description") else {
            throw CatalogError.network("og:description missing")
        }
        let artist = SpotifyPageParser.artist(fromOgDescription: desc, kind: kind)
        logger.notice("og:description='\(desc, privacy: .public)' → artist='\(artist, privacy: .public)'")
        return artist
    }
}
