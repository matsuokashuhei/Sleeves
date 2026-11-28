//
//  SettingsView.swift
//  Sleeves
//
//  Created by Shuhei Matsuoka on 2026/10/18.
//

import SwiftUI
import UniformTypeIdentifiers
import os

/// 設定画面(シェルフ右上のツールバー→「Settings…」から開く)。
/// シェルフの表示設定のみ扱う。アルバム/プレイリストの追加は
/// シェルフへのドロップで行う。
/// 表示設定の編集対象は「最後にキーになったシェルフウィンドウ」
/// (ShelfManager.focusedStore)。言語だけはアプリ全体共通。
struct SettingsView: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    @ObservedObject private var manager = ShelfManager.shared
    /// 言語変更後の再起動促しアラート表示フラグ
    @State private var showRestartAlert = false
    /// サイドバーで選択中のペイン
    @State private var selectedPane: SettingsPane = .general

    /// 編集対象のシェルフ(最後にフォーカスしたウィンドウ)。
    /// まだ一度もシェルフがキーになっていなければnil
    private var store: ShelfStore? { manager.focusedStore }

    /// 言語選択肢のタグ値。"system"はOS設定に従う(AppleLanguages未設定)
    private static let languageCodes = ["en", "ja", "es", "zh-Hans", "ko", "fr", "de"]

    /// 設定ペイン。macOSのシステム設定と同じく、左のサイドバーで
    /// カテゴリを選び右のペインにその設定を出す
    private enum SettingsPane: String, CaseIterable, Identifiable {
        case general, sleeves, shelf, wall, arrangement
        var id: Self { self }

        /// サイドバー表示名とペインのナビゲーションタイトル。
        /// キーはプラグイン表示名と同じなので既存の翻訳が効く
        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .sleeves: "Sleeves"
            case .shelf: "Shelf"
            case .wall: "Wall"
            case .arrangement: "Arrangement"
            }
        }

        /// macOSの設定サイドバーに合わせたカテゴリ別アイコン。
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .sleeves: "record.circle"
            case .wall: "rectangle.inset.filled"
            case .shelf: "square.grid.2x2"
            case .arrangement: "hand.raised"
            }
        }
    }

    var body: some View {
        // macOSのシステム設定と同じサイドバー+ペイン構成。
        // 表示設定の編集対象は「最後にキーになったシェルフウィンドウ」
        // (ShelfManager.focusedStore)。監視するのはstore側
        // (manager.focusedStoreの参照変更だけではsettingsの更新で
        // 再描画されないため)、サブビューに切り出して@ObservedObjectで購読する
        // columnVisibilityを定数バインドしてサイドバーの折りたたみを
        // 禁止(システム設定と同じ)。ツールバーのサイドバートグル
        // ボタンはremoveSidebarToggleButton()でAppKit側から除去する
        // (.toolbar(removing: .sidebarToggle)はこの構成では効かない)
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .foregroundStyle(.white)
                }
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            // ウィンドウは固定サイズ。収まらないペイン(プラグインが多い
            // Sleeves等)は縦スクロールにする(macOSのForm自体は
            // スクロールしないので外側をScrollViewにする)
            ScrollView {
                Form {
                    switch selectedPane {
                    case .general:
                        Section {
                            languagePicker
                        }
                        // Dockアイコンはアプリ全体共通の設定なので
                        // store(フォーカス中シェルフ)が無くても出す
                        Section {
                            AppIconPicker()
                        }
                        #if DEBUG
                        // 展示モード切替(Debugビルド専用・アプリ全体共通)
                        Section {
                            ShowcaseModePicker()
                        }
                        #endif
                        // 削除確認はアプリ全体の振る舞いに近いので
                        // Generalに置く(編集対象は他の表示設定と同じく
                        // フォーカス中のシェルフ)
                        if let store {
                            Section {
                                DeleteConfirmationToggle(store: store)
                            }
                        } else {
                            unfocusedShelfSection
                        }
                    case .sleeves:
                        if let store {
                            // カテゴリの先頭ボックス(固定項目)の直後に、
                            // プラグインを1つ=1ボックスのSectionとして並べる。
                            // プラグインのボックス内は先頭行が有効トグル
                            // (太字タイトル)、以降の行がパラメータ調整UIという、
                            // macOSのシステム設定と同じグループ構造
                            // (例: Spotlightの「Results from Clipboard」)
                            Section {
                                ArtworkSizePicker(store: store)
                            }
                            ShelfEffectSettings(store: store, category: .record)
                        } else {
                            unfocusedShelfSection
                        }
                    case .shelf:
                        if let store {
                            Section {
                                ShelfPickers(store: store)
                                SpacingSlider(store: store,
                                              title: "Shelf Spacing",
                                              range: ShelfSettings.rowSpacingRange,
                                              spacing: \.rowSpacing)
                                SpacingSlider(store: store,
                                              title: "Record Spacing",
                                              range: ShelfSettings.columnSpacingRange,
                                              spacing: \.columnSpacing)
                            }
                            ShelfEffectSettings(store: store, category: .shelf)
                        } else {
                            unfocusedShelfSection
                        }
                    case .wall:
                        if let store {
                            ShelfEffectSettings(store: store, category: .wall)
                        } else {
                            unfocusedShelfSection
                        }
                    case .arrangement:
                        // 「飾り方」ペインは2カテゴリを束ねる1:Nマッピング:
                        // .placement(Lean Depth=置き方)→.lighting
                        // (Ambient Light/Sleeve Gloss=光の当たり方)の順
                        if let store {
                            ShelfEffectSettings(store: store, category: .placement)
                            ShelfEffectSettings(store: store, category: .lighting)
                        } else {
                            unfocusedShelfSection
                        }
                    }
                }
                .formStyle(.grouped)
                .padding(8)
            }
            // ペイン切替でスクロール位置を引き継がないよう、
            // ペインごとにScrollViewを作り直す
            .id(selectedPane)
            .navigationTitle(selectedPane.title)
        }
        // ウィンドウサイズは固定(システム設定アプリと同じく
        // ペイン切替でサイズが変わらない)。min=maxのcontentSizeで
        // リサイズ不可になる
        .frame(width: 675, height: 480)
        .onChange(of: selectedPane) { _, newValue in
            Self.logger.notice("settings pane selected: \(newValue.rawValue, privacy: .public)")
            scheduleSidebarToggleRemoval()
        }
        .onAppear {
            Self.logger.notice("settings window shown")
            scheduleSidebarToggleRemoval()
        }
        .alert(
            "Restart Required",
            isPresented: $showRestartAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The new language will take effect after you restart Sleeves.")
        }
    }

    // MARK: - 表示設定

    /// Generalペインの言語ピッカー
    private var languagePicker: some View {
        Picker("Language", selection: languageSelection) {
            Text("System").tag("system")
            ForEach(Self.languageCodes, id: \.self) { code in
                Text(languageName(for: code)).tag(code)
            }
        }
    }

    /// フォーカス中シェルフが無いとき表示設定ペインに出す案内
    /// (設定画面をシェルフのツールバー以外から開いた経路用)
    private var unfocusedShelfSection: some View {
        Section {
            Text("Focus a shelf window to edit these settings.")
                .foregroundStyle(.secondary)
        }
    }

    /// SwiftUIがツールバーを組み直してトグルを復活させることがある
    /// (直後の再dumpでitemsに戻って来るのを実測)ため、即時+遅延の
    /// 2パスで除去を試みる
    @MainActor
    private func scheduleSidebarToggleRemoval() {
        DispatchQueue.main.async { removeSidebarToggleButton() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            removeSidebarToggleButton()
        }
    }

    /// NavigationSplitViewがツールバーへ自動追加するサイドバートグル
    /// ボタンを消す。`.toolbar(removing: .sidebarToggle)`はこの構成
    /// (Windowシーン+固定columnVisibility)では効かなかったため、
    /// AppKit側からツールバーアイテムを直接除去する
    /// (columnVisibilityは定数なので残しても押すだけ無駄なボタン)。
    /// 対象は設定ウィンドウ(Window id="settings")だけに絞る
    @MainActor
    private func removeSidebarToggleButton() {
        for window in NSApp.windows where window.identifier?.rawValue == "settings" {
            guard let toolbar = window.toolbar else { continue }
            Self.logger.notice("settings: toolbar items of window '\(window.identifier?.rawValue ?? "nil", privacy: .public)': \(toolbar.items.map(\.itemIdentifier.rawValue), privacy: .public)")
            while let index = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == .toggleSidebar
                    || $0.itemIdentifier.rawValue.localizedCaseInsensitiveContains("toggleSidebar")
            }) {
                Self.logger.notice("settings: removing sidebar toggle toolbar item '\(toolbar.items[index].itemIdentifier.rawValue, privacy: .public)'")
                toolbar.removeItem(at: index)
            }
        }
    }

    /// 言語名をその言語自体で表示する(autonym。英語なら"English")
    private func languageName(for code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
    }

    /// 現在の言語設定のタグ値を返す。AppleLanguages未設定なら"system"。
    /// standard.stringArrayはNSGlobalDomainまでフォールバックして
    /// OSの言語一覧を拾ってしまう(未設定なのにピッカーが空選択になる)
    /// ため、アプリ固有ドメインだけ読む
    private static var currentLanguageCode: String {
        let domain = UserDefaults.standard.persistentDomain(
            forName: Bundle.main.bundleIdentifier ?? "com.cacheandbuffer.Sleeves"
        )
        return (domain?["AppleLanguages"] as? [String])?.first ?? "system"
    }

    /// AppleLanguagesに言語コードを書き込んでアプリの表示言語を切り替える。
    /// "system"選択時はキーごと消してOS設定に戻す。反映は次回起動から。
    /// Pickerはポップアップを開いた時点でも現在値でsetを呼ぶため、
    /// 値が変わっていなければ書き込みもアラートもしない
    /// (開くだけで再起動要求が出るバグの対処)
    private var languageSelection: Binding<String> {
        Binding(
            get: { Self.currentLanguageCode },
            set: { newValue in
                guard newValue != Self.currentLanguageCode else {
                    Self.logger.notice("settings: language picker set with unchanged value \(newValue, privacy: .public)")
                    return
                }
                Self.logger.notice("settings: language picker changed to \(newValue, privacy: .public)")
                if newValue == "system" {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                }
                showRestartAlert = true
            }
        )
    }

}

