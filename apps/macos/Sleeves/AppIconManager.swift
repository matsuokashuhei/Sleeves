//
//  AppIconManager.swift
//  Sleeves
//
//  Created by Shuhei Matsuoka on 2026/11/15.
//

import AppKit
import QuartzCore
import os

/// Dockアイコンの差し替え管理。
/// バンドルやFinder上の .app アイコンは一切触らず、実行中プロセスの
/// NSApp.applicationIconImage だけを差し替える。選択はUserDefaultsに
/// 保存し、起動ごとにapplySaved()で再適用する。
/// カスタム画像は Application Support 配下(App Sandbox 互換)に PNG として保存する。
/// ※AppKit(NSApp)を使うためアプリターゲット専用。SleevesTestsにも
///   リンクされるShared/には置けない
@MainActor
enum AppIconManager {

    private static let logger = Logger(
        subsystem: "com.cacheandbuffer.Sleeves", category: "AppIcon")

    /// カスタムアイコンのスロット数(0, 1, 2)
    static let customSlotCount = 3

    /// UserDefaultsの保存キー(プリセットのrawValueまたは"custom-<slot>"を入れる)
    private static let defaultsKey = "appIconID"
    /// カスタムアイコン選択時のUserDefaultsプレフィックス("custom-0"〜"custom-2")
    private static let customSelectionPrefix = "custom-"
    /// 旧単一スロット版のUserDefaults保存値(後方互換でスロット0として扱う)
    private static let legacyCustomSelectionRawValue = "custom"
    /// 旧単一スロット版の保存ファイル名(後方互換でスロット0へ移行する)
    private static let legacyCustomImageFileName = "custom-app-icon.png"

    /// 内蔵プリセット。rawValueがそのままUserDefaultsの保存値になる
    enum AppIconPreset: String, CaseIterable, Identifiable {
        /// バンドルの通常アイコン(nil代入で復帰させる)
        case `default`
        /// レコードジャケットのアイコン(assets/icons/record-N.png)
        case sunburst
        case prism
        case waves
        case portraits

        var id: String { rawValue }

        /// Assets.xcassets内のimageset名。設定画面のサムネイルと
        /// Dockへ適用するNSImageの両方で同じ名前を引く
        var assetName: String {
            switch self {
            // AppIconDefault.imagesetはAppIcon.appiconset/icon_1024px.pngの
            // 複製(appiconsetの中身は名前で引けないため)。デフォルト
            // アイコンのデザインを変えたらこのPNGも再コピーすること
            case .default: "AppIconDefault"
            case .sunburst: "AppIconRecord1"
            case .prism: "AppIconRecord2"
            case .waves: "AppIconRecord3"
            case .portraits: "AppIconRecord4"
            }
        }

        /// 設定画面のサムネイル下に出すラベル
        /// (Localizable.xcstringsのキー名そのまま)
        var label: String {
            switch self {
            case .default: "Default"
            case .sunburst: "Sunburst"
            case .prism: "Prism"
            case .waves: "Waves"
            case .portraits: "Portraits"
            }
        }
    }

    /// Dockアイコンの選択状態(内蔵プリセットまたはユーザー設定のカスタムスロット)
    enum AppIconSelection: Equatable {
        case preset(AppIconPreset)
        case custom(Int)

        var rawValue: String {
            switch self {
            case .preset(let preset): preset.rawValue
            case .custom(let slot): "\(AppIconManager.customSelectionPrefix)\(slot)"
            }
        }
    }

    /// カスタム画像取り込み時のエラー
    enum CustomIconError: Error {
        case invalidSlot
        case fileReadFailed(Error)
        case invalidImageData
        case saveFailed(Error)
    }

    /// 指定スロットのカスタム画像保存先パス
    static func customImageURL(slot: Int) -> URL {
        ShelfStore.baseDirectory.appendingPathComponent("custom-app-icon-\(slot).png")
    }

    private static var legacyCustomImageURL: URL {
        ShelfStore.baseDirectory.appendingPathComponent(legacyCustomImageFileName)
    }

    private static func isValidSlot(_ slot: Int) -> Bool {
        (0..<customSlotCount).contains(slot)
    }

    /// 旧単一スロット版の custom-app-icon.png が残っていてスロット0が無い場合、
    /// custom-app-icon-0.png へ移行する。移行失敗時はログを出して続行する
    private static func migrateLegacyCustomImageIfNeeded() {
        let legacyURL = legacyCustomImageURL
        let slot0URL = customImageURL(slot: 0)
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyURL.path),
              !fm.fileExists(atPath: slot0URL.path)
        else { return }
        do {
            try fm.moveItem(at: legacyURL, to: slot0URL)
            logger.notice("app icon legacy migration OK: moved \(legacyURL.lastPathComponent, privacy: .public) to \(slot0URL.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("app icon legacy migration FAILED: \(String(describing: error), privacy: .public)")
        }
    }

