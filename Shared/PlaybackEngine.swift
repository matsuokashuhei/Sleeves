import AppKit
import Foundation
import os

/// 再生エンジン。
///
/// - アルバム: 「音楽を再生」ショートカットにURLを渡してMusicアプリで再生
///   (`shortcuts://run-shortcut` URLスキーム経由。LaunchServicesを介すため
///   呼び出し元の文脈に引きずられず、オートメーション許可(TCC)も不要。
///   Apple Events / shortcuts CLI はGUIアプリプロセスからだとショートカットの
///   名前解決に失敗するため不採用 — 2026-10-18 実機検証)
/// - プレイリスト: MusicKit ApplicationMusicPlayer で本アプリ内再生
///   (ショートカットの「音楽を再生」はプレイリストURLを解決できないため — 実測済み)
enum PlaybackEngine {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "Playback")

    /// 対応するショートカット名(この順で優先)。
    /// "Sleeves Playback" はアプリが同梱ファイルからインストールする名前
    /// (ASCIIなのでNFD/NFC正規化の問題を踏まない)。
    /// "Records Playback"/"Recordsで再生" はアプリ名変更(Records→Sleeves)
    /// 前に作成・インストール済みのショートカットを拾うための後方互換。
    /// "Sleevesで再生" は新名での手動作成名。
    static let shortcutNameCandidates = [
        "Sleeves Playback",
        "Sleevesで再生",
        "Records Playback",
        "Recordsで再生",
    ]

    enum PlaybackError: LocalizedError {
        case shortcutMissing(visible: [String])
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .shortcutMissing(let visible):
                let names = visible.isEmpty
                    ? String(localized: "(No shortcuts are visible to the shortcuts command.)")
                    : String(localized: "Found shortcuts: \(visible.joined(separator: ", "))")
                return String(localized: "Playback shortcut (\(shortcutNameCandidates.joined(separator: " / "))) not found.\n\(names)")
            case .failed(let detail):
                return String(localized: "Playback failed: \(detail)")
            }
        }
    }

    /// 種類に応じて再生する
    static func play(_ entry: MediaEntry) async throws {
        logger.notice("play() start provider=\(entry.provider.rawValue, privacy: .public) kind=\(entry.kind.rawValue, privacy: .public) url=\(entry.url, privacy: .public)")
        switch entry.provider {
        case .appleMusic:
            switch entry.kind {
            case .album:
                try await playAlbum(entry)
            case .playlist:
                try await PlaylistPlayer.play(entry)
            }
        case .spotify:
            try await playSpotify(entry)
        }
        logger.notice("play() requested OK")
    }

    /// 停止
    static func stop(_ entry: MediaEntry) async throws {
        logger.notice("stop() provider=\(entry.provider.rawValue, privacy: .public) kind=\(entry.kind.rawValue, privacy: .public)")
        switch entry.provider {
        case .appleMusic:
            switch entry.kind {
            case .album:
                try await runTool("/usr/bin/osascript", ["-e", Self.stopMusicScript])
            case .playlist:
                PlaylistPlayer.stop()
            }
        case .spotify:
            try await runTool("/usr/bin/osascript", ["-e", Self.stopSpotifyScript])
        }
    }

    /// `is running` ガード付きの停止スクリプト。
    /// `tell application "Music"` 単体だと未起動のMusic.appを起動してしまうため、
    /// `is running`(起動せずに起動状態だけ調べられる)で囲む。
    private static let stopMusicScript = """
    if application "Music" is running then
        tell application "Music" to stop
    end if
    """

    /// Musicアプリの再生を止める(二重再生の防止用)
    static func stopMusicApp() async {
        _ = try? await runTool("/usr/bin/osascript", ["-e", Self.stopMusicScript])
    }

    /// `is running` ガード付きの停止スクリプト(stopMusicScriptと同じパターン。
    /// 未起動のSpotify.appを起動させない)
    private static let stopSpotifyScript = """
    if application "Spotify" is running then
        tell application "Spotify" to pause
    end if
    """

    /// Spotifyの再生を止める(二重再生の防止用)。
    /// Apple Music側の再生開始時に呼ぶ。未インストール・未起動でも安全
    /// (is runningガードで未起動は触らず、osascript失敗は握り潰す)
    static func stopSpotifyApp() async {
        _ = try? await runTool("/usr/bin/osascript", ["-e", Self.stopSpotifyScript])
    }

    /// Musicアプリの現在の再生状態 (isPlaying, 現在のアルバム名)。
    /// Music.appが起動していなければ起動せず (false, nil) を返す
    /// (PlaybackMonitor が2秒おきに呼ぶため、ガードがないとMusic.appを起動し続ける)。
    static func nowPlayingInfo() async -> (isPlaying: Bool, album: String?)? {
        let script = """
        if application "Music" is running then
            tell application "Music"
                set s to player state as text
                set a to ""
                try
                    set a to album of current track
                end try
                return s & "|" & a
            end tell
        else
            return "stopped|"
        end if
        """
        guard let out = try? await runTool("/usr/bin/osascript", ["-e", script], captureOutput: true) else {
            return nil
        }
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        guard parts.count >= 2 else { return nil }
        return (parts[0] == "playing", parts[1].isEmpty ? nil : parts[1])
    }

    /// Spotifyの現在の再生状態 (isPlaying, 現在のアルバム名)。
    /// nowPlayingInfo()と同じくis runningガード付き —
    /// Spotify.appが起動していなければ起動せず (false, nil) を返し、
    /// 未インストールならosascript自体が失敗してnilを返す
    static func spotifyNowPlayingInfo() async -> (isPlaying: Bool, album: String?)? {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                set s to player state as text
                set a to ""
                try
                    set a to album of current track
                end try
                return s & "|" & a
            end tell
        else
            return "stopped|"
        end if
        """
        guard let out = try? await runTool("/usr/bin/osascript", ["-e", script], captureOutput: true) else {
            return nil
        }
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        guard parts.count >= 2 else { return nil }
        return (parts[0] == "playing", parts[1].isEmpty ? nil : parts[1])
    }

    // MARK: - アルバム(Musicアプリ + ショートカット)

    private static func playAlbum(_ entry: MediaEntry) async throws {
        // 本アプリ内プレイヤーとSpotifyが再生中なら先に止める
        // (二重再生の防止。PlaylistPlayer.playがMusicアプリと
        // Spotifyを止めるのと対称)
        PlaylistPlayer.stop()
        await stopSpotifyApp()

        // ショートカット名の解決には `shortcuts list` を使う
        // (一覧の取得はアプリプロセスからでも動作することを確認済み)
        let installed: [String]
        do {
            installed = try await listShortcutNames()
        } catch {
            throw PlaybackError.failed(String(localized: "Failed to list shortcuts: \(error.localizedDescription)"))
        }
        logger.notice("installed shortcuts: \(installed.joined(separator: " | "), privacy: .public)")

        // 呼び出し名は `shortcuts list` が返す表記をそのまま使う。
        // Shortcutsはショートカット名をNFD(濁点分解)で保存するため、
        // ソース上のNFCリテラルをpercent-encodingして送ると
        // run-shortcut側の名解決が失敗する(2026-11-08実機:
        // NFC名→「Could not find the shortcut」、NFD名→成功)。
        // SwiftのString == は正準等価で比較するためマッチ自体は
        // NFC候補でも成立し、ここで得るのはストレージ上の表記。
        // 優先順は候補リスト側を外側に回す(出現順では効かない)
        guard let name = shortcutNameCandidates
            .compactMap({ candidate in installed.first(where: { $0 == candidate }) })
            .first else {
            logger.error("no candidate name installed")
            throw PlaybackError.shortcutMissing(visible: installed)
        }

        // shortcuts://run-shortcut?name=<enc>&input=<enc>
        let encoded = "shortcuts://run-shortcut?name=\(percentEncoded(name))&input=\(percentEncoded(entry.url))"
        guard let target = URL(string: encoded) else {
            throw PlaybackError.failed(String(localized: "Failed to build the shortcut URL."))
        }
        logger.notice("opening \(encoded, privacy: .public)")

        // LaunchServices経由でShortcutsアプリに実行させる(/usr/bin/open)
        try await runTool("/usr/bin/open", [target.absoluteString])
    }

    static func listShortcutNames() async throws -> [String] {
        let output = try await runTool("/usr/bin/shortcuts", ["list"], captureOutput: true) ?? ""
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func percentEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    // MARK: - Spotify(Spotify.appをAppleScriptで制御)

    /// 冷起動直後にSpotifyがApple Eventを受け付けるまでの
    /// `play track` リトライ回数/間隔(秒)
    private static let spotifyPlayRetryCount = 50
    private static let spotifyPlayRetryInterval: TimeInterval = 0.1

    /// 再生要求後にSpotifyがフォアグラウンドへ出た場合に監視する時間(秒)
    private static let spotifyFrontmostWatchDuration: TimeInterval = 6

    /// Spotifyのbundle ID(フォアグラウンド監視の判定に使う)
    private static let spotifyBundleID = "com.spotify.client"

    /// Spotify.appで `spotify:<kind>:<id>` のURIを再生する。
    /// アルバムもプレイリストも `play track` で再生できる(実機検証済み)。
    ///
    /// フォアグラウンド化の防止(未然防止+保険の2段):
    /// - 起動済みなら従来どおり直接 `play track` を送るだけ。
    /// - 未起動なら `tell application "Spotify" to launch` で起動する。
    ///   `launch` はactivate/reopenイベントを送らずに起動するため
    ///   Spotifyはフォアグラウンドへ出ない(`tell` 対象を未起動のまま
    ///   起動させるとactivateを伴うのでその形は使わない)。
    ///   launch直後はApple Eventをまだ受け付けない場合があるため、
    ///   `play track` は0.1秒間隔・最大50回リトライして成功を待つ。
    /// - 保険として、再生要求成功後は startSpotifyFrontmostWatchdog() が
    ///   約6秒間frontmostを監視し、Spotifyがフォアグラウンドへ出たら
    ///   NSApp.activate()でSleeves側がアクティブを取り戻す。
    ///
    /// 未インストール・コマンド失敗はosascriptの非0終了→PlaybackError.failed
    private static func playSpotify(_ entry: MediaEntry) async throws {
        // 本アプリ内プレイヤーとMusicアプリが再生中なら先に止める
        // (二重再生の防止。playAlbum/PlaylistPlayer.playと対称)
        PlaylistPlayer.stop()
        await stopMusicApp()

        let uri = "spotify:\(entry.kind.rawValue):\(entry.id)"
        let playScript = "tell application \"Spotify\" to play track \"\(uri)\""

        // `is running` は起動させずに起動状態だけ調べられる。
        // 未インストールならosascript自体が失敗し、try?でnil→false扱い
        // →冷起動経路の `launch` がやはり失敗してPlaybackError.failedになる
        // (従来どおりエラーは握り潰さない)
        let runningOutput = try? await runTool(
            "/usr/bin/osascript",
            ["-e", "application \"Spotify\" is running"],
            captureOutput: true
        )
        let isRunning = runningOutput?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"

        if isRunning {
            logger.notice("spotify: already running; sending play track directly uri=\(uri, privacy: .public)")
            try await runTool("/usr/bin/osascript", ["-e", playScript])
        } else {
            // 冷起動経路: activateを伴わない `launch` で起動し、
            // Apple Event受付開始まで `play track` をリトライする
            logger.notice("spotify: not running; cold launch without activation uri=\(uri, privacy: .public)")
            try await runTool("/usr/bin/osascript", ["-e", "tell application \"Spotify\" to launch"])
            var lastError: Error?
            var succeeded = false
            for attempt in 1...Self.spotifyPlayRetryCount {
                try Task.checkCancellation()
                do {
                    try await runTool("/usr/bin/osascript", ["-e", playScript])
                    logger.notice("spotify: play track succeeded on attempt \(attempt, privacy: .public)")
                    succeeded = true
                    break
                } catch {
                    lastError = error
                    // PlaybackError.failedのdetailはosascriptのstdout+stderr
                    // テキスト。なければlocalizedDescriptionをマッチ対象にする
                    let detail: String
                    if case .failed(let text) = error as? PlaybackError {
                        detail = text
                    } else {
                        detail = error.localizedDescription
                    }
                    // 一時的な「起動中でAE未受付」エラーだけリトライ継続。
                    // TCC拒否(-1743)・構文エラー等の恒久エラーは
                    // 50回待っても治らないので即throwして抜ける
                    guard Self.isSpotifyTransientAEError(detail) else {
                        logger.error("spotify: non-transient error on attempt \(attempt, privacy: .public); aborting retry: \(detail, privacy: .public)")
                        throw error
                    }
                    logger.notice("spotify: play track attempt \(attempt, privacy: .public)/\(Self.spotifyPlayRetryCount, privacy: .public) failed: \(detail, privacy: .public)")
                    try? await Task.sleep(nanoseconds: UInt64(Self.spotifyPlayRetryInterval * 1_000_000_000))
                }
            }
            guard succeeded else {
                logger.error("spotify: play track gave up after \(Self.spotifyPlayRetryCount, privacy: .public) attempts")
                throw lastError ?? PlaybackError.failed("play track failed after cold launch")
            }
        }

        startSpotifyFrontmostWatchdog()
    }

    /// osascript経由のApple Eventエラーが「Spotify起動中でAE未受付」の
    /// 一時的なものかを判定する(リトライ継続可否の判定に使う)。
    /// osascriptはstderrに英語のAEエラーメッセージ+数値コードを返す
    /// (例: "Spotify got an error: Application isn't running. (-600)" /
    ///  "Connection is invalid (-609)")。メッセージ文字列はロケールに
    /// 依らず英語なので文字列マッチで判定し、数値コード(-600=procNotFound
    /// 「アプリ未起動/起動途中」、-609=connectionInvalid「AE接続無効」)も
    /// 併せて見る。これら以外(-1743のTCC拒否、スクリプト構文エラー等)は
    /// 恒久エラーとして偽を返し、呼び出し側で即throwさせる。
    private static func isSpotifyTransientAEError(_ message: String) -> Bool {
        message.contains("isn't running")
            || message.contains("Connection is invalid")
            || message.contains("connection is invalid")
            || message.contains("-600")
            || message.contains("-609")
    }

    /// 保険: osascript成功後にSpotifyがフォアグラウンドへ出てきた場合、
    /// バックグラウンドタスクで約6秒間 frontmostApplication を監視し、
    /// frontmostがSpotifyになるたび NSApp.activate() でSleevesへ
    /// アクティブを取り戻す(メインスレッドで呼ぶ)。
    /// 1回取り戻しても監視は継続する(冷起動→後から窓を出す等、
    /// 2段階でactivateされうるため)。
    /// --catalog-test CLI経路ではスキップする(CLIでNSAppをactivateさせない)
    private static func startSpotifyFrontmostWatchdog() {
        guard !ProcessInfo.processInfo.arguments.contains("--catalog-test") else {
            logger.notice("spotify watchdog: skipped (--catalog-test CLI mode)")
            return
        }
        Task.detached {
            logger.notice("spotify watchdog: start; watching frontmost for \(Self.spotifyFrontmostWatchDuration, privacy: .public)s")
            let deadline = Date().addingTimeInterval(Self.spotifyFrontmostWatchDuration)
            var reactivations = 0
            while Date() < deadline {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.spotifyBundleID {
                    reactivations += 1
                    logger.notice("spotify watchdog: Spotify is frontmost; reactivating Sleeves (#\(reactivations, privacy: .public))")
                    await MainActor.run { NSApp.activate() }
                    // activate反映の猶予を置き、直後の同一tickで再検出して
                    // activateを連打しないようにする
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            logger.notice("spotify watchdog: expired; frontmost reactivations=\(reactivations, privacy: .public)")
        }
    }

    /// 子プロセスが応答しなくなった場合の打ち切り時間(秒)
    private static let toolTimeout: TimeInterval = 15

    /// terminate()を無視する子プロセスにSIGKILLを送るまでの猶予(秒)
    private static let killGracePeriod: TimeInterval = 2

    /// 外部プロセスを実行する。
    /// - 標準出力/標準エラーはプロセス終了を待たず別スレッドで排出する。
    ///   (terminationHandler 内だけで読むと、子が64KB超を出力した時点で
    ///   パイプバッファが満杯→子がwriteでブロック→終了しないデッドロックになる)
    /// - `toolTimeout` 秒で応答がなければ terminate して継続を解放する。
    @discardableResult
    static func runTool(_ toolPath: String, _ arguments: [String], captureOutput: Bool = false) async throws -> String? {
        logger.notice("run \(toolPath, privacy: .public) \(arguments.joined(separator: " "), privacy: .public)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        /// 継続の多重resume防止と、排出スレッドからの結果受け取り用
        final class State: @unchecked Sendable {
            let lock = NSLock()
            var stdout = Data()
            var stderr = Data()
            var resumed = false
        }

        return try await withCheckedThrowingContinuation { continuation in
            let state = State()
            @Sendable func resumeOnce(with result: Result<String?, Error>) {
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.resumed else { return }
                state.resumed = true
                continuation.resume(with: result)
            }

            // 排出は run() 前から開始する(パイプデッドロック防止)
            let drained = DispatchGroup()
            drained.enter()
            DispatchQueue.global().async {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                state.lock.lock(); state.stdout = data; state.lock.unlock()
                drained.leave()
            }
            drained.enter()
            DispatchQueue.global().async {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                state.lock.lock(); state.stderr = data; state.lock.unlock()
                drained.leave()
            }

            process.terminationHandler = { proc in
                // EOFはプロセス終了直後に来るので、排出スレッドの完了を待ってから結果を読む
                drained.wait()
                let stdoutText = String(data: state.stdout, encoding: .utf8) ?? ""
                let stderrText = String(data: state.stderr, encoding: .utf8) ?? ""
                logger.notice("exit=\(proc.terminationStatus, privacy: .public) stdout='\(stdoutText, privacy: .public)' stderr='\(stderrText, privacy: .public)'")

                if proc.terminationReason == .exit && proc.terminationStatus == 0 {
                    resumeOnce(with: .success(captureOutput ? stdoutText : nil))
                } else {
                    resumeOnce(with: .failure(PlaybackError.failed(
                        (stdoutText + stderrText).isEmpty ? "exited \(proc.terminationStatus)" : (stdoutText + stderrText)
                    )))
                }
            }

            // タイムアウト: ハングした子プロセスを終了させ、継続を必ず一度だけ解放する
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.toolTimeout) {
                state.lock.lock(); let done = state.resumed; state.lock.unlock()
                guard !done else { return }
                logger.error("timeout(\(Self.toolTimeout, privacy: .public)s): terminating \(toolPath, privacy: .public)")
                process.terminate()
                // terminate()を無視する子へのエスカレーション。放置すると排出スレッドと
                // terminationHandler内のdrained.wait()が永久にリークする。
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGracePeriod) {
                    if process.isRunning {
                        logger.error("still running after terminate(); SIGKILL pid=\(process.processIdentifier, privacy: .public)")
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                resumeOnce(with: .failure(PlaybackError.failed(String(localized: "\(toolPath) timed out."))))
            }

            do {
                try process.run()
            } catch {
                logger.error("spawn failed: \(error.localizedDescription, privacy: .public)")
                // spawn失敗時は誰も書き込まないので書き込み端を閉じ、排出スレッドをEOFで抜けさせる
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                resumeOnce(with: .failure(error))
            }
        }
    }
}