/// 棚セクションのピッカー群(構造スタイル・列数・行数)。
/// @ObservedObjectでstoreを購読するためにSettingsViewから切り出した
/// (SettingsViewが見るのはmanager.focusedStoreの参照だけなので、
///  settingsが変わっても再描画されずピッカー表示が古いままになる)
private struct ShelfPickers: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    @ObservedObject var store: ShelfStore

    var body: some View {
        Picker("Style", selection: styleSelection) {
            ForEach(ShelfSettings.ShelfStyle.allCases) { style in
                Text(LocalizedStringKey(style.label)).tag(style)
            }
        }
        .pickerStyle(.segmented)
        Picker("Columns", selection: columnsSelection) {
            ForEach(1...ShelfSettings.maxDimension, id: \.self) { n in
                Text("\(n) columns").tag(n)
            }
        }
        Picker("Rows", selection: rowsSelection) {
            ForEach(1...ShelfSettings.maxDimension, id: \.self) { n in
                Text("\(n) rows").tag(n)
            }
        }
    }

    private var styleSelection: Binding<ShelfSettings.ShelfStyle> {
        Binding(
            get: { store.settings.shelfStyle },
            set: { newValue in
                Self.logger.notice("settings: shelf style picker changed to \(newValue.rawValue, privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
                updateDisplaySettings { $0.shelfStyle = newValue }
            }
        )
    }

    private var columnsSelection: Binding<Int> {
        Binding(
            get: { store.settings.columns },
            set: { newValue in
                Self.logger.notice("settings: columns picker changed to \(newValue, privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
                updateDisplaySettings { $0.columns = newValue }
            }
        )
    }

    private var rowsSelection: Binding<Int> {
        Binding(
            get: { store.settings.rows },
            set: { newValue in
                Self.logger.notice("settings: rows picker changed to \(newValue, privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
                updateDisplaySettings { $0.rows = newValue }
            }
        )
    }

    /// 列数/行数/スタイルの変更をフォーカス中のシェルフの設定に反映する。
    /// 新規インスタンスを組み立てず現行settingsをコピーして変えるので、
    /// 後から増えたフィールド(間隔等)が黙って既定値に戻ることはない。
    /// 縮小で非表示になった再生中プレイリストは停止UIが消えるためここで止める。
    private func updateDisplaySettings(mutate: (inout ShelfSettings) -> Void) {
        var s = store.settings
        mutate(&s)
        store.updateSettings(s)
        PlaybackMonitor.shared.stopIfActiveEntryHidden()
    }
}

/// レコードセクションのアートワークサイズピッカー。
/// ShelfPickersと同じく@ObservedObjectでstoreを購読するサブビュー
private struct ArtworkSizePicker: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    @ObservedObject var store: ShelfStore

    var body: some View {
        Picker("Artwork Size", selection: artworkSizeSelection) {
            ForEach(ShelfSettings.ArtworkSize.allCases) { size in
                Text(size.label).tag(size)
            }
        }
        .pickerStyle(.segmented)
    }

    private var artworkSizeSelection: Binding<ShelfSettings.ArtworkSize> {
        Binding(
            get: { store.settings.artworkSize },
            set: { newValue in
                Self.logger.notice("settings: artwork size picker changed to \(newValue.rawValue, privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
                var s = store.settings
                s.artworkSize = newValue
                store.updateSettings(s)
                PlaybackMonitor.shared.stopIfActiveEntryHidden()
            }
        )
    }
}

/// レコード削除時の確認ダイアログ有無トグル。
/// ArtworkSizePickerと同じく@ObservedObjectでstoreを購読する
/// サブビュー(SettingsView本体はmanager.focusedStoreの参照しか
/// 監視しないため、settingsの変更で再描画されない)
private struct DeleteConfirmationToggle: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    @ObservedObject var store: ShelfStore

    var body: some View {
        Toggle("Delete Confirmation", isOn: confirmDeleteBinding)
    }

    private var confirmDeleteBinding: Binding<Bool> {
        Binding(
            get: { store.settings.confirmDelete },
            set: { newValue in
                Self.logger.notice("settings: delete confirmation toggle changed to \(newValue, privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
                var s = store.settings
                s.confirmDelete = newValue
                store.updateSettings(s)
            }
        )
    }
}

#if DEBUG
/// 製品モード / 展示モードの切替ピッカー（Debug ビルド専用）。
/// アプリ全体共通の設定で、変更は UserDefaults に保存され開いている全シェルフへ即座に反映される。
private struct ShowcaseModePicker: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    @ObservedObject private var showcaseMode = ShowcaseMode.shared

    var body: some View {
        Picker("Mode", selection: modeSelection) {
            Text("Production").tag(ShowcaseMode.Mode.production)
            Text("Showcase").tag(ShowcaseMode.Mode.showcase)
        }
        .pickerStyle(.segmented)
    }

    private var modeSelection: Binding<ShowcaseMode.Mode> {
        Binding(
            get: { showcaseMode.mode },
            set: { newValue in
                Self.logger.notice("settings: mode picker changed to \(newValue.rawValue, privacy: .public)")
                showcaseMode.mode = newValue
            }
        )
    }
}
#endif

/// グリッド間隔のスライダー1本。spacingのキーで対象フィールドを
/// 指定する(rowSpacing/columnSpacingとも棚セクション。
///  columnSpacingは飾り方ペイン解体に伴い棚セクションへ移設)。
/// 外周の余白は独立した設定ではなく間隔から導出される
/// (edgePadding=columnSpacing、topPadding=max(4,rowSpacing)、
///  bottomPadding=rowSpacing。ShelfSettings参照)。
/// 値の変更はupdateSettingsTransientでメモリ上だけ反映(グリッドと
/// windowResizability(.contentSize)経由でウィンドウへライブ反映)し、
/// settings.jsonへの永続化+変更ログはPluginSliderRowと同じデバウンスで
/// commitSettingsにまとめる
private struct SpacingSlider: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    /// これだけ値が変わらなければ編集完了とみなす無入力時間
    /// (PluginSliderRowと同じ)
    private static let commitDelay: Duration = .milliseconds(400)

    @ObservedObject var store: ShelfStore
    let title: LocalizedStringKey
    let range: ClosedRange<Double>
    /// ShelfSettingsの間隔フィールドを指すキー
    let spacing: WritableKeyPath<ShelfSettings, Double>
    /// デバウンス中のコミットTask。連続変更のたびに張り替える
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        Slider(value: spacingBinding, in: range, step: 1) {
            Text(title)
        }
        // 設定画面が閉じる時点でtransientな変更が残っていたら即確定する
        .onDisappear {
            commitTask?.cancel()
            store.commitSettings()
        }
    }

    private var spacingBinding: Binding<Double> {
        Binding(
            get: { store.settings[keyPath: spacing] },
            set: { newValue in
                var s = store.settings
                s[keyPath: spacing] = newValue
                store.updateSettingsTransient(s)
                scheduleCommit()
            }
        )
    }

    /// 無入力commitDelay後にsettingsを永続化してコミットログを出す。
    /// 連続変更のたびに延期されるので、ドラッグ中は書き込まれない
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            commitTask = nil
            store.commitSettings()
            Self.logger.notice("settings: spacing committed \(self.spacingLabel, privacy: .public)=\(self.store.settings[keyPath: self.spacing], privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
        }
    }

    /// ログ用のフィールド名(keyPathの文字列表現は読みにくいので手動で対応)
    private var spacingLabel: String {
        spacing == \.rowSpacing ? "rowSpacing" : "columnSpacing"
    }
}