    /// 保存済みの選択。未設定・未知値・範囲外スロットは .preset(.default) にフォールバックする。
    /// 旧値 "custom" は .custom(0) として解釈する。ファイル欠損・破損時も安全に .preset(.default) へ倒す
    static var saved: AppIconSelection {
        migrateLegacyCustomImageIfNeeded()
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else {
            return .preset(.default)
        }
        if raw == legacyCustomSelectionRawValue {
            if loadCustomImage(slot: 0) != nil {
                return .custom(0)
            }
            logger.error("app icon saved fallback: legacy custom image missing or unreadable for slot=0, falling back to default")
            return .preset(.default)
        }
        if raw.hasPrefix(customSelectionPrefix) {
            let suffix = raw.dropFirst(customSelectionPrefix.count)
            if let slot = Int(suffix), isValidSlot(slot) {
                if loadCustomImage(slot: slot) != nil {
                    return .custom(slot)
                }
                logger.error("app icon saved fallback: custom image missing or unreadable for slot=\(slot, privacy: .public), falling back to default")
                return .preset(.default)
            }
            logger.error("app icon saved fallback: invalid custom appIconID=\(raw, privacy: .public), falling back to default")
            return .preset(.default)
        }
        if let preset = AppIconPreset(rawValue: raw) {
            return .preset(preset)
        }
        logger.error("app icon saved fallback: unknown appIconID=\(raw, privacy: .public), falling back to default")
        return .preset(.default)
    }

