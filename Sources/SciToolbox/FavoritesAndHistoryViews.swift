import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - FavoritesView (local favorites list with export)

struct FavoritesView: View {
    @StateObject private var favorites = LocalFavorites.shared
    @EnvironmentObject var registry: ToolRegistry
    @State private var exportFormat: ExportFormat = .text
    @State private var showExportSuccess = false
    /// D14：本地过滤关键字
    @State private var filterText = ""
    /// P0-1：清空确认
    @State private var showClearConfirm = false
    /// P1-8：行内编辑笔记
    @State private var editingNoteId: String? = nil
    @State private var noteDraft = ""

    enum ExportFormat {
        case text, json
    }

    private var filtered: [FavoriteItem] {
        let q = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return favorites.favorites }
        return favorites.favorites.filter {
            $0.title.lowercased().contains(q)
                || ($0.subtitle?.lowercased().contains(q) ?? false)
                || $0.toolName.lowercased().contains(q)
                || ($0.note?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Theme.sp3) {
                Text(L10n.t(.favoritesTitle))
                    .font(.system(size: Theme.fsHeadline, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(L10n.t(.resultCount, favorites.favorites.count))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)

                Spacer()

                // Export buttons
                if !favorites.favorites.isEmpty {
                    Menu {
                        Button(L10n.t(.exportAsText)) { export(format: .text) }
                        Button(L10n.t(.exportAsJSON)) { export(format: .json) }
                    } label: {
                        Label(L10n.t(.export), systemImage: "square.and.arrow.up")
                            .font(.system(size: Theme.fsSmall))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    // P0-1：清空加二次确认（附明确数字）
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text(L10n.t(.clearAll))
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.semanticError)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, Theme.sp6)
            .padding(.vertical, Theme.sp4)

            // D14：收藏夹搜索过滤
            if !favorites.favorites.isEmpty {
                HStack(spacing: Theme.sp2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ink3)
                    TextField(L10n.t(.favoritesFilterPlaceholder), text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.fsSmall))
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.ink2)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(L10n.t(.clearFilter))
                    }
                }
                .padding(.horizontal, Theme.sp5)
                .padding(.bottom, Theme.sp2)
            }

            thinDivider()

            // List
            if favorites.favorites.isEmpty {
                StateView(state: .empty(text: L10n.t(.favoritesEmpty)))
            } else if filtered.isEmpty {
                StateView(state: .empty(text: L10n.t(.noFilterMatchFavorites, filterText)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { fav in
                            favoriteRow(fav)
                            thinDivider()
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.t(.favoritesTitle))
        .confirmationDialog(L10n.t(.confirmClearFavoritesMsg, favorites.favorites.count), isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(L10n.t(.clearAll), role: .destructive) {
                favorites.clearAll()
                Clipboard.showToast(L10n.t(.clearedFavorites))
            }
            Button(L10n.t(.cancelBtn), role: .cancel) {}
        } message: {
            Text(L10n.t(.confirmClearFavoritesMsg2))
        }
    }

    @ViewBuilder
    private func favoriteRow(_ fav: FavoriteItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            HStack(spacing: Theme.sp3) {
                Image(systemName: "star.fill")
                .font(.system(size: 11))
                .foregroundColor(Theme.accent.opacity(0.7))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.sp1) {
                        Text(fav.toolName)
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                        Text("·")
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                        Text(fav.relativeTime)
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                    }
                    Text(fav.title)
                        .font(.system(size: Theme.fsBody))
                        .foregroundColor(Theme.ink)
                        .lineLimit(2)
                    if let sub = fav.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink2)
                            .lineLimit(1)
                    }
                    if let snap = fav.snapshot, !snap.isEmpty {
                        let summary = snap.prefix(2).map { "\($0.key): \($0.value)" }.joined(separator: " · ")
                        Text(summary)
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink3)
                            .lineLimit(1)
                    }
                    if let note = fav.note, !note.isEmpty, editingNoteId != fav.id {
                        Text("📝 \(note)")
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink3)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                // P1-8：添加 / 编辑笔记
                Button(action: {
                    editingNoteId = fav.id
                    noteDraft = fav.note ?? ""
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .help(L10n.t(.editNote))
                .accessibilityLabel(L10n.t(.editNote))

                // Quick re-open（P3-9：带 autoDetail 直接打开该条详情，少一次点击）
                Button(action: {
                    NotificationCenter.default.post(
                        name: .navigateToTool,
                        object: nil,
                        userInfo: ["toolId": fav.toolId, "query": fav.itemId, "autoDetail": true]
                    )
                }) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.routeTo, fav.toolName))

                // Remove — P0-1：单条删除 → 可撤销 Toast
                Button(action: {
                    if let removed = favorites.remove(id: fav.id) {
                        Clipboard.showUndoableToast(L10n.t(.deletedFavorite), undo: {
                            favorites.restore(removed)
                        })
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.unfavorite))
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.top, Theme.sp3)

            // P1-8：行内备注编辑
            if editingNoteId == fav.id {
                HStack(spacing: Theme.sp2) {
                    TextField(L10n.t(.notePlaceholder), text: $noteDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.fsSmall))
                        .padding(.horizontal, Theme.sp3)
                        .padding(.vertical, Theme.sp1 + 2)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.line, lineWidth: 0.5))
                    Button(L10n.t(.save)) {
                        favorites.updateNote(id: fav.id, note: noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        editingNoteId = nil
                        Clipboard.showToast(L10n.t(.noteUpdated))
                    }
                    .font(.system(size: Theme.fsSmall, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.sp3)
                    .padding(.vertical, Theme.sp1 + 2)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .buttonStyle(PressableButtonStyle())
                    Button(L10n.t(.cancelBtn)) { editingNoteId = nil }
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.ink3)
                        .buttonStyle(PressableButtonStyle())
                }
                .padding(.horizontal, Theme.sp5)
                .padding(.bottom, Theme.sp3)
            } else {
                Color.clear.frame(height: Theme.sp1)
            }
        }
    }

    private func export(format: ExportFormat) {
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
}