/// エフェクトプラグインの設定ボックス群(レジストリ列挙)。
/// 各プラグイン = 1つのSection(独立したグループボックス)で、
/// 先頭行が有効トグル(太字タイトル)、以降の行がパラメータ調整UI
/// (スライダー等)。canDisable=falseのプラグイン(壁等)は
/// トグル行を出さずパラメータ行のみ。パラメータ行は常時表示し、
/// プラグイン無効時は
/// .disabledで標準の選択不可表現(グレー・操作不可)にする
/// — システム設定の「Spotlight > Results from Clipboard」と同じ構造。
/// categoryで「レコード」「壁」「棚」「照明」「レコードの置き方」
/// のどのセクションに属するかを絞る(セクション内の順序は
/// レジストリ順=適用順)。「飾り方」ペインはplacementとlightingの
/// 2カテゴリ分を並べて表示する(ペイン:カテゴリ=1:N)。
/// ShelfPickersと同じく、store.settingsの更新で再描画されるよう
/// @ObservedObjectでstoreを購読するサブビューに切り出してある。
/// 変更はstore.updateSettingsでフォーカス中シェルフへ即時反映・永続化。
private struct ShelfEffectSettings: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    @ObservedObject var store: ShelfStore
    /// このセクションに表示するプラグインの分類
    let category: ShelfPluginCategory

    var body: some View {
        // レジストリ順=適用順=セクション内の表示順(決定論的)。
        // 構造プラグインは選択中のスタイルのものだけ列挙する
        // (非選択側はレジストリでもresolveされないので、
        //  トグルを出しても見た目に効かず混乱するだけ)
        ForEach(ShelfPluginRegistry.all.filter {
            $0.category == category
                && ($0.shelfStyle == nil || $0.shelfStyle == store.settings.shelfStyle)
        }, id: \.id) { plugin in
            Section {
                pluginGroup(plugin)
            }
        }
        // スライダーのtransient更新が確定前に残らないよう、
        // ペイン切替・設定画面を閉じる時点で必ず永続化する
        // (変更が無ければcommitSettingsはno-op)
        .onDisappear { store.commitSettings() }
    }

    @ViewBuilder
    private func pluginGroup(_ plugin: any ShelfPlugin) -> some View {
        // canDisable=falseのプラグイン(壁等)は常に有効なので
        // ON/OFFトグル行を出さず、パラメータ調整UIだけを並べる
        if plugin.canDisable {
            Toggle(isOn: enabledBinding(plugin)) {
                // displayName/labelはStringなのでText(String)=verbatim initに
                // 解決されてしまう。LocalizedStringKey経由にしてカタログを
                // 引かせる(キーが無ければそのまま表示される)。
                // 太字にしてボックス内の先頭行=グループのタイトルに見せる
                Text(LocalizedStringKey(plugin.displayName))
                    .font(.headline)
            }
        }
        // パラメータ調整UIは有効/無効に関わらず常時表示し、
        // 無効時は標準のディセーブル表現(グレー・操作不可)にする
        ForEach(plugin.parameterSpecs, id: \.id) { spec in
            parameterControl(plugin, spec: spec)
        }
        .disabled(!isEnabled(plugin))
    }

    @ViewBuilder
    private func parameterControl(_ plugin: any ShelfPlugin, spec: PluginParameterSpec) -> some View {
        switch spec {
        case .slider(let s):
            PluginSliderRow(store: store, plugin: plugin, spec: s)
        case .options(let o):
            PluginOptionsRow(store: store, plugin: plugin, spec: o)
        }
    }

    // MARK: - 状態アクセス

    private func isEnabled(_ plugin: any ShelfPlugin) -> Bool {
        // 未保存のプラグインはdefaultEnabled(StoreShelfPluginは既定ON、
        // 効果系は既定OFF)。canDisable=falseは常に有効。
        // レジストリのresolveと同じ規則にして表示と実態を一致させる
        !plugin.canDisable
            || (store.settings.plugins[plugin.id]?.enabled ?? plugin.defaultEnabled)
    }

    private func enabledBinding(_ plugin: any ShelfPlugin) -> Binding<Bool> {
        Binding(
            get: { isEnabled(plugin) },
            set: { on in
                Self.logger.notice("plugin toggled: \(plugin.id, privacy: .public) \(on ? "enabled" : "disabled", privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
                updatePluginState(store: store, plugin: plugin) { $0.enabled = on }
            }
        )
    }
}

