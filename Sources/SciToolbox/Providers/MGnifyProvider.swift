import Foundation

// MARK: - MGnify Provider

/// MGnify metagenomics database — EBI REST API (JSON:API format).
final class MGnifyProvider: ToolProvider {
    let id = "mgnify"
    var name: String { DT.t("MGnify 微生物组", "MGnify Microbiome") }
    let category: ToolCategory = .taxonomy
    let iconName = "circle.hexagongrid"
    var placeholder: String { DT.t("关键词 / Accession", "Keyword / Accession") }
    var dataSourceNote: String { DT.t("数据来源：EBI MGnify (www.ebi.ac.uk/metagenomics)", "Data source: EBI MGnify (www.ebi.ac.uk/metagenomics)") }

    private let base = "https://www.ebi.ac.uk/metagenomics/api/v1"

    func search(query: String) async throws -> SearchResult {
        let url = buildQueryURL("\(base)/studies", params: [
            "q": query, "page_size": "20"
        ])
        let data = try await APIClient.shared.getJSON(url)

        var items: [ResultItem] = []
        for s in data["data"].arrayValue {
            let a = s["attributes"]
            let accession = a["accession"].string ?? s["id"].string ?? ""
            let name = a["study-name"].string ?? ""
            let biome = biomeOf(s)
            let samplesCount = a["samples-count"].int ?? 0

            items.append(ResultItem(
                id: accession,
                title: name.isEmpty ? accession : name,
                subtitle: biome.isEmpty ? nil : biome,
                badge: accession,
                meta: "\(samplesCount) samples",
                extra: ["accession": accession]
            ))
        }

        let count = data["meta"]["pagination"]["count"].int ?? items.count
        return SearchResult(items: items, total: count)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let accession = context?["accession"] ?? id
        let url = "\(base)/studies/\(urlEncodePath(accession))"
        let data = try await APIClient.shared.getJSON(url)
        let s = data["data"]
        let a = s["attributes"]

        let name = a["study-name"].string ?? ""
        let abstract = a["study-abstract"].string ?? ""
        let secondaryAcc = a["secondary-accession"].string ?? ""
        let bioproject = a["bioproject"].string ?? ""
        let samplesCount = a["samples-count"].int ?? 0
        let centre = a["centre-name"].string ?? ""
        let lastUpdate = a["last-update"].string ?? ""
        let biome = biomeOf(s)

        var rows: [KVRow] = [
            KVRow("Accession", accession, copyable: true),
            KVRow(DT.t("名称", "Name"), name),
        ]
        if !secondaryAcc.isEmpty { rows.append(KVRow(DT.t("次要编号", "Secondary accession"), secondaryAcc)) }
        if !bioproject.isEmpty { rows.append(KVRow("BioProject", bioproject, copyable: true)) }
        if !biome.isEmpty { rows.append(KVRow(DT.t("生物群系", "Biome"), biome)) }
        rows.append(KVRow(DT.t("样本数", "Sample count"), "\(samplesCount)"))
        if !centre.isEmpty { rows.append(KVRow(DT.t("中心", "Centre"), centre)) }
        if !lastUpdate.isEmpty { rows.append(KVRow(DT.t("最后更新", "Last updated"), lastUpdate)) }

        var sections: [KVSection] = [KVSection(title: DT.t("研究信息", "Study Info"), rows: rows)]
        if !abstract.isEmpty {
            sections.append(KVSection(title: DT.t("摘要", "Abstract"), rows: [KVRow("", abstract)]))
        }

        return DetailModel(
            headerTitle: name.isEmpty ? accession : name,
            headerSubtitle: accession,
            headerMeta: [biome].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制 Accession", "Copy Accession"), payload: accession, style: .secondary)],
            xlinks: [],
            webUrl: "https://www.ebi.ac.uk/metagenomics/studies/\(accession)"
        )
    }

    private func biomeOf(_ s: JSON) -> String {
        let bd = s["relationships"]["biomes"]["data"]
        if let firstId = bd.arrayValue.first?["id"].string {
            return firstId.split(separator: ":").dropFirst().joined(separator: " › ")
        }
        return ""
    }

}
