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
/// ※AppKit(NSApp)を使うためアプリターゲット専用。SleevesTestsにも
///   リンクされるShared/には置けない
@MainActor
enum AppIconManager {

    private static let logger = Logger(
        subsystem: "com.cacheandbuffer.Sleeves", category: "AppIcon")

    /// UserDefaultsの保存キー(選択したプリセットのrawValueを入れる)
    private static let defaultsKey = "appIconID"

    /// 内蔵プリセット。rawValueがそのままUserDefaultsの保存値になる
    enum AppIconPreset: String, CaseIterable, Identifiable {
        /// バンドルの通常アイコン(nil代入で復帰させる)
        case `default`
        /// レコードジャケットのアイコン(record-icons/record-N.png)
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

    /// 保存済みの選択。未設定・未知値は.defaultにフォールバックする
    /// (プリセットの廃止や手編集で壊れた値が残っていても起動を妨げない)
    static var saved: AppIconPreset {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let preset = AppIconPreset(rawValue: raw)
        else { return .default }
        return preset
    }

    /// アイコンを適用する。.defaultのときはnilを代入してバンドル
    /// アイコンへ復帰させる(applicationIconImageのnilは「カスタム
    /// 画像なし=既定アイコン」というNSApplicationの規約)。
    /// 戻り値は適用の成否(画像が読めなかったときfalse)
    @discardableResult
    static func apply(_ preset: AppIconPreset) -> Bool {
        logger.notice("app icon apply start: \(preset.rawValue, privacy: .public)")
        if preset == .default {
            NSApp.applicationIconImage = nil
            logger.notice("app icon apply OK: default (bundle icon)")
            return true
        }
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
    static func select(_ preset: AppIconPreset) {
        logger.notice("app icon select: \(preset.rawValue, privacy: .public)")
        if apply(preset) {
            UserDefaults.standard.set(preset.rawValue, forKey: defaultsKey)
        }
    }

    /// 保存値を読んで適用する。起動時にAppDelegateから呼ぶ
    /// (App.initの時点ではNSAppの準備が保証されないため
    ///  applicationDidFinishLaunching経由にしている)
    static func applySaved() {
        let preset = saved
        logger.notice("app icon applySaved: \(preset.rawValue, privacy: .public)")
        apply(preset)
    }
}