/// フォーカス中シェルフのプラグイン状態を1件書き換える。
/// persist=trueは即座にsettings.jsonへ保存(トグル等の単発変更)。
/// persist=falseはメモリ上のライブ反映のみ(スライダーの連続変更。
/// 呼び出し側がcommitSettingsで確定する)
@MainActor
private func updatePluginState(
    store: ShelfStore,
    plugin: any ShelfPlugin,
    persist: Bool = true,
    mutate: (inout PluginState) -> Void
) {
    var plugins = store.settings.plugins
    // 未保存のプラグインはdefaultEnabledで状態をシードする
    // (トグルの表示=実態の規則と同じ)
    var state = plugins[plugin.id] ?? PluginState(enabled: plugin.defaultEnabled)
    mutate(&state)
    // canDisable=false(常時有効)のプラグインにenabled=falseは
    // 書かせない。古い保存値が残っていてもここで正規化する
    if !plugin.canDisable { state.enabled = true }
    // specに存在しないキー(廃止パラメータ等)を間引き、settings.jsonに
    // 残った古い値が次の保存で消えるようにする
    let specIDs = Set(plugin.parameterSpecs.map(\.id))
    state.values = state.values.filter { specIDs.contains($0.key) }
    plugins[plugin.id] = state
    // 現行settingsをコピーしてpluginsだけ差し替える。新規インスタンスを
    // 組み立てると後から増えたフィールド(間隔等)が既定値に戻る
    var newSettings = store.settings
    newSettings.plugins = plugins
    if persist {
        store.updateSettings(newSettings)
    } else {
        store.updateSettingsTransient(newSettings)
    }
}

