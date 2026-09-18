import Foundation

// MARK: - PubMed Provider

/// PubMed literature search via NCBI E-utilities.
/// esearch → esummary for search; efetch for abstract.
final class PubMedProvider: ToolProvider {
    let id = "pubmed"
    var name: String { DT.t("PubMed 文献", "PubMed Literature") }
    let category: ToolCategory = .literature
    let iconName = "doc.text"
    var placeholder: String { DT.t("关键词 / PMID / DOI", "Keyword / PMID / DOI") }
    var dataSourceNote: String { DT.t("数据来源：NCBI PubMed (eutils.ncbi.nlm.nih.gov)", "Data source: NCBI PubMed (eutils.ncbi.nlm.nih.gov)") }

    var pickerOptions: [PickerOption]? = [
        PickerOption(id: "all", label: DT.t("全部时间", "All time"), example: "cancer"),
        PickerOption(id: "5y", label: DT.t("近5年", "Past 5y"), example: "CRISPR"),
        PickerOption(id: "10y", label: DT.t("近10年", "Past 10y"), example: "p53"),
        PickerOption(id: "2y", label: DT.t("近2年", "Past 2y"), example: "SARS-CoV-2"),
    ]
    var defaultPickerId: String? = "all"

    private let base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

    func search(query: String) async throws -> SearchResult {
        try await search(query: query, offset: 0, pickerId: nil)
    }

