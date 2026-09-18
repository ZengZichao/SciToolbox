import Foundation

// MARK: - GBIF Provider

/// GBIF species database — global biodiversity.
final class GBIFProvider: ToolProvider {
    let id = "gbif"
    var name: String { DT.t("GBIF 物种", "GBIF Species") }
    let category: ToolCategory = .taxonomy
    let iconName = "leaf"
    var placeholder: String { DT.t("物种名 / 关键词", "Species name / Keyword") }
    var dataSourceNote: String { DT.t("数据来源：GBIF (api.gbif.org)", "Data source: GBIF (api.gbif.org)") }

    private let base = "https://api.gbif.org/v1"

    func search(query: String) async throws -> SearchResult {
        let url = buildQueryURL("\(base)/species/search", params: [
            "q": query, "limit": "20"
        ])
        let data = try await APIClient.shared.getJSON(url)

        var items: [ResultItem] = []
        for s in data["results"].arrayValue {
            let key = s["key"].int.map(String.init) ?? ""
            let sciName = s["scientificName"].string ?? ""
            let canonical = s["canonicalName"].string ?? sciName
            let rank = s["rank"].string ?? ""
            let kingdom = s["kingdom"].string ?? ""
            let family = s["family"].string ?? ""

            items.append(ResultItem(
                id: key,
                title: sciName.isEmpty ? "Key: \(key)" : sciName,
                subtitle: canonical == sciName ? nil : canonical,
                badge: key,
                meta: [kingdom, family, rank].filter { !$0.isEmpty }.joined(separator: " · "),
                extra: ["key": key]
            ))
        }

        let count = data["count"].int ?? items.count
        return SearchResult(items: items, total: count)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let key = context?["key"] ?? id
        let url = "\(base)/species/\(urlEncodePath(key))"
        let s = try await APIClient.shared.getJSON(url)

        let sciName = s["scientificName"].string ?? ""
        let canonical = s["canonicalName"].string ?? sciName
        let authorship = s["authorship"].string ?? ""
        let rank = s["rank"].string ?? ""
        let taxStatus = s["taxonomicStatus"].string ?? ""
        let acceptedKey = s["acceptedKey"].int.map(String.init) ?? ""

        var rows: [KVRow] = [
            KVRow("Key", key, copyable: true),
            KVRow(DT.t("学名", "Scientific name"), sciName),
        ]
        if !canonical.isEmpty && canonical != sciName { rows.append(KVRow(DT.t("规范名", "Canonical name"), canonical)) }
        if !authorship.isEmpty { rows.append(KVRow(DT.t("命名作者", "Author"), authorship)) }
        if !rank.isEmpty { rows.append(KVRow(DT.t("等级", "Rank"), rank)) }
        if !taxStatus.isEmpty { rows.append(KVRow(DT.t("分类状态", "Taxonomic status"), taxStatus)) }
        if !acceptedKey.isEmpty { rows.append(KVRow(DT.t("接受名 Key", "Accepted key"), acceptedKey, copyable: true)) }

        // Classification
        let classRanks = ["kingdom", "phylum", "class", "order", "family", "genus", "species"]
        let classLabels = [DT.t("界", "Kingdom"), DT.t("门", "Phylum"), DT.t("纲", "Class"), DT.t("目", "Order"), DT.t("科", "Family"), DT.t("属", "Genus"), DT.t("种", "Species")]
        var classRows: [KVRow] = []
        for (i, rankKey) in classRanks.enumerated() {
            let val = s[rankKey].string ?? ""
            if !val.isEmpty {
                classRows.append(KVRow(classLabels[i], val))
            }
        }

        // 4.2：旧代码遍历 higherClassificationMap 后丢弃结果（空循环体），已删除。
        // 标准七阶已在 classRows 覆盖；古菌/病毒等缺少标准阶的类群可后续按需补充。

        var sections: [KVSection] = [KVSection(title: DT.t("基本信息", "Basic Info"), rows: rows)]
        if !classRows.isEmpty {
            sections.append(KVSection(title: DT.t("分类", "Classification"), rows: classRows))
        }

        // Fetch children and synonyms
        async let childrenResult = fetchSpeciesList("\(base)/species/\(key)/children?limit=50")
        async let synonymsResult = fetchSpeciesList("\(base)/species/\(key)/synonyms?limit=50")

        let children = try? await childrenResult
        let synonyms = try? await synonymsResult

        if let children = children, !children.isEmpty {
            sections.append(KVSection(title: DT.t("下级分类 (\(children.count))", "Child taxa (\(children.count))"), rows: children.map { c in
                KVRow(c.rank, "\(c.scientificName)\(c.canonicalName != c.scientificName ? " (\(c.canonicalName))" : "")", copyable: true)
            }))
        }

        if let synonyms = synonyms, !synonyms.isEmpty {
            sections.append(KVSection(title: DT.t("同物异名 (\(synonyms.count))", "Synonyms (\(synonyms.count))"), rows: synonyms.map { syn in
                KVRow(syn.rank, syn.scientificName)
            }))
        }

        var xlinks: [XLink] = []
        xlinks.append(XLink(toolId: "ncbi_taxonomy", query: canonical, label: DT.t("NCBI 分类: \(canonical)", "NCBI Taxonomy: \(canonical)")))

        return DetailModel(
            headerTitle: sciName.isEmpty ? "Key: \(key)" : sciName,
            headerSubtitle: canonical == sciName ? nil : canonical,
            headerMeta: [rank, taxStatus].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制 Key", "Copy Key"), payload: key, style: .secondary)],
            xlinks: xlinks,
            webUrl: "https://www.gbif.org/species/\(key)"
        )
    }

    // MARK: - Helpers

    struct SpeciesSummary {
        var key: String
        var scientificName: String
        var canonicalName: String
        var rank: String
    }

    private func fetchSpeciesList(_ urlString: String) async throws -> [SpeciesSummary] {
        let data = try await APIClient.shared.getJSON(urlString)
        return data["results"].arrayValue.compactMap { s in
            let key = s["key"].int.map(String.init) ?? ""
            guard !key.isEmpty else { return nil }
            return SpeciesSummary(
                key: key,
                scientificName: s["scientificName"].string ?? "",
                canonicalName: s["canonicalName"].string ?? s["scientificName"].string ?? "",
                rank: s["rank"].string ?? ""
            )
        }
    }

}
