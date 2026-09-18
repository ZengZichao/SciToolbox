import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - SettingsView (minimal)

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("cacheEnabled") private var cacheEnabled: Bool = true
    /// A3：侧边栏密度（此前已实现却不可达，补上设置 UI）
    @AppStorage("sidebarDensity") private var sidebarDensity: String = "normal"
    @StateObject private var history = SearchHistory.shared
    @StateObject private var favorites = LocalFavorites.shared
    @StateObject private var collections = CollectionStore.shared
    @StateObject private var appLanguage = AppLanguage.shared
    /// P0-1 / P2-12：清除类操作确认
    @State private var confirmClearCache = false
    @State private var confirmClearHistory = false
    @State private var confirmClearFavorites = false
    @State private var confirmResetAll = false

    var body: some View {
        Form {
            Section(L10n.t(.appearance)) {
                Picker(L10n.t(.theme), selection: $appearance) {
                    Text(L10n.t(.themeSystem)).tag("system")
                    Text(L10n.t(.themeLight)).tag("light")
                    Text(L10n.t(.themeDark)).tag("dark")
                }
                .pickerStyle(.segmented)
                // A3：密度设置 UI（绑定同一 @AppStorage("sidebarDensity")）
                Picker(L10n.t(.sidebarDensity), selection: $sidebarDensity) {
                    ForEach(SidebarDensity.allCases, id: \.rawValue) { density in
                        Text(density.name).tag(density.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                // 语言切换
                Picker(L10n.t(.language), selection: Binding(
                    get: { appLanguage.current },
                    set: { appLanguage.current = $0 }
                )) {
                    ForEach(AppLanguage.Language.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.t(.cache)) {
                Toggle(L10n.t(.enableCache), isOn: $cacheEnabled)
                    .onChange(of: cacheEnabled) { _, newValue in
                        // P2-12：切换即时反馈
                        Clipboard.showToast(newValue ? L10n.t(.cacheEnabled) : L10n.t(.cacheDisabled))
                    }
                Button(L10n.t(.clearCache), role: .destructive) {
                    confirmClearCache = true
                }
            }

            Section(L10n.t(.queryHistory)) {
                LabeledContent(L10n.t(.historyCount), value: "\(history.entries.count)")
                Button(L10n.t(.clearHistory), role: .destructive) {
                    confirmClearHistory = true
                }
                .disabled(history.entries.isEmpty)
            }

            Section(L10n.t(.favoritesSection)) {
                LabeledContent(L10n.t(.favoritesCount), value: "\(favorites.favorites.count)")
                Button(L10n.t(.exportFavoritesText)) {
                    exportFavorites(format: .text)
                }
                .disabled(favorites.favorites.isEmpty)
                Button(L10n.t(.exportFavoritesJSON)) {
                    exportFavorites(format: .json)
                }
                .disabled(favorites.favorites.isEmpty)
                Button(L10n.t(.clearFavorites), role: .destructive) {
                    confirmClearFavorites = true
                }
                .disabled(favorites.favorites.isEmpty)
            }

            Section(L10n.t(.dataManagement)) {
                // E16：一键导出全部本地数据（含集合）
                Button(L10n.t(.exportAllData)) {
                    exportAllData()
                }
                .disabled(favorites.favorites.isEmpty && history.entries.isEmpty && collections.collections.isEmpty)
                // E16：重置应用
                Button(L10n.t(.resetApp), role: .destructive) {
                    confirmResetAll = true
                }
            }

            Section(L10n.t(.shortcutsSection)) {
                shortcutRow(L10n.t(.shortcutCmdK), L10n.t(.shortcutCmdKDesc))
                shortcutRow(L10n.t(.shortcutCmdF), L10n.t(.shortcutCmdFDesc))
                shortcutRow(L10n.t(.shortcutCmdBracket), L10n.t(.shortcutCmdBracketDesc))
                shortcutRow(L10n.t(.shortcutCmdBackslash), L10n.t(.shortcutCmdBackslashDesc))
                shortcutRow(L10n.t(.shortcutCmdSlash), L10n.t(.shortcutCmdSlashDesc))
                shortcutRow(L10n.t(.shortcutCmdClick), L10n.t(.shortcutCmdClickDesc))
            }

            Section(L10n.t(.about)) {
                HStack(spacing: Theme.sp4) {
                    AppLogoView(size: 48)
                    VStack(alignment: .leading, spacing: Theme.sp1) {
                        Text("SciToolbox")
                            .font(.system(size: Theme.fsHeadline, weight: .semibold))
                            .foregroundColor(Theme.ink)
                        LabeledContent(L10n.t(.version), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    }
                }
                LabeledContent(L10n.t(.osVersion), value: "macOS 15+")
                Button(L10n.t(.revisitOnboarding)) {
                    UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                    Clipboard.showToast(L10n.t(.onboardingHint))
                }
                Text(L10n.t(.aboutText))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.t(.navTitle))
        .frame(maxWidth: 520)
        .confirmationDialog(L10n.t(.confirmClearCache), isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button(L10n.t(.clearCacheBtn), role: .destructive) {
                ResponseCache.shared.clear()
                Clipboard.showToast(L10n.t(.cacheCleared))
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        }
        .confirmationDialog(L10n.t(.confirmClearHistory, history.entries.count), isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button(L10n.t(.clearHistoryBtn), role: .destructive) {
                history.clearAll()
                Clipboard.showToast(L10n.t(.historyCleared))
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        }
        .confirmationDialog(L10n.t(.confirmClearFavorites, favorites.favorites.count), isPresented: $confirmClearFavorites, titleVisibility: .visible) {
            Button(L10n.t(.clearFavoritesBtn), role: .destructive) {
                favorites.clearAll()
                Clipboard.showToast(L10n.t(.favoritesCleared))
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        }
        .confirmationDialog(L10n.t(.confirmResetAll), isPresented: $confirmResetAll, titleVisibility: .visible) {
            Button(L10n.t(.resetAllBtn), role: .destructive) {
                resetAllData()
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        } message: {
            Text(L10n.t(.resetAllMessage))
        }
    }

    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack(spacing: Theme.sp3) {
            Text(keys)
                .font(.system(size: Theme.fsSmall, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.accent)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.ink2)
        }
    }

    private enum ExportFormat { case text, json }

    private func exportFavorites(format: ExportFormat) {
        let content: String
        let filename: String
        let ext: String
        switch format {
        case .text:
            content = favorites.exportAsText()
            filename = L10n.t(.favoritesFilename)
            ext = "txt"
        case .json:
            content = favorites.exportAsJSON()
            filename = L10n.t(.favoritesFilename)
            ext = "json"
        }

        // P2-15：按扩展名选择正确 UTType
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename + "." + ext
        panel.allowedContentTypes = [ExportUtil.contentType(for: ext)]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.data(using: .utf8)?.write(to: url)
            Clipboard.showToast(L10n.t(.exported, url.lastPathComponent))
        }
    }

    /// E16：导出全部本地数据（收藏 + 历史 + 集合）为单一 JSON。
    private func exportAllData() {
        struct Bundle: Encodable {
            let exportedAt: Date
            let favorites: [FavoriteItem]
            let history: [HistoryEntry]
            let collections: [SciCollection]
        }
        let bundle = Bundle(
            exportedAt: Date(),
            favorites: favorites.favorites,
            history: history.entries,
            collections: collections.collections
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(bundle) else {
            Clipboard.showToast(L10n.t(.exportFailed))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = L10n.t(.allDataFilename) + ".json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
            Clipboard.showToast(L10n.t(.allDataExported))
        }
    }

    private func resetAllData() {
        favorites.clearAll()
        history.clearAll()
        collections.clearAll()
        ResponseCache.shared.clear()
        Clipboard.showToast(L10n.t(.dataReset))
    }
}

// MARK: - Appearance helper

enum Appearance {
    static func apply(_ value: String) {
        switch value {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}