    /// 指定スロットの保存済みカスタム画像を読み込む。範囲外・未保存・破損時は nil
    static func loadCustomImage(slot: Int) -> NSImage? {
        guard isValidSlot(slot) else {
            logger.error("app icon loadCustomImage FAILED: invalid slot=\(slot, privacy: .public)")
            return nil
        }
        if slot == 0 {
            migrateLegacyCustomImageIfNeeded()
        }
        let url = customImageURL(slot: slot)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data),
                  image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil
            else {
                logger.error("app icon loadCustomImage FAILED: corrupt image data slot=\(slot, privacy: .public) path=\(url.path, privacy: .public)")
                return nil
            }
            return image
        } catch {
            logger.error("app icon loadCustomImage FAILED: slot=\(slot, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// 全スロット(長さ customSlotCount)の保存済みカスタム画像を読み込む
    static func loadAllCustomImages() -> [NSImage?] {
        migrateLegacyCustomImageIfNeeded()
        return (0..<customSlotCount).map { loadCustomImage(slot: $0) }
    }

    /// URL から画像を読み込んで指定スロットのカスタムアイコンとして取り込み・適用する。
    /// App Sandbox の security-scoped resource に対応するため開始/終了を必ず対で呼ぶ
    static func importCustomImage(from url: URL, slot: Int) -> Result<NSImage, CustomIconError> {
        logger.notice("app icon import from URL start: slot=\(slot, privacy: .public) file=\(url.lastPathComponent, privacy: .public)")
        guard isValidSlot(slot) else {
            logger.error("app icon import from URL FAILED: invalid slot=\(slot, privacy: .public)")
            return .failure(.invalidSlot)
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("app icon import from URL FAILED (read): slot=\(slot, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return .failure(.fileReadFailed(error))
        }
        return importCustomImage(data: data, slot: slot)
    }

    /// 画像データを 824×824 PNG に正規化し、合成検証後に指定スロットへ保存・適用・永続化する。
    /// 途中で失敗した場合は既存の保存ファイル・現行アイコン・UserDefaults を一切変更しない
    static func importCustomImage(data: Data, slot: Int) -> Result<NSImage, CustomIconError> {
        logger.notice("app icon import from data start: slot=\(slot, privacy: .public) bytes=\(data.count, privacy: .public)")
        guard isValidSlot(slot) else {
            logger.error("app icon import FAILED: invalid slot=\(slot, privacy: .public)")
            return .failure(.invalidSlot)
        }
        guard let pngData = AppIconImageProcessor.normalizeSquarePNG(
            from: data, targetSize: AppIconImageProcessor.defaultTargetSize
        ) else {
            logger.error("app icon import FAILED: image normalization returned nil slot=\(slot, privacy: .public)")
            return .failure(.invalidImageData)
        }
        guard let image = NSImage(data: pngData),
              let composited = compositeDockIcon(image)
        else {
            logger.error("app icon import FAILED: NSImage or dock compositing failed slot=\(slot, privacy: .public)")
            return .failure(.invalidImageData)
        }

        let directory = ShelfStore.baseDirectory
        let destination = customImageURL(slot: slot)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: destination, options: .atomic)
        } catch {
            logger.error("app icon import FAILED (save): slot=\(slot, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return .failure(.saveFailed(error))
        }

        NSApp.applicationIconImage = composited
        UserDefaults.standard.set(AppIconSelection.custom(slot).rawValue, forKey: defaultsKey)
        logger.notice("app icon import OK: slot=\(slot, privacy: .public) saved bytes=\(pngData.count, privacy: .public) path=\(destination.path, privacy: .public)")
        return .success(image)
    }

    /// 指定スロットの保存済みカスタム画像を削除する(ファイルが無くてもエラーにしない)。
    /// 現在そのスロットが選択中だった場合は .preset(.default) へ復帰させる
    static func removeCustomImage(slot: Int) {
        guard isValidSlot(slot) else {
            logger.error("app icon removeCustomImage FAILED: invalid slot=\(slot, privacy: .public)")
            return
        }
        let url = customImageURL(slot: slot)
        logger.notice("app icon removeCustomImage start: slot=\(slot, privacy: .public) path=\(url.path, privacy: .public)")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                logger.notice("app icon removeCustomImage: file removed slot=\(slot, privacy: .public)")
            } catch {
                logger.error("app icon removeCustomImage FAILED: slot=\(slot, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        } else {
            logger.notice("app icon removeCustomImage: no file to remove slot=\(slot, privacy: .public)")
        }

        let currentRaw = UserDefaults.standard.string(forKey: defaultsKey)
        let isActiveSlot = currentRaw == AppIconSelection.custom(slot).rawValue
            || (slot == 0 && currentRaw == legacyCustomSelectionRawValue)
        if isActiveSlot {
            NSApp.applicationIconImage = nil
            UserDefaults.standard.set(AppIconPreset.default.rawValue, forKey: defaultsKey)
            logger.notice("app icon removeCustomImage: reverted active custom slot=\(slot, privacy: .public) to default")
        }
    }

    /// アイコンを適用する。.preset(.default) のときは nil を代入してバンドル
    /// アイコンへ復帰させる(applicationIconImage の nil は「カスタム
    /// 画像なし=既定アイコン」という NSApplication の規約)。
    /// 戻り値は適用の成否(画像が読めなかったとき false)
    @discardableResult
    static func apply(_ selection: AppIconSelection) -> Bool {
        logger.notice("app icon apply start: \(selection.rawValue, privacy: .public)")
        switch selection {
        case .preset(.default):
            NSApp.applicationIconImage = nil
            logger.notice("app icon apply OK: default (bundle icon)")
            return true
        case .preset(let preset):
            guard let image = NSImage(named: preset.assetName) else {
                // 読めない画像でnil相当を代入するとアイコンが消えて見える
                // ため、現行のアイコンを維持して失敗だけ記録する
                logger.error("app icon apply FAILED: image not found asset=\(preset.assetName, privacy: .public)")
                return false
            }
            // 素材は全面ベタ塗りの正方形PNG(Settingsサムネイルと共用のため
            // 素材自体は触らない)。バンドルアイコンと同じ見え方になるよう、
            // 1024キャンバス中央の824x824タイルへsquircleクリップで合成する
            guard let composited = compositeDockIcon(image) else {
                // 合成失敗時も現行アイコンを維持する(代入しない)
                logger.error("app icon apply FAILED: compositing failed preset=\(preset.rawValue, privacy: .public)")
                return false
            }
            NSApp.applicationIconImage = composited
            logger.notice("app icon apply OK: \(preset.rawValue, privacy: .public)")
            return true
        case .custom(let slot):
            guard isValidSlot(slot) else {
                logger.error("app icon apply FAILED: invalid custom slot=\(slot, privacy: .public)")
                return false
            }
            guard let image = loadCustomImage(slot: slot) else {
                logger.error("app icon apply FAILED: custom image unavailable slot=\(slot, privacy: .public)")
                return false
            }
            guard let composited = compositeDockIcon(image) else {
                logger.error("app icon apply FAILED: compositing failed custom slot=\(slot, privacy: .public)")
                return false
            }
            NSApp.applicationIconImage = composited
            logger.notice("app icon apply OK: custom slot=\(slot, privacy: .public)")
            return true
        }
    }

    // MARK: - squircle合成

    /// 出力キャンバスの1辺(macOSアイコンの標準)
    private static let iconCanvasSize: CGFloat = 1024
    /// ジャケットを描く中央タイルの1辺(バンドルアイコンと同じ占有率)
    private static let iconTileSize: CGFloat = 824
    /// squircleの角半径(タイル1辺の約22.4%。設定画面のサムネイルと同じ比率)
    private static let iconCornerRadius: CGFloat = 185

    /// 全面正方形のジャケット画像を、1024x1024キャンバス中央の
    /// 824x824タイルへmacOS連続角丸(squircle)でクリップして描き、
    /// 外側を透明にしたNSImageを返す。失敗時はnil
    /// (呼び出し側が現行アイコンを維持する)
    private static func compositeDockIcon(_ source: NSImage) -> NSImage? {
        guard let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.error("app icon composite FAILED: CGImage取得不可")
            return nil
        }
        let canvas = Int(iconCanvasSize)
        let margin = (iconCanvasSize - iconTileSize) / 2
        let tileRect = CGRect(x: margin, y: margin, width: iconTileSize, height: iconTileSize)

        // 1) squircleマスク生成: cornerCurve=.continuous のCALayerを
        //    グレースケール(アルファ無し)コンテキストに白で描き、
        //    輝度マスクとして使う。角が円弧ではなく連続曲率になるのが要点
        guard let maskCtx = CGContext(
            data: nil,
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            logger.error("app icon composite FAILED: maskコンテキスト作成不可")
            return nil
        }
        let container = CALayer()
        container.bounds = CGRect(
            x: 0, y: 0, width: iconCanvasSize, height: iconCanvasSize)
        let squircle = CALayer()
        squircle.frame = tileRect
        squircle.cornerRadius = iconCornerRadius
        squircle.cornerCurve = .continuous
        // マスクは輝度で評価される(白=表示、黒=非表示)ので白で塗る
        squircle.backgroundColor = CGColor(gray: 1.0, alpha: 1.0)
        container.addSublayer(squircle)
        // render(in:)はレイヤ座標(左上原点)をそのまま描くのでCGContext上は
        // 上下反転するが、squircleは天地対称かつ中央配置なので結果は同じ
        container.render(in: maskCtx)
        guard let mask = maskCtx.makeImage() else {
            logger.error("app icon composite FAILED: mask画像生成不可")
            return nil
        }

        // 2) RGBA出力コンテキストへマスククリップしてジャケットを描く
        guard let outCtx = CGContext(
            data: nil,
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            logger.error("app icon composite FAILED: 出力コンテキスト作成不可")
            return nil
        }
        // マスクはキャンバスと同じ1024x1024でsquircleがタイル位置に
        // 描かれている。clip(to:mask:)はrectいっぱいにマスクを引き伸ばす
        // ため、ここにtileRectを渡すとsquircleが縮んでしまう。必ず
        // キャンバス全体のrectを渡すこと
        outCtx.clip(to: CGRect(x: 0, y: 0, width: iconCanvasSize, height: iconCanvasSize), mask: mask)
        // CGImage→CGContext→CGImageの往復では向きは保たれる
        // (UIKitの反転コンテキストに混ぜるときだけ上下が裏返る。
        //   実測で確認済み: CTMを反転するとジャケットが逆さまになる)
        // 素材は360pxと小さいので824pxへの拡大は.high補間にする
        outCtx.interpolationQuality = .high
        outCtx.draw(sourceCG, in: tileRect)
        guard let outCG = outCtx.makeImage() else {
            logger.error("app icon composite FAILED: 出力画像生成不可")
            return nil
        }
        logger.notice("app icon composite OK: squircle tile=\(Int(iconTileSize), privacy: .public) radius=\(Int(iconCornerRadius), privacy: .public)")
        return NSImage(
            cgImage: outCG,
            size: NSSize(width: iconCanvasSize, height: iconCanvasSize))
    }

    /// 選択を適用し、成功したときだけ永続化する(設定画面からの操作経路)。
    /// 失敗しても保存しないのは、「選択表示と実アイコンが食い違う
    /// 状態」を起動のたびに再生しないため
    static func select(_ selection: AppIconSelection) {
        logger.notice("app icon select: \(selection.rawValue, privacy: .public)")
        if apply(selection) {
            UserDefaults.standard.set(selection.rawValue, forKey: defaultsKey)
        }
    }

    /// 保存値を読んで適用する。起動時にAppDelegateから呼ぶ
    /// (App.initの時点ではNSAppの準備が保証されないため
    ///  applicationDidFinishLaunching経由にしている)
    static func applySaved() {
        let selection = saved
        logger.notice("app icon applySaved: \(selection.rawValue, privacy: .public)")
        apply(selection)
    }
}
