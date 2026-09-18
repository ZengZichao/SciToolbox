import Foundation

// MARK: - NCBI Gene Provider

/// NCBI Gene search + detail + related sequences via E-utilities.
final class NCBIGeneProvider: ToolProvider {
    let id = "ncbi_gene"
    var name: String { DT.t("NCBI 基因/序列", "NCBI Gene/Sequence") }
    let category: ToolCategory = .gene
    /// 注：SF Symbols 在本机系统字形目录中不含 "dna"（仅为 emoji 🧬），
    /// 使用 systemName:"dna" 会渲染为空白。改用可用的生命科学符号 "flask"。
    let iconName = "flask"
    var placeholder: String { DT.t("基因符号（如 TP53）", "Gene symbol (e.g. TP53)") }
    var dataSourceNote: String { DT.t("数据来源：NCBI Gene (eutils.ncbi.nlm.nih.gov)", "Data source: NCBI Gene (eutils.ncbi.nlm.nih.gov)") }

    private let base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

    func search(query: String) async throws -> SearchResult {
        // Validate gene symbol
        guard query.first?.isLetter == true || query.first?.isNumber == true else {
            throw APIError.invalidInput(DT.t("请输入合法基因符号（以字母或数字开头）", "Enter a valid gene symbol (starting with a letter or digit)"))
        }

        let term = "\(query)[Gene Name] OR \(query)[Gene Synonym]"
        let searchURL = buildURL("esearch", params: [
            "db": "gene", "term": term, "retmode": "json", "retmax": "20"
        ])
        let searchResult = try await APIClient.shared.getJSON(searchURL)
        let ids = searchResult["esearchresult"]["idlist"].arrayValue.compactMap { $0.string }

        guard !ids.isEmpty else { return SearchResult(items: [], total: nil) }

        let sumURL = buildURL("esummary", params: [
            "db": "gene", "id": ids.joined(separator: ","), "retmode": "json"
        ])
        let sum = try await APIClient.shared.getJSON(sumURL)
        let map = sum["result"]

        var items: [ResultItem] = []
        for id in ids {
            let g = map[id]
            let name = g["name"].string ?? ""
            let desc = g["description"].string ?? ""
            let organism = g["organism"]["scientificname"].string ?? ""
            let chromosome = g["chromosome"].string ?? g["genomicinfo"].arrayValue.first?["chr"].string ?? ""

            items.append(ResultItem(
                id: id,
                title: name.isEmpty ? id : "\(name) — \(desc)",
                subtitle: organism,
                badge: id,
                meta: chromosome.isEmpty ? nil : "Chr \(chromosome)",
                extra: ["uid": id, "name": name]
            ))
        }

        return SearchResult(items: items, total: nil)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let uid = context?["uid"] ?? id
        let sumURL = buildURL("esummary", params: [
            "db": "gene", "id": uid, "retmode": "json"
        ])
        let sum = try await APIClient.shared.getJSON(sumURL)
        let g = sum["result"][uid]

        guard g["name"].string != nil else {
            throw APIError.notFound(DT.t("未找到该基因", "Gene not found"))
        }

        let name = g["name"].string ?? ""
        let desc = g["description"].string ?? ""
        let organism = g["organism"]["scientificname"].string ?? ""
        let taxid = String(g["organism"]["taxid"].int ?? 0)
        let chromosome = g["chromosome"].string ?? ""
        let mapLocation = g["maplocation"].string ?? ""
        let summary = g["summary"].string ?? ""
        let aliases = g["otheraliases"].string?.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []

        var rows: [KVRow] = [
            KVRow("Gene ID", uid, copyable: true),
            KVRow(DT.t("符号", "Symbol"), name, copyable: true),
            KVRow(DT.t("描述", "Description"), desc),
            KVRow(DT.t("物种", "Organism"), organism),
        ]
        if !chromosome.isEmpty { rows.append(KVRow(DT.t("染色体", "Chromosome"), chromosome)) }
        if !mapLocation.isEmpty { rows.append(KVRow(DT.t("图谱位置", "Map Location"), mapLocation)) }
        if !aliases.isEmpty { rows.append(KVRow(DT.t("别名", "Aliases"), aliases.joined(separator: ", "))) }

        // Genomic info
        let genomicInfo = g["genomicinfo"].arrayValue
        if !genomicInfo.isEmpty {
            for (i, gi) in genomicInfo.enumerated() {
                let chr = gi["chr"].string ?? ""
                let start = String(gi["chrstart"].int ?? 0)
                let stop = String(gi["chrstop"].int ?? 0)
                let orient = gi["orientation"].string ?? ""
                rows.append(KVRow(DT.t("基因组\(i + 1)", "Genomic \(i + 1)"), "\(chr): \(start)-\(stop) (\(orient))"))
            }
        }

        // Fetch related sequences (nuccore + protein)
        // P2-13：任一子请求失败只降级为空，不再让整个详情页失败
        var seqRows: [KVRow] = []
        let nuccore = (try? await fetchSeqList(db: "nuccore", uid: uid)) ?? []
        let protein = (try? await fetchSeqList(db: "protein", uid: uid)) ?? []
        for s in nuccore.prefix(5) {
            seqRows.append(KVRow(s.accession, "\(s.title) (\(s.length) bp)", copyable: true))
        }
        for s in protein.prefix(5) {
            seqRows.append(KVRow(s.accession, "\(s.title) (\(s.length) aa)", copyable: true))
        }

        var sections: [KVSection] = [KVSection(title: DT.t("基因信息", "Gene Info"), rows: rows)]
        if !seqRows.isEmpty {
            sections.append(KVSection(title: DT.t("关联序列", "Related Sequences"), rows: seqRows))
        }

        var xlinks: [XLink] = []
        if !taxid.isEmpty && taxid != "0" {
            xlinks.append(XLink(toolId: "ncbi_taxonomy", query: taxid, label: DT.t("NCBI 分类: \(organism)", "NCBI Taxonomy: \(organism)")))
        }
        xlinks.append(XLink(toolId: "ensembl", query: name, label: "Ensembl: \(name)"))

        var freeTexts: [FreeTextBlock] = []
        if !summary.isEmpty {
            freeTexts.append(FreeTextBlock(title: DT.t("基因摘要", "Gene Summary"), text: summary, copyable: true))
        }

        return DetailModel(
            headerTitle: "\(name) — \(desc)",
            headerSubtitle: organism,
            headerMeta: [chromosome.isEmpty ? nil : "Chr \(chromosome)", mapLocation.isEmpty ? nil : mapLocation].compactMap { $0 },
            sections: sections,
            freeTextBlocks: freeTexts,
            actions: [DetailAction(label: DT.t("复制 Gene ID", "Copy Gene ID"), payload: uid, style: .secondary)],
            xlinks: xlinks,
            webUrl: "https://www.ncbi.nlm.nih.gov/gene/\(uid)"
        )
    }