    func search(query: String, offset: Int, pickerId: String?) async throws -> SearchResult {
        let pageSize = 20
        let yearFilter = buildYearFilter(pickerId ?? defaultPickerId ?? "all")
        let fullQuery = yearFilter.isEmpty ? query : "\(query) AND \(yearFilter)"
        // Step 1: esearch to get PMIDs
        let searchURL = buildURL("esearch", params: [
            "db": "pubmed", "term": fullQuery, "retmode": "json",
            "retmax": String(pageSize), "retstart": String(offset)
        ])
        let searchResult = try await APIClient.shared.getJSON(searchURL)
        let ids = searchResult["esearchresult"]["idlist"].arrayValue.compactMap { $0.string }
        // NCBI esearch 的 count 是字符串（如 "15234"），需兼容；解析失败才退回 ids.count
        let countRaw = searchResult["esearchresult"]["count"]
        let total = countRaw.int ?? Int(countRaw.string ?? "") ?? ids.count

        guard !ids.isEmpty else { return SearchResult(items: [], total: 0) }

        // Step 2: esummary to get article summaries
        let sumURL = buildURL("esummary", params: [
            "db": "pubmed", "id": ids.joined(separator: ","), "retmode": "json"
        ])
        let sum = try await APIClient.shared.getJSON(sumURL)
        let map = sum["result"]

        var items: [ResultItem] = []
        for id in ids {
            let a = map[id]
            let title = a["title"].string ?? ""
            let authors = a["authors"].arrayValue.compactMap { $0["name"].string }
            let journal = a["fulljournalname"].string ?? a["source"].string ?? ""
            let pubdate = a["pubdate"].string ?? ""

            items.append(ResultItem(
                id: id,
                title: title.isEmpty ? DT.t("（无标题）", "(No title)") : title,
                subtitle: authors.isEmpty ? journal : "\(authors.prefix(3).joined(separator: ", "))\(authors.count > 3 ? DT.t(" 等", " et al.") : "")",
                badge: "PMID: \(id)",
                meta: "\(journal)\(pubdate.isEmpty ? "" : " · \(pubdate)")",
                extra: ["pmid": id]
            ))
        }

        return SearchResult(items: items, total: total, hasMore: offset + items.count < total)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let pmid = context?["pmid"] ?? id

        // Fetch abstract via efetch
        let url = buildURL("efetch", params: [
            "db": "pubmed", "id": pmid, "retmode": "text", "rettype": "abstract"
        ])
        let abstractText = try await APIClient.shared.getText(url)

        // Also fetch summary for metadata
        let sumURL = buildURL("esummary", params: [
            "db": "pubmed", "id": pmid, "retmode": "json"
        ])
        let sum = try await APIClient.shared.getJSON(sumURL)
        let a = sum["result"][pmid]

        let title = a["title"].string ?? ""
        let authors = a["authors"].arrayValue.compactMap { $0["name"].string }
        let journal = a["fulljournalname"].string ?? a["source"].string ?? ""
        let pubdate = a["pubdate"].string ?? ""
        let volume = a["volume"].string ?? ""
        let issue = a["issue"].string ?? ""
        let pages = a["pages"].string ?? ""
        let doi = a["doi"].string ?? ""
        let pubtypes = a["pubtype"].arrayValue.compactMap { $0.string }

        var rows: [KVRow] = [
            KVRow("PMID", pmid, copyable: true),
            KVRow("DOI", doi, copyable: true, link: ProviderHelpers.doiURL(doi)),
            KVRow(DT.t("作者", "Authors"), ProviderHelpers.formatAuthors(authors), copyable: authors.count > 3),
            KVRow(DT.t("期刊", "Journal"), journal),
            KVRow(DT.t("发表日期", "Published"), pubdate),
        ]
        if !volume.isEmpty || !issue.isEmpty || !pages.isEmpty {
            rows.append(KVRow(DT.t("卷期页", "Volume/Issue/Pages"), "\(volume)(\(issue)): \(pages)"))
        }
        if !pubtypes.isEmpty { rows.append(KVRow(DT.t("类型", "Type"), pubtypes.joined(separator: ", "))) }

        var xlinks: [XLink] = []
        if !doi.isEmpty {
            xlinks.append(ProviderHelpers.xlink("europepmc", doi, "Europe PMC: \(doi)"))
        }

        var freeTexts: [FreeTextBlock] = []
        if !abstractText.isEmpty {
            freeTexts.append(FreeTextBlock(title: DT.t("摘要", "Abstract"), text: abstractText.trimmingCharacters(in: .whitespacesAndNewlines), copyable: true))
        }

        var actions: [DetailAction] = []
        if !authors.isEmpty {
            let bib = ExportUtil.bibtex(pmid: pmid, title: title, authors: authors, journal: journal, year: pubdate)
            actions.append(DetailAction(label: DT.t("复制 BibTeX", "Copy BibTeX"), payload: bib, style: .secondary))
            actions.append(DetailAction(label: DT.t("导出 BibTeX", "Export BibTeX"), payload: bib, style: .secondary,
                                        kind: .export, exportFileName: "PMID_\(pmid)", exportExt: "bib"))
            let ris = ExportUtil.ris(title: title, authors: authors, journal: journal, year: pubdate,
                                     pmid: pmid, doi: doi, volume: volume, issue: issue, pages: pages)
            actions.append(DetailAction(label: DT.t("复制 RIS", "Copy RIS"), payload: ris, style: .secondary))
            actions.append(DetailAction(label: DT.t("导出 RIS", "Export RIS"), payload: ris, style: .secondary,
                                        kind: .export, exportFileName: "PMID_\(pmid)", exportExt: "ris"))
        }

        return DetailModel(
            headerTitle: title.isEmpty ? "PMID: \(pmid)" : title,
            headerSubtitle: authors.prefix(3).joined(separator: ", ") + (authors.count > 3 ? DT.t(" 等", " et al.") : ""),
            headerMeta: [journal, pubdate].filter { !$0.isEmpty },
            sections: [KVSection(title: DT.t("文献信息", "Article Info"), rows: rows)],
            freeTextBlocks: freeTexts,
            actions: actions,
            xlinks: xlinks,
            webUrl: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/"
        )
    }

    private func buildURL(_ tool: String, params: [String: String]) -> String {
        buildQueryURL("\(base)/\(tool).fcgi", params: params)
    }

    private func buildYearFilter(_ filterId: String) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        switch filterId {
        case "2y":
            let start = currentYear - 2
            return "(\"\(start)\"[PDAT] : \"\(currentYear + 1)\"[PDAT])"
        case "5y":
            let start = currentYear - 5
            return "(\"\(start)\"[PDAT] : \"\(currentYear + 1)\"[PDAT])"
        case "10y":
            let start = currentYear - 10
            return "(\"\(start)\"[PDAT] : \"\(currentYear + 1)\"[PDAT])"
        default:
            return ""
        }
    }
}
