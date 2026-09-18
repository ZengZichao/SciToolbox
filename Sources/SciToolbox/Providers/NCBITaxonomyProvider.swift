import Foundation

// MARK: - NCBI Taxonomy Provider

/// NCBI Taxonomy search via E-utilities.
final class NCBITaxonomyProvider: ToolProvider {
    let id = "ncbi_taxonomy"
    var name: String { DT.t("NCBI 分类检索", "NCBI Taxonomy Search") }
    let category: ToolCategory = .taxonomy
    let iconName = "tree"
    var placeholder: String { DT.t("物种名 / TaxID", "Species name / TaxID") }
    var dataSourceNote: String { DT.t("数据来源：NCBI Taxonomy (eutils.ncbi.nlm.nih.gov)", "Data source: NCBI Taxonomy (eutils.ncbi.nlm.nih.gov)") }

    private let base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

    func search(query: String) async throws -> SearchResult {
        let searchURL = buildURL("esearch", params: [
            "db": "taxonomy", "term": query, "retmode": "json", "retmax": "30"
        ])
        let searchResult = try await APIClient.shared.getJSON(searchURL)
        let ids = searchResult["esearchresult"]["idlist"].arrayValue.compactMap { $0.string }

        guard !ids.isEmpty else { return SearchResult(items: [], total: nil) }

        let sumURL = buildURL("esummary", params: [
            "db": "taxonomy", "id": ids.joined(separator: ","), "retmode": "json"
        ])
        let sum = try await APIClient.shared.getJSON(sumURL)
        let map = sum["result"]

        var items: [ResultItem] = []
        for id in ids {
            let t = map[id]
            let sciName = t["scientificname"].string ?? ""
            let commonName = t["commonname"].string ?? t["othernames"].arrayValue.first?.string ?? ""
            let rank = t["rank"].string ?? ""
            let rankCN = RankName.cn(rank)

            items.append(ResultItem(
                id: id,
                title: sciName.isEmpty ? "TaxID: \(id)" : sciName,
                subtitle: commonName.isEmpty ? nil : commonName,
                badge: id,
                meta: rankCN.isEmpty ? nil : rankCN,
                extra: ["taxid": id, "name": sciName]
            ))
        }

        return SearchResult(items: items, total: nil)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let taxid = context?["taxid"] ?? id
        let sumURL = buildURL("esummary", params: [
            "db": "taxonomy", "id": taxid, "retmode": "json"
        ])
        let sum = try await APIClient.shared.getJSON(sumURL)
        let t = sum["result"][taxid]

        let sciName = t["scientificname"].string ?? ""
        let commonName = t["commonname"].string ?? ""
        let rank = t["rank"].string ?? ""
        let rankCN = RankName.cn(rank)

        // Build lineage
        // P2-4：esummary JSON 中既无 lineageex 也无 lineage，谱系改用 efetch（XML）获取
        var lineageRows: [KVRow] = await fetchLineage(taxid)
        // Add self
        lineageRows.append(KVRow(rankCN, sciName, copyable: true))

        var infoRows: [KVRow] = [
            KVRow("TaxID", taxid, copyable: true),
            KVRow(DT.t("学名", "Scientific name"), sciName),
        ]
        if !commonName.isEmpty { infoRows.append(KVRow(DT.t("常用名", "Common name"), commonName)) }
        infoRows.append(KVRow(DT.t("分类等级", "Rank"), rankCN.isEmpty ? rank : rankCN))

        var xlinks: [XLink] = []
        xlinks.append(XLink(toolId: "gbif", query: sciName, label: "GBIF: \(sciName)"))
        if !sciName.isEmpty {
            xlinks.append(XLink(toolId: "ncbi_gene", query: sciName, label: DT.t("NCBI 基因: \(sciName)", "NCBI Gene: \(sciName)")))
        }

        return DetailModel(
            headerTitle: sciName.isEmpty ? "TaxID: \(taxid)" : sciName,
            headerSubtitle: commonName.isEmpty ? nil : commonName,
            headerMeta: [rankCN].filter { !$0.isEmpty },
            sections: [
                KVSection(title: DT.t("基本信息", "Basic Info"), rows: infoRows),
                KVSection(title: DT.t("分类谱系", "Lineage"), rows: lineageRows)
            ],
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制 TaxID", "Copy TaxID"), payload: taxid, style: .secondary)],
            xlinks: xlinks,
            webUrl: "https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=\(taxid)"
        )
    }

    private func buildURL(_ tool: String, params: [String: String]) -> String {
        buildQueryURL("\(base)/\(tool).fcgi", params: params)
    }

    // MARK: - Lineage (efetch XML)

    /// efetch 返回的 XML 含 `<LineageEx>`（逐级带 Rank），esummary JSON 中无谱系字段。
    private func fetchLineage(_ taxid: String) async -> [KVRow] {
        let url = buildURL("efetch", params: ["db": "taxonomy", "id": taxid, "retmode": "xml"])
        guard let data = try? await APIClient.shared.getRaw(url) else { return [] }
        let items = LineageExParser(data: data).parse()
        return items.map { KVRow(RankName.cn($0.rank), $0.scientificName, copyable: true) }
    }
}

/// 解析 NCBI efetch taxonomy XML 的 `<LineageEx>` 段。
private final class LineageExParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var inLineageEx = false
    private var currentElement = ""
    private var currentTaxId = ""
    private var currentName = ""
    private var currentRank = ""
    private var items: [(rank: String, scientificName: String)] = []

    init(data: Data) {
        self.data = data
        super.init()
    }

    func parse() -> [(rank: String, scientificName: String)] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "LineageEx" {
            inLineageEx = true
        } else if inLineageEx {
            currentElement = elementName
            if elementName == "Taxon" {
                currentTaxId = ""
                currentName = ""
                currentRank = ""
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inLineageEx else { return }
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentElement {
        case "TaxId": currentTaxId += s
        case "ScientificName": currentName += s
        case "Rank": currentRank += s
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Taxon", inLineageEx {
            items.append((currentRank, currentName))
        } else if elementName == "LineageEx" {
            inLineageEx = false
        }
    }
}