// MARK: - HistoryView (query history list)

struct HistoryView: View {
    @StateObject private var history = SearchHistory.shared
    let onToolSelected: ((String) -> Void)?
    /// D14：本地过滤关键字
    @State private var filterText = ""
    /// P0-1：清空确认
    @State private var showClearConfirm = false

    private var filtered: [HistoryEntry] {
        let q = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.query.lowercased().contains(q) || $0.toolName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Theme.sp3) {
                Text(L10n.t(.historyTitle))
                    .font(.system(size: Theme.fsHeadline, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(L10n.t(.resultCount, history.entries.count))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)

                Spacer()

                if !history.entries.isEmpty {
                    // P0-1：清空加二次确认
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text(L10n.t(.clearAll))
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.semanticError)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, Theme.sp6)
            .padding(.vertical, Theme.sp4)

            // D14：历史过滤
            if !history.entries.isEmpty {
                HStack(spacing: Theme.sp2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ink3)
                    TextField(L10n.t(.historyFilterPlaceholder), text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.fsSmall))
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.ink2)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(L10n.t(.clearFilter))
                    }
                }
                .padding(.horizontal, Theme.sp5)
                .padding(.bottom, Theme.sp2)
            }

            thinDivider()

            // List
            if history.entries.isEmpty {
                StateView(state: .empty(text: L10n.t(.historyEmpty)))
            } else if filtered.isEmpty {
                StateView(state: .empty(text: L10n.t(.noFilterMatchHistory, filterText)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { entry in
                            historyRow(entry)
                            thinDivider()
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.t(.historyTitle))
        .confirmationDialog(L10n.t(.confirmClearHistoryMsg, history.entries.count), isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(L10n.t(.clearAll), role: .destructive) {
                history.clearAll()
                Clipboard.showToast(L10n.t(.clearedHistory))
            }
            Button(L10n.t(.cancelBtn), role: .cancel) {}
        } message: {
            Text(L10n.t(.confirmClearHistoryMsg2))
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: Theme.sp3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundColor(Theme.ink3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.sp1) {
                    Text(entry.toolName)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Text("·")
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Text(entry.relativeTime)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                }
                Text(entry.query)
                    .font(.system(size: Theme.fsBody, design: .monospaced))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Re-run（P3-9：带 autoDetail，重查后直接打开详情）
            Button(action: {
                NotificationCenter.default.post(
                    name: .navigateToTool,
                    object: nil,
                    userInfo: ["toolId": entry.toolId, "query": entry.query, "autoDetail": true]
                )
            }) {
                HStack(spacing: Theme.sp1) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text(L10n.t(.reSearch))
                        .font(.system(size: Theme.fsSmall))
                }
                .foregroundColor(Theme.accent)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.reSearch))

            // Remove — P0-1：单条删除 → 可撤销 Toast
            Button(action: {
                if let removed = history.remove(id: entry.id) {
                    Clipboard.showUndoableToast(L10n.t(.deletedHistory), undo: {
                        history.restore(removed)
                    })
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.ink3)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.deleteHistoryAction))
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp3)
    }
}
