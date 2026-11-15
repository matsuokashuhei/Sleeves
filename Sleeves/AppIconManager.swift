//
//  AppIconManager.swift
//  Sleeves
//
//  Created by Shuhei Matsuoka on 2026/11/15.
//

import AppKit
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
        NSApp.applicationIconImage = image
        logger.notice("app icon apply OK: \(preset.rawValue, privacy: .public)")
        return true
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
