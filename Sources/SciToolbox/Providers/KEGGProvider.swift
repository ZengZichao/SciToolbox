import Foundation

// MARK: - KEGG Provider

/// KEGG REST API — returns plain text (tab-separated for find, structured for get).
/// Auto-detects database type from query pattern.
final class KEGGProvider: ToolProvider {
    let id = "kegg"
    var name: String { DT.t("KEGG 在线检索", "KEGG Online Search") }
    let category: ToolCategory = .functionCategory
    let iconName = "network"
    var placeholder: String { DT.t("关键词（如 glycolysis）", "Keyword (e.g. glycolysis)") }
    var dataSourceNote: String { DT.t("数据来源：KEGG REST API (rest.kegg.jp)", "Data source: KEGG REST API (rest.kegg.jp)") }

    private let base = "https://rest.kegg.jp"

    func search(query: String) async throws -> SearchResult {
        try await search(query: query, offset: 0, pickerId: nil)
    }

    func search(query: String, offset: Int, pickerId: String?) async throws -> SearchResult {
        // Auto-detect database from query pattern since the picker was removed.
        let db = detectDatabase(query: query)
        if offset > 0 { return SearchResult(items: [], total: 0) }
        let url = "\(base)/find/\(urlEncodePath(db))/\(urlEncodePath(query))"

        let text: String
        do {
            text = try await APIClient.shared.getText(url)
        } catch APIError.http(404) {
            // 无效数据库 / 查询无响应：静默返回空结果（不报错）
            return SearchResult(items: [], total: 0)
        }

        // KEGG 无匹配时返回空响应；个别接口会以 "404 ..." 文本返回
        if text.isEmpty || text.hasPrefix("404") {
            return SearchResult(items: [], total: 0)
        }

        var items: [ResultItem] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 {
                let entry = String(parts[0])
                let desc = String(parts[1])
                items.append(ResultItem(
                    id: entry,
                    title: desc,
                    badge: entry,
                    extra: ["entry": entry]
                ))
            }
        }

        return SearchResult(items: items, total: items.count)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let entry = context?["entry"] ?? id
        let url = "\(base)/get/\(urlEncodePath(entry))"

        let text: String
        do {
            text = try await APIClient.shared.getText(url)
        } catch APIError.http(404) {
            throw APIError.notFound(DT.t("未找到条目 \(entry)", "Entry not found: \(entry)"))
        }

        if text.isEmpty || text.hasPrefix("404") {
            throw APIError.notFound(DT.t("未找到相关条目", "No matching entry found"))
        }

        // Parse the entry text into sections
        let sections = parseEntry(text)
        var kvSections: [KVSection] = []
        var rows: [KVRow] = []
        var currentField = ""

        for sec in sections {
            if sec.field != currentField {
                if !rows.isEmpty {
                    kvSections.append(KVSection(title: nil, rows: rows))
                    rows = []
                }
                currentField = sec.field
            }
            rows.append(KVRow(sec.field, sec.value, copyable: true))
        }
        if !rows.isEmpty {
            kvSections.append(KVSection(title: nil, rows: rows))
        }

        let actions: [DetailAction] = [
            DetailAction(label: DT.t("复制条目", "Copy Entry"), payload: entry, style: .secondary),
            DetailAction(label: DT.t("复制详情", "Copy Details"), payload: sections.map { "\($0.field)\t\($0.value)" }.joined(separator: "\n"), style: .secondary)
        ]

        // 化合物 / 药物 / 糖链类条目提供结构图预览
        var imageUrl: String?
        if entry.hasPrefix("C") {
            imageUrl = "https://www.kegg.jp/Fig/compound/\(entry).gif"
        } else if entry.hasPrefix("D") {
            imageUrl = "https://www.kegg.jp/Fig/drug/\(entry).gif"
        } else if entry.hasPrefix("G") {
            imageUrl = "https://www.kegg.jp/Fig/glycan/\(entry).gif"
        }

        return DetailModel(
            headerTitle: entry,
            headerSubtitle: sections.first?.value,
            headerMeta: nil,
            sections: kvSections,
            freeTextBlocks: [],
            actions: actions,
            xlinks: [],
            webUrl: "https://www.kegg.jp/entry/\(entry)",
            imageUrl: imageUrl
        )
    }

    // MARK: - Parsing

    struct EntrySection {
        var field: String
        var value: String
    }

    private func parseEntry(_ text: String) -> [EntrySection] {
        var out: [EntrySection] = []
        var current: EntrySection?

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            if lineStr.isEmpty { continue }
            if lineStr.hasPrefix(" ") {
                // Continuation line
                if var cur = current {
                    cur.value += "\n" + lineStr.trimmingCharacters(in: .whitespaces)
                    current = cur
                }
            } else {
                if let cur = current { out.append(cur) }
                if let spaceIdx = lineStr.firstIndex(of: " ") {
                    let field = String(lineStr[..<spaceIdx])
                    let value = String(lineStr[lineStr.index(after: spaceIdx)...])
                    current = EntrySection(field: field, value: value)
                } else {
                    current = EntrySection(field: lineStr, value: "")
                }
            }
        }
        if let cur = current { out.append(cur) }
        return out
    }

    // MARK: - Auto-detect KEGG database from query pattern

    private func detectDatabase(query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespaces)

        // K number → KO (e.g., K00001)
        if q.matches("^K\\d{5}$") { return "ko" }
        // M number → module (e.g., M00001)
        if q.matches("^M\\d{5}$") { return "module" }
        // C number → compound (e.g., C00031)
        if q.matches("^C\\d{5}$") { return "compound" }
        // D number → drug (e.g., D00123)
        if q.matches("^D\\d{5}$") { return "drug" }
        // H number → disease (e.g., H01421)
        if q.matches("^H\\d{5}$") { return "disease" }
        // EC number → enzyme (e.g., 2.7.1.1)
        if q.matches("^\\d+\\.\\d+\\.\\d+\\.\\d+$") { return "enzyme" }
        // pathway entry (e.g., hsa00010, map00010)
        if q.matches("^\\w{2,5}\\d{5}$") { return "pathway" }
        // genome entry (e.g., T01001)
        if q.matches("^T\\d{5}$") { return "genome" }

        // Default: pathway (keyword search)
        return "pathway"
    }

}

// MARK: - String regex helper

extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
