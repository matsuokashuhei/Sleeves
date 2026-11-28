#if DEBUG
import Foundation
import os

/// 展示モード (Showcase Mode) の状態管理シングルトン（Debug ビルド専用）。
/// UserDefaults に状態を永続化し、変更時に開いている全シェルフへ即座に反映する。
/// Release ビルドでは `#if DEBUG` により完全に除外される。
@MainActor
final class ShowcaseMode: ObservableObject {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "Showcase")

    static let shared = ShowcaseMode()

    static let userDefaultsKey = "com.cacheandbuffer.Sleeves.showcaseMode"

    /// 設定画面ピッカー用のモード表現
    enum Mode: String, CaseIterable, Identifiable {
        case production
        case showcase

        var id: String { rawValue }
    }

    /// 現在展示モードが有効か
    @Published private(set) var isEnabled: Bool

    private init() {
        let saved = UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
        self.isEnabled = saved
        Self.logger.notice("showcase mode initialized: enabled=\(saved, privacy: .public)")
    }

    var mode: Mode {
        get { isEnabled ? .showcase : .production }
        set { setEnabled(newValue == .showcase) }
    }

    /// 展示モードを切り替え、UserDefaults に保存し、全シェルフへ反映する。
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            Self.logger.debug("showcase mode unchanged: enabled=\(enabled, privacy: .public)")
            return
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.userDefaultsKey)
        Self.logger.notice("showcase mode changed: enabled=\(enabled, privacy: .public)")
        ShelfManager.shared.applyShowcaseModeChange(enabled: enabled)
    }
}
#endif
