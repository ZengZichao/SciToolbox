import Foundation

// MARK: - UniProt Provider

/// UniProt protein database — direct REST API (no proxy needed).
/// API: https://rest.uniprot.org/uniprotkb
final class UniProtProvider: ToolProvider {
    let id = "uniprot"
    var name: String { DT.t("UniProt 蛋白质", "UniProt Proteins") }
    let category: ToolCategory = .protein
    let iconName = "atom"
    var placeholder: String { DT.t("蛋白名 / 基因名 / Accession", "Protein / Gene / Accession") }
    var dataSourceNote: String { DT.t("数据来源：UniProt REST API (rest.uniprot.org)", "Data source: UniProt REST API (rest.uniprot.org)") }

    private let baseURL = "https://rest.uniprot.org/uniprotkb"

    func search(query: String) async throws -> SearchResult {
        try await search(query: query, offset: 0, pickerId: nil)
    }

    func search(query: String, offset: Int, pickerId: String?) async throws -> SearchResult {
        let pageSize = 30
        let fields = "accession,id,gene_names,protein_name,organism_name,length,reviewed"
        let url = buildQueryURL(baseURL + "/search", params: [
            "query": query, "format": "json", "size": String(pageSize),
            "offset": String(offset), "fields": fields
        ])
        let json = try await APIClient.shared.getJSON(url)

        var items: [ResultItem] = []
        for r in json["results"].arrayValue {
            let accession = r["primaryAccession"].string ?? ""
            let pName = Self.proteinName(of: r)
            let geneNames = r["genes"].arrayValue.compactMap { $0["geneName"]["value"].string }
            let organism = r["organism"]["scientificName"].string ?? ""
            let length = r["sequence"]["length"].int ?? 0
            let reviewed = Self.isReviewed(r)

            items.append(ResultItem(
                id: accession,
                title: pName.isEmpty ? accession : pName,
                subtitle: geneNames.isEmpty ? organism : geneNames.joined(separator: ", ") + " · " + organism,
                badge: accession,
                meta: (reviewed ? DT.t("已审核", "Reviewed") : DT.t("未审核", "Unreviewed")) + " · " + String(length) + " aa",
                extra: ["accession": accession]
            ))
        }

        let (total, hasMore) = ProviderHelpers.paginate(items: items, pageSize: pageSize)
        return SearchResult(items: items, total: total, hasMore: hasMore)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let accession = context?["accession"] ?? id
        let url = baseURL + "/" + urlEncodePath(accession) + "?format=json"
        let data = try await APIClient.shared.getJSON(url)

        // Extract function text
        var funcText = ""
        for c in data["comments"].arrayValue {
            if c["commentType"].string == "FUNCTION" {
                funcText = c["texts"].arrayValue.compactMap { $0["value"].string }.joined(separator: " ")
            }
        }

        // Extract GO annotations and domains
        var domains: [(type: String, id: String, name: String, xlink: XLink?)] = []
        var xlinks: [XLink] = []

        for d in data["dbReferences"].arrayValue {
            let type = d["type"].string ?? ""
            if type == "GO" {
                let term = d["properties"]["term"].string ?? ""
                if let sep = term.firstIndex(of: "!") {
                    let goId = String(term[..<sep])
                    let goName = String(term[term.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
                    xlinks.append(ProviderHelpers.xlink("go", goId, "GO: " + (goName.isEmpty ? goId : goName)))
                }
            } else if type == "Pfam" || type == "InterPro" {
                let pfId = d["id"].string ?? ""
                let nm = d["properties"]["entry name"].string ?? d["properties"]["entryName"].string ?? ""
                let xlink: XLink? = type == "Pfam" ? ProviderHelpers.xlink("pfam", pfId, "Pfam: " + (nm.isEmpty ? pfId : nm)) : nil
                domains.append((type, pfId, nm, xlink))
                if type == "Pfam" {
                    xlinks.append(ProviderHelpers.xlink("pfam", pfId, "Pfam: " + (nm.isEmpty ? pfId : nm)))
                }
            } else if type == "PDB" {
                let pdbId = d["id"].string ?? ""
                if !pdbId.isEmpty {
                    xlinks.append(ProviderHelpers.xlink("pdb", pdbId, "PDB: \(pdbId)"))
                }
            } else if type == "PubMed" {
                let pmid = d["id"].string ?? ""
                if !pmid.isEmpty {
                    xlinks.append(ProviderHelpers.xlink("pubmed", pmid, "PubMed: \(pmid)"))
                }
            } else if type == "Ensembl" {
                let ensId = d["id"].string ?? ""
                if !ensId.isEmpty {
                    xlinks.append(ProviderHelpers.xlink("ensembl", ensId, "Ensembl: \(ensId)"))
                }
            } else if type == "AlphaFoldDB" {
                let afId = d["id"].string ?? ""
                if !afId.isEmpty {
                    xlinks.append(ProviderHelpers.xlink("alphafold", afId, "AlphaFold: \(afId)"))
                }
            }
        }

        let pName = Self.proteinName(of: data)
        let geneNames = data["genes"].arrayValue.compactMap { $0["geneName"]["value"].string }
        let organism = data["organism"]["scientificName"].string ?? ""
        let lineage = data["organism"]["lineage"].arrayValue.compactMap { $0.string }
        let length = data["sequence"]["length"].int ?? 0
        let sequence = data["sequence"]["value"].string ?? ""
        let reviewed = Self.isReviewed(data)
        let entryType = data["entryType"].string ?? ""

        var sections: [KVSection] = []
        sections.append(KVSection(title: DT.t("基本信息", "Basic Info"), rows: [
            KVRow("Accession", accession, copyable: true, link: URL(string: "https://www.uniprot.org/uniprotkb/" + accession)),
            KVRow(DT.t("类型", "Type"), entryType),
            KVRow(DT.t("审核状态", "Review Status"), reviewed ? DT.t("已审核 (Swiss-Prot)", "Reviewed (Swiss-Prot)") : DT.t("未审核 (TrEMBL)", "Unreviewed (TrEMBL)")),
            KVRow(DT.t("蛋白名称", "Protein Name"), pName),
            KVRow(DT.t("基因名", "Gene Name"), geneNames.joined(separator: ", ")),
            KVRow(DT.t("物种", "Organism"), organism),
            KVRow(DT.t("序列长度", "Sequence Length"), String(length) + " aa")
        ]))

        if !lineage.isEmpty {
            sections.append(KVSection(title: DT.t("分类谱系", "Lineage"), rows: lineage.enumerated().map { (i, name) in
                KVRow(String(i + 1), name)
            }))
        }

        if !domains.isEmpty {
            sections.append(KVSection(title: DT.t("结构域", "Domains"), rows: domains.map { d in
                KVRow(d.type, d.id + " — " + d.name, copyable: true, xlinkTarget: d.xlink)
            }))
        }

        var freeTexts: [FreeTextBlock] = []
        if !funcText.isEmpty {
            freeTexts.append(FreeTextBlock(title: DT.t("功能", "Function"), text: funcText, copyable: true))
        }

        var actions: [DetailAction] = []
        if !sequence.isEmpty {
            actions.append(DetailAction(label: DT.t("复制序列", "Copy Sequence"), payload: sequence, style: .primary))
            let fastaHeader = accession + " " + pName + " " + organism
            let fasta = ExportUtil.fasta(header: fastaHeader, sequence: sequence)
            actions.append(DetailAction(label: DT.t("复制 FASTA", "Copy FASTA"), payload: fasta, style: .secondary))
        }

        return DetailModel(
            headerTitle: pName.isEmpty ? accession : pName,
            headerSubtitle: accession,
            headerMeta: [reviewed ? DT.t("已审核", "Reviewed") : DT.t("未审核", "Unreviewed"), organism, String(length) + " aa"],
            sections: sections,
            freeTextBlocks: freeTexts,
            actions: actions,
            xlinks: xlinks,
            webUrl: "https://www.uniprot.org/uniprotkb/" + accession
        )
    }

    // MARK: - Helpers

    /// REST JSON 表示中没有 `reviewed` 布尔字段，审核状态由 `entryType` 表达
    /// （"UniProtKB reviewed (Swiss-Prot)" / "UniProtKB unreviewed (TrEMBL)"）。
    static func isReviewed(_ r: JSON) -> Bool {
        if let flag = r["reviewed"].bool { return flag }
        return (r["entryType"].string ?? "").contains("reviewed")
    }

    static func proteinName(of r: JSON) -> String {
        let pd = r["proteinDescription"]
        if let name = pd["recommendedName"]["fullName"]["value"].string { return name }
        if let arr = pd["submissionNames"].arrayValue.first {
            return arr["value"].string ?? ""
        }
        if let arr = pd["alternativeNames"].arrayValue.first {
            return arr["fullName"]["value"].string ?? ""
        }
        return ""
    }
}