/// プラグインパラメータのスライダー行。
/// 値の変更はupdateSettingsTransientでメモリ上だけ反映(セルへライブ反映)
/// し、settings.jsonへの永続化+変更ログは「入力が止まる」を編集完了と
/// みなすデバウンスでcommitSettingsにまとめる。
/// (macOS 26で onEditingChanged 付きSliderのinitは非推奨。
///  デバウンスならドラッグ/クリックジャンプ/キー操作を問わず
///  編集完了を網羅できる)
private struct PluginSliderRow: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    /// これだけ値が変わらなければ編集完了とみなす無入力時間
    private static let commitDelay: Duration = .milliseconds(400)

    @ObservedObject var store: ShelfStore
    let plugin: any ShelfPlugin
    let spec: PluginParameterSpec.Slider
    /// デバウンス中のコミットTask。連続変更のたびに張り替える
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let step = spec.step {
                Slider(value: sliderBinding, in: spec.range, step: step) {
                    Text(LocalizedStringKey(spec.label))
                }
            } else {
                Slider(value: sliderBinding, in: spec.range) {
                    Text(LocalizedStringKey(spec.label))
                }
            }
        }
        // 行が一覧から外れる(スタイル切替等)・設定画面が閉じる時点で
        // transientな変更が残っていたら即確定する
        .onDisappear {
            commitTask?.cancel()
            store.commitSettings()
        }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                store.settings.plugins[plugin.id]?.values[spec.id]?.number ?? spec.defaultValue
            },
            set: { newValue in
                updatePluginState(store: store, plugin: plugin, persist: false) {
                    $0.values[spec.id] = .number(newValue)
                }
                scheduleCommit()
            }
        )
    }

    /// 無入力commitDelay後にsettingsを永続化してコミットログを出す。
    /// 連続変更のたびに延期されるので、ドラッグ中は書き込まれない
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            commitTask = nil
            store.commitSettings()
            let value = store.settings.plugins[plugin.id]?.values[spec.id]?.number ?? spec.defaultValue
            Self.logger.notice("plugin param committed: \(plugin.id, privacy: .public)/\(spec.id, privacy: .public)=\(value, privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
        }
    }
}

