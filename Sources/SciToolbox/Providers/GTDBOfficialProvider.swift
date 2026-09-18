import Foundation

// MARK: - GTDB Official Provider

/// GTDB official taxonomy tree browser — uses official GTDB API.
/// Starts from domain level (Archaea/Bacteria), drill down through ranks.
final class GTDBOfficialProvider: ToolProvider {
    let id = "gtdb_official"
    var name: String { DT.t("GTDB 官方分类", "GTDB Official Taxonomy") }
    let category: ToolCategory = .taxonomy
    let iconName = "globe"
    var placeholder: String { DT.t("分类名（留空浏览域级）", "Taxon name (leave empty to browse domains)") }
    var dataSourceNote: String { DT.t("数据来源：GTDB 官方 API (gtdb-api.ecogenomic.org)", "Data source: GTDB official API (gtdb-api.ecogenomic.org)") }

    private let base = "https://gtdb-api.ecogenomic.org"

    func search(query: String) async throws -> SearchResult {
        let q = query.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            // Return domain-level taxa as initial results
            return SearchResult(items: [
                ResultItem(id: "d__Archaea", title: "Archaea", badge: DT.t("域", "Domain"), meta: DT.t("古菌域", "Archaea domain"), extra: ["taxon": "d__Archaea"]),
                ResultItem(id: "d__Bacteria", title: "Bacteria", badge: DT.t("域", "Domain"), meta: DT.t("细菌域", "Bacteria domain"), extra: ["taxon": "d__Bacteria"]),
            ], total: 2)
        }

        // Search by name
        let url = "\(base)/taxon/search/\(urlEncodePath(q))?limit=30"
        let data = try await APIClient.shared.getJSON(url)

        if data["detail"].string != nil {
            throw APIError.notFound(data["detail"].string ?? DT.t("未找到", "Not found"))
        }

        let matches = data["matches"].arrayValue
        var items: [ResultItem] = []
        for taxon in matches {
            guard let taxonStr = taxon.string else { continue }
            let parsed = parseTaxon(taxonStr)
            items.append(ResultItem(
                id: taxonStr,
                title: parsed.name,
                badge: parsed.rankName,
                meta: taxonStr,
                extra: ["taxon": taxonStr]
            ))
        }

        return SearchResult(items: items, total: items.count)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let taxon = context?["taxon"] ?? id
        let url = "\(base)/taxon/\(urlEncodePath(taxon))"
        let data = try await APIClient.shared.getJSON(url)

        if data["detail"].string != nil {
            throw APIError.notFound(data["detail"].string ?? DT.t("未找到该分类", "Taxon not found"))
        }

        let parsed = parseTaxon(taxon)
        // GTDB API returns children as an array at the top level.
        // For genome leaf nodes, the response may be a non-array object —
        // in that case there are simply no child taxa to display.
        let children: [JSON]
        if data.value is [Any] {
            children = data.arrayValue
        } else {
            children = []
        }

        var childRows: [KVRow] = []
        var xlinks: [XLink] = []

        for child in children {
            let childTaxon = child["taxon"].string ?? ""
            let total = child["total"].int ?? 0
            let isGenome = child["isGenome"].bool ?? false
            if !childTaxon.isEmpty {
                let cp = parseTaxon(childTaxon)
                let label = "\(cp.name)\(total > 0 ? " (\(total))" : "")\(isGenome ? DT.t(" [基因组]", " [genome]") : "")"
                childRows.append(KVRow(cp.rankName, label, copyable: true))
                if !isGenome {
                    xlinks.append(XLink(toolId: "gtdb_official", query: childTaxon, label: DT.t("下钻: \(cp.name)", "Drill down: \(cp.name)")))
                }
            }
        }

        var sections: [KVSection] = []
        let infoRows: [KVRow] = [
            KVRow(DT.t("分类名", "Taxon name"), parsed.name, copyable: true),
            KVRow(DT.t("完整标记", "Full marker"), taxon, copyable: true),
            KVRow(DT.t("等级", "Rank"), parsed.rankName),
        ]
        sections.append(KVSection(title: DT.t("分类信息", "Taxonomy Info"), rows: infoRows))

        if !childRows.isEmpty {
            sections.append(KVSection(title: DT.t("下级分类 (\(childRows.count))", "Child taxa (\(childRows.count))"), rows: childRows))
        }

        return DetailModel(
            headerTitle: parsed.name,
            headerSubtitle: parsed.rankName,
            headerMeta: [taxon],
            sections: sections,
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制分类名", "Copy Taxon"), payload: taxon, style: .secondary)],
            xlinks: xlinks,
            webUrl: "https://gtdb.ecogenomic.org/tree?r=\(taxon.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? taxon)"
        )
    }

    // MARK: - Helpers

    private func parseTaxon(_ taxon: String) -> (rank: String, rankName: String, name: String) {
        if let idx = taxon.range(of: "__") {
            let rank = String(taxon[..<idx.lowerBound])
            let name = String(taxon[idx.upperBound...])
            return (rank, GTDBRank.name(rank), name)
        }
        return ("", "", taxon)
    }

}
