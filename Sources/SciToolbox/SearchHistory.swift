import Foundation

// MARK: - SearchHistory (local-only, no network, no privacy risk)

/// Query history manager. Stores recent queries per tool in UserDefaults.
/// Pure local — never sends any data to any server.
@MainActor
final class SearchHistory: ObservableObject {
    static let shared = SearchHistory()

    @Published private(set) var entries: [HistoryEntry] = []

    private let key = "SciToolbox.SearchHistory"
    private let maxEntries = 200

    init() {
        load()
    }

    func add(toolId: String, toolName: String, query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Remove duplicate (same tool + same query) to avoid clutter
        entries.removeAll { $0.toolId == toolId && $0.query == trimmed }

        let entry = HistoryEntry(
            id: UUID().uuidString,
            toolId: toolId,
            toolName: toolName,
            query: trimmed,
            timestamp: Date()
        )
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func entries(for toolId: String) -> [HistoryEntry] {
        entries.filter { $0.toolId == toolId }
    }

    /// 删除单条历史，返回被删项以便「撤销」（P0-1）。
    @discardableResult
    func remove(id: String) -> HistoryEntry? {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = entries[idx]
        entries.remove(at: idx)
        save()
        return removed
    }

    /// 撤销删除：恢复单条历史。
    func restore(_ entry: HistoryEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.insert(entry, at: 0)
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    func clear(toolId: String) {
        entries.removeAll { $0.toolId == toolId }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - HistoryEntry

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: String
    let toolId: String
    let toolName: String
    let query: String
    let timestamp: Date

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