/// プラグインパラメータの選択型行。
/// spec.presentationで出し方を切り替える:
///  - .automatic: 選択肢が少なければセグメント、多ければメニューの標準ピッカー
///  - .grid(columns): 固定列数のグリッドピッカー(照明位置の3x3等)
/// 選択は1回のタップで確定する単発変更なので、即時永続化
/// (persist=true)し、コミットログもここで出す(デバウンス不要)。
private struct PluginOptionsRow: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    /// グリッドピッカーのセル1辺
    private static let gridCellSize: CGFloat = 24

    @ObservedObject var store: ShelfStore
    let plugin: any ShelfPlugin
    let spec: PluginParameterSpec.Options
    /// 親トグルOFFで行が.disabledにされたか。標準コントロールは
    /// 自前でグレー化するが、グリッドピッカーは自前描画なので
    /// この値を見て減光させる(ボタンの操作不可自体は
    /// .disabled環境値が効く)
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        switch spec.presentation {
        case .automatic:
            automaticPicker
        case .grid(let columns):
            gridPicker(columns: columns)
        }
    }

    /// 現在値(未設定ならspecのデフォルト)
    private var selection: String {
        store.settings.plugins[plugin.id]?.values[spec.id]?.string ?? spec.defaultValue
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { selection },
            set: { commit($0) }
        )
    }

    /// 標準ピッカー。4択程度までなら一目で選べるセグメントにし、
    /// それより多い/ラベルが長い場合はメニューに逃がす
    /// (pickerStyleは型が違うので三項演算子ではなく分岐で返す)
    @ViewBuilder
    private var automaticPicker: some View {
        if spec.choices.count <= 4 {
            optionsPicker.pickerStyle(.segmented)
        } else {
            optionsPicker.pickerStyle(.menu)
        }
    }

    private var optionsPicker: some View {
        Picker(selection: selectionBinding) {
            ForEach(spec.choices, id: \.id) { choice in
                if let icon = choice.icon {
                    Label {
                        Text(LocalizedStringKey(choice.label))
                    } icon: {
                        choiceIcon(icon)
                    }
                    // 閉じたボタンではiconとtitleが標準間隔で詰まって
                    // 見えるため広げる。メニュー項目側はNSMenuItemの
                    // image+titleで描画されるのでこのスタイルの影響は
                    // 受けず、開いたメニューの見た目は変わらない
                    .labelStyle(SwatchLabelStyle())
                    .tag(choice.id)
                } else {
                    Text(LocalizedStringKey(choice.label)).tag(choice.id)
                }
            }
        } label: {
            Text(LocalizedStringKey(spec.label))
        }
    }

    /// 選択肢Labelのiconとtitleの間隔を広げるスタイル。
    /// メニュー項目(NSMenuItem)には影響せず、ピッカーが閉じた
    /// ボタン表示でのみiconとtitleの間を開く
    private struct SwatchLabelStyle: LabelStyle {
        /// メニュー項目の画像とタイトルの間隔に合わせた目安値
        let spacing: CGFloat = 8
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: spacing) {
                configuration.icon
                configuration.title
            }
        }
    }

    /// 選択肢行の見本(壁の色/質感スウォッチ)。
    /// macOSの「外観モード」の色見本と同じく丸いスウォッチを
    /// メニュー行の先頭に出す。
    /// メニュー項目の画像として出せるのはImage(=NSImage)だけ
    /// (Circle()等のViewは描画されず、resizable/clipShape等の
    /// 修飾もメニュー側では無視されて元画像の矩形が出る
    /// — 2026-11実機確認)。そのため丸く切り抜いたNSImageを
    /// 自前で描いてからImageに載せる
    private static let choiceIconSize: CGFloat = 16

    private func choiceIcon(
        _ icon: PluginParameterSpec.Options.Choice.Icon
    ) -> Image {
        let size = NSSize(
            width: Self.choiceIconSize, height: Self.choiceIconSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let oval = NSBezierPath(
                ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            switch icon {
            case .color(let r, let g, let b):
                NSColor(red: r, green: g, blue: b, alpha: 1).setFill()
                oval.fill()
            case .texture(let asset):
                if let tile = NSImage(named: asset) {
                    NSGraphicsContext.current?.saveGraphicsState()
                    oval.addClip()
                    tile.draw(in: rect)
                    NSGraphicsContext.current?.restoreGraphicsState()
                }
            }
            // 白っぽい見本が地の色に溶けないよう薄い縁を付ける
            NSColor.separatorColor.setStroke()
            oval.lineWidth = 0.5
            oval.stroke()
            return true
        }
        return Image(nsImage: image)
    }

    /// 固定列数のグリッドピッカー。各セルは照明(sun)アイコンで、
    /// 選択中のセルだけ点灯した表示にする(光の位置を視覚的に選ぶUI)。
    /// 行が.disabledのときは標準コントロールと同じくグレー化する
    /// (自前描画なのでisEnabledを見て自分で減光する必要がある)
    @ViewBuilder
    private func gridPicker(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(spec.label))
                .foregroundStyle(isEnabled ? .primary : .secondary)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(Self.gridCellSize), spacing: 4),
                    count: columns
                ),
                spacing: 4
            ) {
                ForEach(spec.choices, id: \.id) { choice in
                    let selected = selection == choice.id
                    Button {
                        commit(choice.id)
                    } label: {
                        gridCell(selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(LocalizedStringKey(choice.label)))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
    }

    /// グリッドの1セル。選択中はアクセントの背景+点灯した
    /// sunアイコン、未選択は薄いドット状のsunアイコン
    private func gridCell(selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(selected
                      ? Color.accentColor.opacity(0.3)
                      : Color.primary.opacity(0.06))
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color.accentColor
                                          : Color.secondary.opacity(0.35))
        }
        .frame(width: Self.gridCellSize, height: Self.gridCellSize)
        .contentShape(Rectangle())
    }

    /// 選択を確定して即時永続化+コミットログ。
    /// ログ形式はPluginSliderRowの `plugin param committed:` と同じ
    private func commit(_ newValue: String) {
        guard newValue != selection else { return }
        updatePluginState(store: store, plugin: plugin, persist: true) {
            $0.values[spec.id] = .string(newValue)
        }
        Self.logger.notice("plugin param committed: \(plugin.id, privacy: .public)/\(spec.id, privacy: .public)=\(newValue, privacy: .public) (shelf=\(self.store.shelfID, privacy: .public))")
    }
}

/// Dockアイコンのプリセット＋カスタム画像選択(Generalペイン)。
/// アプリ全体共通の設定なのでShelfStoreは要求しない
/// (フォーカス中シェルフが無くても操作できる)。
/// 1行目に内蔵5プリセット、2行目にCustom 3スロットを左揃えで並べ、
/// 選択中のCustomスロット右上に削除バッジボタンを重ねる
private struct AppIconPicker: View {

    private static let logger = Logger(subsystem: "com.cacheandbuffer.Sleeves", category: "UI")

    /// サムネイルの1辺
    private static let thumbnailSize: CGFloat = 64
    /// サムネイルの角丸。macOSのアイコン形状(連続角丸のsquircle)に
    /// 近づけるため1辺の約22%にしてある
    private static let cornerRadius: CGFloat = 14
    /// タイル間の水平間隔(1行目の先頭3枚と2行目の3スロットの縦軸を揃える)
    private static let tileSpacing: CGFloat = 20
    /// プリセット行とカスタム行の縦間隔
    private static let rowSpacing: CGFloat = 12

