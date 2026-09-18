import Foundation

// MARK: - Pfam Provider

/// Pfam / InterPro search via EBI Search + InterPro API.
final class PfamProvider: ToolProvider {
    let id = "pfam"
    let name = "Pfam / InterPro"
    let category: ToolCategory = .protein
    let iconName = "square.stack.3d.up"
    var placeholder: String { DT.t("蛋白家族名 / 关键词", "Protein family name / Keyword") }
    var dataSourceNote: String { DT.t("数据来源：EBI InterPro (www.ebi.ac.uk/interpro)", "Data source: EBI InterPro (www.ebi.ac.uk/interpro)") }

    private let ebiSearch = "https://www.ebi.ac.uk/ebisearch/ws/rest/pfam"
    private let interpro = "https://www.ebi.ac.uk/interpro/api/entry/pfam"

    func search(query: String) async throws -> SearchResult {
        guard query.count >= 2 else {
            throw APIError.invalidInput(DT.t("检索词至少 2 个字符", "Search term must be at least 2 characters"))
        }

        let url = buildQueryURL(ebiSearch, params: [
            "query": query, "format": "json", "size": "20"
        ])
        let data = try await APIClient.shared.getJSON(url)

        let entries = data["entries"].arrayValue
        let total = data["hitCount"].int ?? entries.count

        guard !entries.isEmpty else { return SearchResult(items: [], total: 0) }

        var items: [ResultItem] = []
        for e in entries {
            let acc = e["acc"].string ?? e["id"].string ?? ""
            // Fetch entry details for better display
            let detail = try? await fetchEntry(acc)
            items.append(ResultItem(
                id: acc,
                title: detail?.name ?? acc,
                subtitle: detail?.short,
                badge: acc,
                meta: detail?.type,
                extra: ["acc": acc]
            ))
        }

        return SearchResult(items: items, total: total)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let acc = (context?["acc"] ?? id).uppercased()
        let d = try await fetchEntry(acc)

        var rows: [KVRow] = [
            KVRow("Accession", d.accession, copyable: true),
            KVRow(DT.t("名称", "Name"), d.name),
            KVRow(DT.t("缩写", "Short name"), d.short),
            KVRow(DT.t("类型", "Type"), d.type),
            KVRow(DT.t("数据库", "Database"), d.sourceDatabase),
        ]
        if !d.integrated.isEmpty { rows.append(KVRow(DT.t("整合入", "Integrated into"), d.integrated, copyable: true)) }

        var sections: [KVSection] = [KVSection(title: DT.t("条目信息", "Entry Info"), rows: rows)]

        if !d.description.isEmpty {
            sections.append(KVSection(title: DT.t("描述", "Description"), rows: [KVRow("", d.description)]))
        }

        if !d.goTerms.isEmpty {
            sections.append(KVSection(title: DT.t("GO 注释", "GO annotation"), rows: d.goTerms.map { g in
                KVRow(g.id, g.name, copyable: true)
            }))
        }

        var xlinks: [XLink] = []
        for g in d.goTerms {
            xlinks.append(XLink(toolId: "go", query: g.id, label: "GO: \(g.name)"))
        }

        return DetailModel(
            headerTitle: d.name.isEmpty ? d.accession : d.name,
            headerSubtitle: d.accession,
            headerMeta: [d.type, d.short].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制 Accession", "Copy Accession"), payload: d.accession, style: .secondary)],
            xlinks: xlinks,
            webUrl: d.webUrl
        )
    }

    // MARK: - Entry fetching

    struct PfamEntry {
        var accession: String
        var name: String
        var short: String
        var type: String
        var sourceDatabase: String
        var integrated: String
        var description: String
        var goTerms: [(id: String, name: String)]
        var literatureCount: Int
        var webUrl: String
    }

    private func fetchEntry(_ acc: String) async throws -> PfamEntry {
        let url = "\(interpro)/\(urlEncodePath(acc))"
        let data = try await APIClient.shared.getJSON(url)
        let m = data["metadata"]
        let nameObj = m["name"]

        let descArr = m["description"].arrayValue
        let goArr = m["go_terms"].arrayValue
        let litArr = m["literature"].arrayValue

        return PfamEntry(
            accession: m["accession"].string ?? acc,
            name: nameObj["name"].string ?? "",
            short: nameObj["short"].string ?? "",
            type: m["type"].string ?? "",
            sourceDatabase: m["source_database"].string ?? "pfam",
            integrated: m["integrated"].string ?? "",
            description: stripHtml(descArr.first?["text"].string ?? ""),
            goTerms: goArr.compactMap { g in
                let id = g["identifier"].string ?? ""
                let name = g["name"].string ?? ""
                return name.isEmpty ? nil : (id, name)
            },
            literatureCount: litArr.count,
            webUrl: "https://www.ebi.ac.uk/interpro/entry/pfam/\(acc)"
        )
    }

    private func stripHtml(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
