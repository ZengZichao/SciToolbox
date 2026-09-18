import Foundation

// MARK: - GO Provider

/// GO ontology search via EBI QuickGO REST API.
final class GOProvider: ToolProvider {
    let id = "go"
    var name: String { DT.t("GO 术语查询", "GO Term Search") }
    let category: ToolCategory = .functionCategory
    let iconName = "circle.grid.2x2"
    var placeholder: String { DT.t("GO ID / 关键词", "GO ID / Keyword") }
    var dataSourceNote: String { DT.t("数据来源：EBI QuickGO (www.ebi.ac.uk/QuickGO)", "Data source: EBI QuickGO (www.ebi.ac.uk/QuickGO)") }

    private let base = "https://www.ebi.ac.uk/QuickGO/services/ontology/go"

    static let aspectCN: [String: (zh: String, en: String, short: String)] = [
        "biological_process": ("生物学过程", "Biological Process", "BP"),
        "cellular_component": ("细胞组分", "Cellular Component", "CC"),
        "molecular_function": ("分子功能", "Molecular Function", "MF"),
    ]

    static func aspectInfo(_ aspect: String) -> (name: String, short: String)? {
        guard let a = aspectCN[aspect] else { return nil }
        return (DT.t(a.zh, a.en), a.short)
    }

    func search(query: String) async throws -> SearchResult {
        let url = buildQueryURL(base + "/search", params: [
            "query": query, "limit": "50", "page": "1"
        ])
        let data = try await APIClient.shared.getJSON(url)

        var items: [ResultItem] = []
        for t in data["results"].arrayValue {
            let goId = t["id"].string ?? ""
            let name = t["name"].string ?? ""
            let aspect = t["aspect"].string ?? ""
            let aspectInfo = Self.aspectInfo(aspect)

            items.append(ResultItem(
                id: goId,
                title: name.isEmpty ? goId : name,
                badge: goId,
                meta: aspectInfo?.name ?? aspect,
                extra: ["goId": goId]
            ))
        }

        return SearchResult(items: items, total: nil)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let goId = context?["goId"] ?? id
        let encodedId = urlEncodePath(goId)

        // Fetch term, ancestors, and children in parallel
        // QuickGO 所有 term 端点都是 {numberOfHits, results} 信封结构（P1-2/3/4）
        async let termResult = APIClient.shared.getJSON(base + "/terms/" + encodedId)
        async let ancResult = fetchList(base + "/terms/" + encodedId + "/ancestors", excluding: goId)
        async let childResult = fetchList(base + "/terms/" + encodedId + "/children", excluding: goId)

        let termRaw = try await termResult
        let ancestors = await ancResult
        let children = await childResult

        let term = unwrapResults(termRaw).first.flatMap(normalizeTerm) ?? GOTerm(
            goId: goId, name: "", definition: "", aspect: "", aspectName: "", aspectShort: "", isObsolete: false, synonyms: []
        )

        var rows: [KVRow] = [
            KVRow("GO ID", term.goId, copyable: true),
            KVRow(DT.t("名称", "Name"), term.name),
            KVRow(DT.t("类别", "Category"), term.aspectName),
        ]
        if term.isObsolete { rows.append(KVRow(DT.t("状态", "Status"), DT.t("已废弃", "Obsolete"))) }

        var sections: [KVSection] = [KVSection(title: DT.t("术语信息", "Term Info"), rows: rows)]

        if !term.definition.isEmpty {
            sections.append(KVSection(title: DT.t("定义", "Definition"), rows: [KVRow("", term.definition)]))
        }

        if !term.synonyms.isEmpty {
            sections.append(KVSection(title: DT.t("同义词", "Synonyms"), rows: term.synonyms.map { KVRow("", $0) }))
        }

        if !ancestors.isEmpty {
            sections.append(KVSection(title: DT.t("祖先节点", "Ancestors"), rows: ancestors.prefix(40).map { a in
                KVRow(a.aspectShort, a.goId + " — " + a.name, copyable: true)
            }))
        }

        if !children.isEmpty {
            sections.append(KVSection(title: DT.t("子节点", "Children"), rows: children.prefix(60).map { c in
                KVRow(c.aspectShort, c.goId + " — " + c.name, copyable: true)
            }))
        }

        return DetailModel(
            headerTitle: term.name.isEmpty ? goId : term.name,
            headerSubtitle: goId,
            headerMeta: [term.aspectName].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制 GO ID", "Copy GO ID"), payload: goId, style: .secondary)],
            xlinks: [XLink(toolId: "uniprot", query: goId, label: DT.t("UniProt: 搜索含此 GO 的蛋白", "UniProt: Search proteins with this GO"))],
            webUrl: "https://www.ebi.ac.uk/QuickGO/term/" + goId
        )
    }

    // MARK: - Fetching helpers

    private func fetchList(_ url: String, excluding target: String) async -> [GOTerm] {
        do {
            let data = try await APIClient.shared.getJSON(url)
            return unwrapResults(data).compactMap { normalizeTerm($0) }.filter { $0.goId != target }
        } catch {
            return []
        }
    }

    /// 统一解包 QuickGO 的 {numberOfHits, results} 信封；兼容裸数组响应。
    private func unwrapResults(_ data: JSON) -> [JSON] {
        let wrapped = data["results"].arrayValue
        return wrapped.isEmpty ? data.arrayValue : wrapped
    }

    // MARK: - Normalization

    struct GOTerm {
        var goId: String
        var name: String
        var definition: String
        var aspect: String
        var aspectName: String
        var aspectShort: String
        var isObsolete: Bool
        var synonyms: [String]
    }

    private func normalizeTerm(_ t: JSON) -> GOTerm? {
        guard t["id"].string != nil else { return nil }
        // GO 的 definition 是对象 {text: ...} 而非字符串
        let def = t["definition"]["text"].string ?? t["definition"].string ?? ""
        let aspect = t["aspect"].string ?? ""
        let aspectInfo = Self.aspectInfo(aspect)

        let syns = t["synonyms"].arrayValue.compactMap { s -> String? in
            if let str = s.string { return str }
            return s["name"].string ?? s["value"].string
        }

        return GOTerm(
            goId: t["id"].string ?? "",
            name: t["name"].string ?? "",
            definition: def,
            aspect: aspect,
            aspectName: aspectInfo?.name ?? aspect,
            aspectShort: aspectInfo?.short ?? "",
            isObsolete: t["isObsolete"].bool ?? false,
            synonyms: syns
        )
    }
}