    /// 表示中の選択。実体はUserDefaults(AppIconManager.saved)で、
    /// ここは表示用のミラーとして.onAppearと操作のたびに同期する
    @State private var selected: AppIconManager.AppIconSelection = .preset(.default)
    /// 削除バッジ表示用のフォーカス中カスタムスロット。
    /// 適用中のアイコン(selected)とは分離し、余白クリックやウィンドウ非アクティブ化で
    /// 削除ボタンだけを消す(Dockアイコンと選択枠は維持する)
    @State private var activeCustomSlot: Int? = nil
    /// 保存済みカスタム画像のサムネイルキャッシュ(.onAppearで読み込む)
    @State private var customImages: [NSImage?] = Array(repeating: nil, count: AppIconManager.customSlotCount)
    /// fileImporter で取り込み対象にしているスロット番号
    @State private var importingSlot: Int? = nil
    /// 画像ファイル選択シートの表示フラグ
    @State private var showFileImporter = false
    /// 読み込み/変換失敗アラートの表示フラグ
    @State private var showErrorAlert = false
    /// ドラッグ進入ハイライト中のスロット番号
    @State private var dropTargetedSlot: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Icon")
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                HStack(spacing: Self.tileSpacing) {
                    ForEach(AppIconManager.AppIconPreset.allCases) { preset in
                        let isSelected = selected == .preset(preset)
                        Button {
                            Self.logger.notice("settings: app icon preset tapped \(preset.rawValue, privacy: .public)")
                            activeCustomSlot = nil
                            AppIconManager.select(.preset(preset))
                            // selectはapply失敗時に保存しないので、表示も
                            // 保存値へ寄せ直す(失敗した選択が残らない)
                            selected = AppIconManager.saved
                        } label: {
                            VStack(spacing: 6) {
                                Image(preset.assetName)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Self.cornerRadius)
                                            .strokeBorder(
                                                isSelected
                                                    ? Color.accentColor
                                                    : Color.secondary.opacity(0.3),
                                                lineWidth: isSelected ? 2 : 1)
                                    }
                                Text(LocalizedStringKey(preset.label))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }

                HStack(spacing: Self.tileSpacing) {
                    ForEach(0..<AppIconManager.customSlotCount, id: \.self) { slot in
                        customTile(slot: slot)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .onAppear {
            customImages = AppIconManager.loadAllCustomImages()
            selected = AppIconManager.saved
        }
        .onDisappear {
            if let slot = activeCustomSlot {
                Self.logger.notice("settings: app icon custom focus cleared (onDisappear) slot=\(slot, privacy: .public)")
                activeCustomSlot = nil
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            let targetSlot = importingSlot ?? 0
            importingSlot = nil
            switch result {
            case .success(let url):
                Self.logger.notice("settings: app icon fileImporter selected slot=\(targetSlot, privacy: .public) file=\(url.lastPathComponent, privacy: .public)")
                importCustomImage(from: url, slot: targetSlot)
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                    Self.logger.notice("settings: app icon fileImporter cancelled slot=\(targetSlot, privacy: .public)")
                } else {
                    Self.logger.error("settings: app icon fileImporter FAILED slot=\(targetSlot, privacy: .public): \(String(describing: error), privacy: .public)")
                    showErrorAlert = true
                }
            }
        }
        .alert("Couldn’t Set App Icon", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected file couldn’t be loaded as an image.")
        }
    }

    /// Customスロット1枚。未設定時は破線枠＋"+"でピッカーを開き、
    /// 設定済み時はサムネイル表示でタップ選択。フォーカス中(activeCustomSlot == slot)の
    /// 設定済みスロット右上には兄弟ビューとして削除サークルボタンを重ねる
    /// (Buttonネストによるイベント競合を防止)。どちらの状態でも画像ドロップを受理する
    private func customTile(slot: Int) -> some View {
        let image = customImages.indices.contains(slot) ? customImages[slot] : nil
        let isSelected = selected == .custom(slot)
        let isBadgeVisible = activeCustomSlot == slot && image != nil
        let isDropTargeted = dropTargetedSlot == slot
        let labelText = "\(String(localized: "Custom")) \(slot + 1)"
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button {
                    if image != nil {
                        Self.logger.notice("settings: app icon custom tile tapped (select) slot=\(slot, privacy: .public)")
                        AppIconManager.select(.custom(slot))
                        selected = AppIconManager.saved
                        activeCustomSlot = (selected == .custom(slot)) ? slot : nil
                    } else {
                        Self.logger.notice("settings: app icon custom tile tapped (open picker) slot=\(slot, privacy: .public)")
                        activeCustomSlot = nil
                        importingSlot = slot
                        showFileImporter = true
                    }
                } label: {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: Self.cornerRadius)
                                    .strokeBorder(
                                        (isDropTargeted || isSelected)
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.3),
                                        lineWidth: (isDropTargeted || isSelected) ? 2 : 1)
                            }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: Self.cornerRadius)
                                .strokeBorder(
                                    isDropTargeted
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.5),
                                    style: StrokeStyle(
                                        lineWidth: isDropTargeted ? 2 : 1.5,
                                        dash: [4, 3]))
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                        }
                        .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(labelText))
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isBadgeVisible {
                    Button {
                        Self.logger.notice("settings: app icon remove tapped slot=\(slot, privacy: .public)")
                        activeCustomSlot = nil
                        AppIconManager.removeCustomImage(slot: slot)
                        customImages = AppIconManager.loadAllCustomImages()
                        selected = AppIconManager.saved
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove"))
                    .offset(x: 6, y: -6)
                }
            }
            .background {
                OutsideClickDismissMonitor(isActive: isBadgeVisible) { reason in
                    if activeCustomSlot == slot {
                        Self.logger.notice("settings: app icon custom focus cleared (\(reason, privacy: .public)) slot=\(slot, privacy: .public)")
                        activeCustomSlot = nil
                    }
                }
            }

            Text(labelText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: dropTargetedBinding(for: slot)) { providers in
            handleDrop(providers, slot: slot)
        }
    }

    private func dropTargetedBinding(for slot: Int) -> Binding<Bool> {
        Binding(
            get: { dropTargetedSlot == slot },
            set: { targeted in
                if targeted {
                    dropTargetedSlot = slot
                } else if dropTargetedSlot == slot {
                    dropTargetedSlot = nil
                }
            }
        )
    }

    private func importCustomImage(from url: URL, slot: Int) {
        switch AppIconManager.importCustomImage(from: url, slot: slot) {
        case .success(let image):
            if customImages.indices.contains(slot) {
                customImages[slot] = image
            }
            selected = AppIconManager.saved
            activeCustomSlot = slot
            Self.logger.notice("settings: app icon custom image applied from URL slot=\(slot, privacy: .public)")
        case .failure(let error):
            Self.logger.error("settings: app icon import from URL FAILED slot=\(slot, privacy: .public): \(String(describing: error), privacy: .public)")
            showErrorAlert = true
        }
    }

    private func importCustomImage(data: Data, slot: Int) {
        switch AppIconManager.importCustomImage(data: data, slot: slot) {
        case .success(let image):
            if customImages.indices.contains(slot) {
                customImages[slot] = image
            }
            selected = AppIconManager.saved
            activeCustomSlot = slot
            Self.logger.notice("settings: app icon custom image applied from dropped data slot=\(slot, privacy: .public)")
        case .failure(let error):
            Self.logger.error("settings: app icon import from data FAILED slot=\(slot, privacy: .public): \(String(describing: error), privacy: .public)")
            showErrorAlert = true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], slot: Int) -> Bool {
        guard let provider = providers.first else {
            Self.logger.error("settings: app icon drop ignored (no providers) slot=\(slot, privacy: .public)")
            return false
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            Self.logger.notice("settings: app icon drop received (fileURL) slot=\(slot, privacy: .public)")
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                let droppedURL: URL?
                if let directURL = item as? URL {
                    droppedURL = directURL
                } else if let data = item as? Data {
                    droppedURL = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    droppedURL = nil
                }
                let errorDescription = error.map { String(describing: $0) }
                Task { @MainActor in
                    if let errorDescription {
                        Self.logger.error("settings: app icon drop fileURL load FAILED slot=\(slot, privacy: .public): \(errorDescription, privacy: .public)")
                        showErrorAlert = true
                        return
                    }
                    guard let droppedURL else {
                        Self.logger.error("settings: app icon drop fileURL decode FAILED slot=\(slot, privacy: .public)")
                        showErrorAlert = true
                        return
                    }
                    importCustomImage(from: droppedURL, slot: slot)
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            Self.logger.notice("settings: app icon drop received (image) slot=\(slot, privacy: .public)")
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                let errorDescription = error.map { String(describing: $0) }
                Task { @MainActor in
                    if let errorDescription {
                        Self.logger.error("settings: app icon drop image load FAILED slot=\(slot, privacy: .public): \(errorDescription, privacy: .public)")
                        showErrorAlert = true
                        return
                    }
                    guard let data else {
                        Self.logger.error("settings: app icon drop image data nil slot=\(slot, privacy: .public)")
                        showErrorAlert = true
                        return
                    }
                    importCustomImage(data: data, slot: slot)
                }
            }
            return true
        }
        Self.logger.error("settings: app icon drop rejected (unsupported type) slot=\(slot, privacy: .public)")
        return false
    }
}