    // MARK: - Sequence fetching

    struct SeqSummary {
        var accession: String
        var title: String
        var length: Int
    }

    private func fetchSeqList(db: String, uid: String) async throws -> [SeqSummary] {
        let term = "\(uid)[GeneID]"
        let searchURL = buildURL("esearch", params: [
            "db": db, "term": term, "retmode": "json", "retmax": "15"
        ])
        let s = try await APIClient.shared.getJSON(searchURL)
        let ids = s["esearchresult"]["idlist"].arrayValue.compactMap { $0.string }
        guard !ids.isEmpty else { return [] }

        let sumURL = buildURL("esummary", params: [
            "db": db, "id": ids.joined(separator: ","), "retmode": "json"
        ])
        let sum = try await APIClient.shared.getJSON(sumURL)
        let map = sum["result"]

        return ids.compactMap { id in
            let x = map[id]
            return SeqSummary(
                accession: x["accession"].string ?? x["caption"].string ?? id,   // P2-3：esummary 无 accession，编号在 caption
                title: x["title"].string ?? x["caption"].string ?? "",
                length: x["slen"].int ?? 0
            )
        }
    }

    private func buildURL(_ tool: String, params: [String: String]) -> String {
        buildQueryURL("\(base)/\(tool).fcgi", params: params)
    }
}
