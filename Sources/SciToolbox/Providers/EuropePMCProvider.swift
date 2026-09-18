import Foundation

// MARK: - EuropePMC Provider

/// Europe PMC literature search — EBI REST API.
final class EuropePMCProvider: ToolProvider {
    let id = "europepmc"
    var name: String { DT.t("Europe PMC 文献", "Europe PMC Literature") }
    let category: ToolCategory = .literature
    let iconName = "books.vertical"
    var placeholder: String { DT.t("关键词 / DOI / PMID", "Keyword / DOI / PMID") }
    var dataSourceNote: String { DT.t("数据来源：EBI Europe PMC (www.ebi.ac.uk/europepmc)", "Data source: EBI Europe PMC (www.ebi.ac.uk/europepmc)") }

    private let base = "https://www.ebi.ac.uk/europepmc/webservices/rest"

    func search(query: String) async throws -> SearchResult {
        guard query.count >= 2 else {
            throw APIError.invalidInput(DT.t("检索词至少 2 个字符", "Query must be at least 2 characters"))
        }

        let url = buildQueryURL("\(base)/search", params: [
            "query": query, "format": "json", "pageSize": "20", "resultType": "core"
        ])
        let data = try await APIClient.shared.getJSON(url)

        var items: [ResultItem] = []
        for rec in data["resultList"]["result"].arrayValue {
            let id = rec["id"].string ?? ""
            let source = rec["source"].string ?? ""
            let pmid = rec["pmid"].string ?? ""
            let title = rec["title"].string ?? ""
            let authorString = rec["authorString"].string ?? ""
            let journal = rec["journalTitle"].string ?? rec["journalInfo"]["journalTitle"].string ?? ""
            let pubYear = rec["pubYear"].string ?? rec["journalInfo"]["dateOfPublication"].string ?? ""
            let citedBy = rec["citedByCount"].int ?? 0
            let isOpenAccess = rec["isOpenAccess"].string == "Y"

            let badge = pmid.isEmpty ? "\(source):\(id)" : "PMID: \(pmid)"
            items.append(ResultItem(
                id: "\(source):\(id)",
                title: title.isEmpty ? DT.t("（无标题）", "(No title)") : title,
                subtitle: authorString,
                badge: badge,
                meta: "\(journal)\(pubYear.isEmpty ? "" : " · \(pubYear)")\(citedBy > 0 ? " · \(DT.t("引用 \(citedBy)", "Cited \(citedBy)"))" : "")\(isOpenAccess ? " · OA" : "")",
                extra: ["source": source, "id": id, "pmid": pmid]
            ))
        }

        let total = data["hitCount"].int ?? items.count
        return SearchResult(items: items, total: total)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let source = context?["source"] ?? "MED"
        let articleId = context?["id"] ?? id
        // Correct endpoint: /article/{source}/{id}?format=json
        let url = "\(base)/article/\(urlEncodePath(source))/\(urlEncodePath(articleId))?format=json"
        let resp = try await APIClient.shared.getJSON(url)

        // The article endpoint wraps the record in a "result" key.
        let rec = resp["result"].isNull ? resp : resp["result"]

        let id = rec["id"].string ?? articleId
        let pmid = rec["pmid"].string ?? ""
        let doi = rec["doi"].string ?? ""
        let title = rec["title"].string ?? ""
        let authorString = rec["authorString"].string ?? ""
        let journal = rec["journalTitle"].string ?? rec["journalInfo"]["journalTitle"].string ?? ""
        let pubYear = rec["pubYear"].string ?? rec["journalInfo"]["dateOfPublication"].string ?? ""
        let pubType = rec["pubType"].string ?? ""
        let citedBy = rec["citedByCount"].int ?? 0
        let isOpenAccess = rec["isOpenAccess"].string == "Y"
        let abstractText = rec["abstractText"].string ?? ""

        var rows: [KVRow] = []
        if !pmid.isEmpty { rows.append(KVRow("PMID", pmid, copyable: true)) }
        rows.append(KVRow("ID", "\(source):\(id)", copyable: true))
        if !doi.isEmpty { rows.append(KVRow("DOI", doi, copyable: true)) }
        if !journal.isEmpty { rows.append(KVRow(DT.t("期刊", "Journal"), journal)) }
        if !pubYear.isEmpty { rows.append(KVRow(DT.t("发表年份", "Year"), pubYear)) }
        if !pubType.isEmpty { rows.append(KVRow(DT.t("类型", "Type"), pubType)) }
        if !authorString.isEmpty { rows.append(KVRow(DT.t("作者", "Authors"), authorString)) }
        if citedBy > 0 { rows.append(KVRow(DT.t("被引次数", "Cited By"), "\(citedBy)")) }
        rows.append(KVRow(DT.t("开放获取", "Open Access"), isOpenAccess ? DT.t("是", "Yes") : DT.t("否", "No")))

        let sections: [KVSection] = [KVSection(title: DT.t("文献信息", "Article Info"), rows: rows)]

        var freeTexts: [FreeTextBlock] = []
        if !abstractText.isEmpty {
            freeTexts.append(FreeTextBlock(title: DT.t("摘要", "Abstract"), text: abstractText, copyable: true))
        }

        var xlinks: [XLink] = []
        if !pmid.isEmpty {
            xlinks.append(XLink(toolId: "pubmed", query: pmid, label: "PubMed: \(pmid)"))
        }
        if !doi.isEmpty {
            xlinks.append(XLink(toolId: "pdb", query: doi, label: DT.t("按 DOI 搜索 PDB", "Search PDB by DOI")))
        }

        let webUrl: String
        if !pmid.isEmpty {
            webUrl = "https://www.europepmc.org/article/MED/\(pmid)"
        } else {
            webUrl = "https://www.europepmc.org/article/\(source)/\(id)"
        }

        // Build citation export actions
        var actions: [DetailAction] = [DetailAction(label: DT.t("复制 ID", "Copy ID"), payload: id, style: .secondary)]
        if !title.isEmpty {
            let authorList = authorString.split(separator: ", ").map(String.init)
            let bib = ExportUtil.bibtex(pmid: pmid, title: title, authors: authorList, journal: journal, year: pubYear)
            actions.append(DetailAction(label: DT.t("复制 BibTeX", "Copy BibTeX"), payload: bib, style: .secondary))
            actions.append(DetailAction(label: DT.t("导出 BibTeX", "Export BibTeX"), payload: bib, style: .secondary,
                                        kind: .export, exportFileName: "EuropePMC_\(id)", exportExt: "bib"))
            let ris = ExportUtil.ris(title: title, authors: authorList, journal: journal, year: pubYear,
                                     pmid: pmid, doi: doi)
            actions.append(DetailAction(label: DT.t("复制 RIS", "Copy RIS"), payload: ris, style: .secondary))
            actions.append(DetailAction(label: DT.t("导出 RIS", "Export RIS"), payload: ris, style: .secondary,
                                        kind: .export, exportFileName: "EuropePMC_\(id)", exportExt: "ris"))
        }

        return DetailModel(
            headerTitle: title.isEmpty ? "ID: \(id)" : title,
            headerSubtitle: authorString,
            headerMeta: [journal, pubYear].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: freeTexts,
            actions: actions,
            xlinks: xlinks,
            webUrl: webUrl
        )
    }

}