/// カスタムアイコンの削除バッジ表示中だけ、外側クリックとウィンドウ非アクティブ化を
/// 検知してフォーカスを解除するための軽量モニタ。
/// isActive が false になったとき・ビュー破棄時(dismantleNSView/deinit)に必ず
/// イベントモニタと通知オブザーバを解除する
private struct OutsideClickDismissMonitor: NSViewRepresentable {

    let isActive: Bool
    let onDismiss: (String) -> Void

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    final class Coordinator {
        private var isMonitoring = false
        private var mouseMonitor: Any?
        private var resignObserver: NSObjectProtocol?
        weak var view: NSView?
        var onDismiss: (String) -> Void

        init(onDismiss: @escaping (String) -> Void) {
            self.onDismiss = onDismiss
        }

        func update(isActive: Bool, view: NSView, onDismiss: @escaping (String) -> Void) {
            self.view = view
            self.onDismiss = onDismiss
            if isActive, !isMonitoring {
                startMonitoring()
            } else if !isActive, isMonitoring {
                teardown()
            }
        }

        private func startMonitoring() {
            isMonitoring = true
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let view = self.view else { return event }
                if event.window !== view.window {
                    self.onDismiss("outside window click")
                    return event
                }
                let point = view.convert(event.locationInWindow, from: nil)
                // 右上削除バッジ(offset(x: 6, y: -6) の 18pt アイコン)＋ヒット余白を包含する領域
                let badgeRect = CGRect(
                    x: view.bounds.maxX - 16,
                    y: -10,
                    width: 26,
                    height: 26
                )
                if !view.bounds.contains(point) && !badgeRect.contains(point) {
                    self.onDismiss("outside click")
                }
                return event
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let window = self.view?.window,
                      (notification.object as? NSWindow) === window
                else { return }
                self.onDismiss("window resigned key")
            }
        }

        func teardown() {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
                self.resignObserver = nil
            }
            isMonitoring = false
        }

        deinit {
            teardown()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> FlippedView {
        let view = FlippedView(frame: .zero)
        context.coordinator.update(isActive: isActive, view: view, onDismiss: onDismiss)
        return view
    }

    func updateNSView(_ nsView: FlippedView, context: Context) {
        context.coordinator.update(isActive: isActive, view: nsView, onDismiss: onDismiss)
    }

    static func dismantleNSView(_ nsView: FlippedView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}
