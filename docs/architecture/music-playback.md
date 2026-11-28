# 音楽再生・カタログ取得・権限の設計メモ

## 1. Apple Music 再生と MusicKit

- **アルバムの再生**:
  - `shortcuts://run-shortcut?name=<enc>&input=<アルバムURL>` を `/usr/bin/open` で開き、ユーザーのショートカット「Sleeves Playback」（「音楽を再生」アクションの音楽パラメータに Shortcut Input を渡す）経由で Music アプリのカタログ再生を行う。
  - **制約**: Apple Events / `shortcuts run` CLI は GUI アプリプロセスから spawn するとショートカット名解決に失敗する（ターミナルからは成功する）。URL スキーム経由なら動作する。
  - `SystemSettings → プライバシーとセキュリティ → オートメーション → Sleeves → Shortcuts Events` を ON にしないと、アプリプロセスからの Shortcuts Events 照会が空リストを返す。
- **プレイリストの再生**:
  - ショートカットの「音楽を再生」はプレイリスト URL を解決できない（実測）。
  - MusicKit の `ApplicationMusicPlayer` で本アプリ内再生する（`ApplicationMusicPlayer.Queue(for: [playlist])`、`Playlist` は `PlayableMusicItem` 適合）。
- **macOS MusicKit の制約**:
  - macOS の MusicKit に `SystemMusicPlayer` は存在しない（iOS 専用、`@available(macOS, unavailable)`）。
  - `music://` ディープリンクは再生せずページを開くだけ（3 形式で実測）。
- **カタログ取得**:
  - iTunes Search/Lookup API は認証不要だがプレイリスト非対応。
  - プレイリストの検証は MusicKit カタログ API (`MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: ...)`) で行う。カタログ読み取りにユーザー認可は不要。

### MusicKit の App Service・権限 (TCC)

- **entitlement ではなく runtime サービス**:
  - `com.apple.developer.musickit` という entitlement は存在しない。entitlements ファイルに書くとプロビジョニングで `"invalid entitlement"` エラーになるため**書いてはいけない**。
  - 必要な設定: developer.apple.com → Identifiers → App ID `com.cacheandbuffer.Sleeves` → **App Services タブで MusicKit を有効化**。
  - CLI / `-allowProvisioningUpdates` からは App ID サービスを有効化できない（pbxproj への `SystemCapabilities` 注入も無効）。
- **Usage Description**:
  - `NSAppleMusicUsageDescription` が無いと `MusicAuthorization.request()` 時に TCC が `SIGABRT` でアプリを即死させる（`apps/macos/project.yml` の `INFOPLIST_KEY_NSAppleMusicUsageDescription` + `InfoPlist.xcstrings` で対応済み）。
- **TCC と再生履歴**:
  - Apple Music 権限は `MusicAuthorization.request()` 1 つに集約され、macOS では `kTCCServiceMediaLibrary` (`itunescloudd.tcchelper` 経由) として「プライバシーとセキュリティ → メディアとApple Music」に表示される（内訳の個別 ON/OFF は不可）。
  - `ApplicationMusicPlayer.Queue.affectsListeningHistory` (macOS 26.4+) はユーザー方針により既定 `true`（履歴に残す）のまま。
  - `tccutil reset MediaLibrary <bundleID>` は TCC 側のみリセットし、`itunescloudd` 管理の MusicKit 認可は残るため再プロンプト検証には使えない。

## 2. Spotify 対応

- **モデル分岐**:
  - `MediaEntry.provider` (`appleMusic` / `spotify`、後方互換デコードでキー欠落・未知値は `appleMusic`) で分岐。
  - `MediaURLParser` は `open.spotify.com` の album/playlist (`intl-XX`・`?si=` 許容) と `spotify:<kind>:<id>` URI を受理する（ID は base62、track/artist 等は拒否）。
- **再生・監視**:
  - 再生: `tell application "Spotify" to play track "spotify:<kind>:<id>"`（アルバム・プレイリスト両対応）。
  - 停止: AppleScript の `pause`（`is running` ガード付き）。
  - 監視: `player state` + `album of current track` (`PlaybackEngine.spotifyNowPlayingInfo`)。プレイリストは AppleScript からコンテキストが取れないため `activeEntryID` 方式（アプリ内プレイリストと同様）。
  - ポーリングは開いているシェルフに Spotify エントリがあるときだけ実行する（2 秒おきの不要な `osascript` spawn 防止、`ShelfManager.anyOpenShelfHasSpotify`）。
- **メタデータ取得 (`SpotifyCatalogClient`)**:
  - 認証不要。oEmbed (`https://open.spotify.com/oembed?url=<canonical>`) でタイトル + サムネイルを取得し、ページ HTML の `og:description` からアーティスト名を抽出する。
  - `og:description` は `" · "` (U+00B7) 区切り:
    - アルバム: `"Pink Floyd · album · 1973 · 10 songs"` → 先頭セグメント
    - プレイリスト: `"Playlist · Spotify · 50 items · 33.6M saves"` → 先頭が `"Playlist"` なら 2 番目、以外は `"Spotify"`
  - `og` 取得失敗時は `artist = ""` で縮退。`og:title` は装飾付きのため使わず oEmbed を正とする。
  - **必須**: ページ取得は非ブラウザ User-Agent (`curl/8.0`) を使うこと（ブラウザ系 UA には `og` タグ無しの JS シェルが返る）。
  - `og` 解析の純ロジックは `SpotifyPageParser` (`apps/macos/Shared/MediaEntry.swift`、テストターゲットに含む)。
