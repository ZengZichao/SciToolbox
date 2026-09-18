import Foundation

// MARK: - LocalFavorites (pure local, no network, user-exportable)

/// Local favorites/bookmarks manager. Pure local storage — no syncing, no network.
/// Users can export their favorites as text/JSON at any time.
@MainActor
final class LocalFavorites: ObservableObject {
    static let shared = LocalFavorites()

    @Published private(set) var favorites: [FavoriteItem] = []

    private let key = "SciToolbox.LocalFavorites"

    init() {
        load()
    }

    func toggle(toolId: String, toolName: String, itemId: String, title: String, subtitle: String? = nil) {
        toggle(toolId: toolId, toolName: toolName, itemId: itemId, title: title, subtitle: subtitle, snapshot: nil, note: nil)
    }

    /// 收藏时同时保存详情快照（key/value 摘要），便于收藏夹离线展示更多上下文。
    func toggle(toolId: String, toolName: String, itemId: String, title: String, subtitle: String? = nil, snapshot: [String: String]? = nil, note: String? = nil) {
        if let idx = favorites.firstIndex(where: { $0.itemId == itemId && $0.toolId == toolId }) {
            favorites.remove(at: idx)
        } else {
            let fav = FavoriteItem(
                id: UUID().uuidString,
                toolId: toolId,
                toolName: toolName,
                itemId: itemId,
                title: title,
                subtitle: subtitle,
                note: note,
                snapshot: snapshot,
                timestamp: Date()
            )
            favorites.insert(fav, at: 0)
        }
        save()
    }

    /// 仅添加（不切换/移除）。用于批量收藏：若已存在则跳过。
    func add(toolId: String, toolName: String, itemId: String, title: String, subtitle: String? = nil) {
        guard !favorites.contains(where: { $0.itemId == itemId && $0.toolId == toolId }) else { return }
        let fav = FavoriteItem(
            id: UUID().uuidString,
            toolId: toolId,
            toolName: toolName,
            itemId: itemId,
            title: title,
            subtitle: subtitle,
            note: nil,
            snapshot: nil,
            timestamp: Date()
        )
        favorites.insert(fav, at: 0)
        save()
    }

    func isFavorited(toolId: String, itemId: String) -> Bool {
        favorites.contains { $0.toolId == toolId && $0.itemId == itemId }
    }

    /// 按 (toolId, itemId) 查找收藏条目（详情页「编辑笔记」用）。
    func favorite(toolId: String, itemId: String) -> FavoriteItem? {
        favorites.first { $0.toolId == toolId && $0.itemId == itemId }
    }

    func updateNote(id: String, note: String?) {
        if let idx = favorites.firstIndex(where: { $0.id == id }) {
            favorites[idx].note = note
            save()
        }
    }

    /// 删除单条收藏，返回被删项以便「撤销」（P0-1）。
    @discardableResult
    func remove(id: String) -> FavoriteItem? {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = favorites[idx]
        favorites.remove(at: idx)
        save()
        return removed
    }

    /// 撤销删除：把条目恢复到原位置附近（插入到开头，保持可见）。
    func restore(_ item: FavoriteItem) {
        guard !favorites.contains(where: { $0.id == item.id }) else { return }
        favorites.insert(item, at: 0)
        save()
    }

    func clearAll() {
        favorites.removeAll()
        save()
    }

    // MARK: - Export

    /// Export favorites as plain text (human-readable)
    func exportAsText() -> String {
        var lines = [DT.t("SciToolbox 收藏列表", "SciToolbox Favorites"), DT.t("导出时间：\(Date().formatted())", "Exported: \(Date().formatted())"), DT.t("共 \(favorites.count) 条", "\(favorites.count) items"), ""]
        for fav in favorites {
            lines.append("[\(fav.toolName)] \(fav.title)")
            if let sub = fav.subtitle, !sub.isEmpty { lines.append("  \(sub)") }
            if let snap = fav.snapshot, !snap.isEmpty {
                for (k, v) in snap.prefix(4) {
                    lines.append("  \(k): \(v)")
                }
            }
            if let note = fav.note, !note.isEmpty { lines.append(DT.t("  笔记：\(note)", "  Note: \(note)")) }
            lines.append("  ID: \(fav.itemId)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Export favorites as JSON
    func exportAsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(favorites) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) else { return }
        favorites = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - FavoriteItem

struct FavoriteItem: Identifiable, Codable, Hashable {
    let id: String
    let toolId: String
    let toolName: String
    let itemId: String
    let title: String
    let subtitle: String?
    var note: String?
    /// 收藏时抓取的详情快照（key/value 摘要），离线时也能展示上下文。
    let snapshot: [String: String]?
    let timestamp: Date

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
