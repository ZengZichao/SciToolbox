import Foundation

// MARK: - Collection Store（项目集合 / 课题）

/// 项目集合：把一组相关的查询 / 实体（accession、基因符号、PMID 等）组织成一个「课题」，
/// 用于批量查询、留痕与对比。
///
/// 设计取舍：
/// - 复用 LocalFavorites 的「纯本地、UserDefaults、可导出」范式 —— 不联网、无隐私风险。
/// - 与收藏（扁平列表）的区别：集合是「带课题维度的分组容器」，一个实体可同时属于多个集合。
/// - Entry 记录来源工具与编号，点击即可重新跳转（navigateToTool），实现「留痕」。
@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    @Published private(set) var collections: [SciCollection] = []

    private let key = "SciToolbox.Collections"
    /// 去重键：同一集合内 (toolId + itemId) 唯一
    private let dedupKey: (String, String) -> String = { "\($0)|\($1)" }

    init() { load() }

    // MARK: - Collection 级操作

    @discardableResult
    func create(name: String) -> SciCollection {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let c = SciCollection(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? L10n.t(.unnamedCollection) : trimmed,
            note: nil,
            createdAt: Date(),
            updatedAt: Date(),
            entries: []
        )
        collections.insert(c, at: 0)
        save()
        return c
    }

    func rename(id: String, name: String) {
        if let idx = collections.firstIndex(where: { $0.id == id }) {
            collections[idx].name = name.trimmingCharacters(in: .whitespaces).isEmpty ? L10n.t(.unnamedCollection) : name
            collections[idx].updatedAt = Date()
            save()
        }
    }

    func updateNote(id: String, note: String?) {
        if let idx = collections.firstIndex(where: { $0.id == id }) {
            collections[idx].note = note
            collections[idx].updatedAt = Date()
            save()
        }
    }

    func delete(id: String) {
        collections.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        collections.removeAll()
        save()
    }

    // MARK: - Entry 级操作

    func addEntry(_ entry: CollectionEntry, to collectionId: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let key = dedupKey(entry.toolId, entry.itemId)
        let exists = collections[idx].entries.contains { dedupKey($0.toolId, $0.itemId) == key }
        guard !exists else { return }
        var updated = collections[idx]
        updated.entries.append(entry)
        updated.updatedAt = Date()
        collections[idx] = updated
        save()
    }

    func addEntries(_ entries: [CollectionEntry], to collectionId: String) {
        for e in entries { addEntry(e, to: collectionId) }
    }

    func removeEntry(collectionId: String, entryId: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        collections[idx].entries.removeAll { $0.id == entryId }
        collections[idx].updatedAt = Date()
        save()
    }

    /// 删除集合内实体，返回被删项以便「撤销」（P0-1）。
    @discardableResult
    func removeEntryWithItem(collectionId: String, entryId: String) -> CollectionEntry? {
        guard let idx = collections.firstIndex(where: { $0.id == collectionId }),
              let entryIdx = collections[idx].entries.firstIndex(where: { $0.id == entryId }) else { return nil }
        let removed = collections[idx].entries[entryIdx]
        collections[idx].entries.remove(at: entryIdx)
        collections[idx].updatedAt = Date()
        save()
        return removed
    }

    /// 撤销：把实体放回集合（保持去重）。
    func restoreEntry(_ entry: CollectionEntry, to collectionId: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let key = dedupKey(entry.toolId, entry.itemId)
        let exists = collections[idx].entries.contains { dedupKey($0.toolId, $0.itemId) == key }
        guard !exists else { return }
        collections[idx].entries.insert(entry, at: 0)
        collections[idx].updatedAt = Date()
        save()
    }

    /// 更新集合内实体的备注（P1-8）。
    func updateEntryNote(collectionId: String, entryId: String, note: String?) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionId }),
              let entryIdx = collections[idx].entries.firstIndex(where: { $0.id == entryId }) else { return }
        collections[idx].entries[entryIdx].note = note
        collections[idx].updatedAt = Date()
        save()
    }

    func contains(collectionId: String, toolId: String, itemId: String) -> Bool {
        guard let c = collections.first(where: { $0.id == collectionId }) else { return false }
        return c.entries.contains { $0.toolId == toolId && $0.itemId == itemId }
    }

    // MARK: - 导出

    func exportAsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(collections) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SciCollection].self, from: data) else { return }
        collections = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Models

/// 集合中的一个实体（一条 accession / 基因 / 文献等）
struct CollectionEntry: Identifiable, Codable, Hashable {
    let id: String
    let toolId: String
    let toolName: String
    let itemId: String
    let title: String
    let subtitle: String?
    /// 可编辑（P1-8：实体备注）。
    var note: String?
    /// 重新拉取详情所需的上下文（如 Europe PMC 的 source/id、UniProt 的 accession 等），
    /// 缺失时回退到 itemId 直接查询。
    let context: [String: String]?
    let addedAt: Date

    init(id: String = UUID().uuidString, toolId: String, toolName: String,
         itemId: String, title: String, subtitle: String? = nil, note: String? = nil,
         context: [String: String]? = nil, addedAt: Date = Date()) {
        self.id = id
        self.toolId = toolId
        self.toolName = toolName
        self.itemId = itemId
        self.title = title
        self.subtitle = subtitle
        self.note = note
        self.context = context
        self.addedAt = addedAt
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: addedAt, relativeTo: Date())
    }
}

/// 一个项目集合（课题）
struct SciCollection: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var note: String?
    let createdAt: Date
    var updatedAt: Date
    var entries: [CollectionEntry]

    var relativeUpdated: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}

// MARK: - 加入集合的候选（用于从结果列表 / 详情页批量加入）

struct CollectionCandidate: Identifiable {
    let id: String
    let toolId: String
    let toolName: String
    let itemId: String
    let title: String
    let subtitle: String?
    let context: [String: String]?

    init(id: String = UUID().uuidString, toolId: String, toolName: String,
         itemId: String, title: String, subtitle: String? = nil,
         context: [String: String]? = nil) {
        self.id = id
        self.toolId = toolId
        self.toolName = toolName
        self.itemId = itemId
        self.title = title
        self.subtitle = subtitle
        self.context = context
    }

    func toEntry() -> CollectionEntry {
        CollectionEntry(
            toolId: toolId, toolName: toolName,
            itemId: itemId, title: title, subtitle: subtitle, context: context
        )
    }
}
