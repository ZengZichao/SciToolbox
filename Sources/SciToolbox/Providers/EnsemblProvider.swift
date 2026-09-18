import Foundation

// MARK: - Ensembl Provider

/// Ensembl gene database — direct REST API.
/// Searches human genes by default (species picker removed).
final class EnsemblProvider: ToolProvider {
    let id = "ensembl"
    var name: String { DT.t("Ensembl 基因", "Ensembl Gene") }
    let category: ToolCategory = .gene
    let iconName = "scope"
    var placeholder: String { DT.t("基因符号（如 BRCA1）", "Gene symbol (e.g. BRCA1)") }
    var dataSourceNote: String { DT.t("数据来源：Ensembl REST API (rest.ensembl.org)", "Data source: Ensembl REST API (rest.ensembl.org)") }

    private let base = "https://rest.ensembl.org"

    func search(query: String) async throws -> SearchResult {
        try await search(query: query, offset: 0, pickerId: nil)
    }

    func search(query: String, offset: Int, pickerId: String?) async throws -> SearchResult {
        // Ensembl lookup by symbol returns a single gene, not a list.
        // We use it as a "search" that returns one result.
        // Default to human species since the picker was removed.
        let species = "homo_sapiens"
        if offset > 0 { return SearchResult(items: [], total: 0) }
        let symbol = query.uppercased()
        let url = "\(base)/lookup/symbol/\(species)/\(urlEncodePath(symbol))?content-type=application/json"

        let g: JSON
        do {
            g = try await APIClient.shared.getJSON(url)
        } catch let error as APIError {
            if case .http(let code) = error, code == 400 || code == 404 {
                throw APIError.notFound(DT.t("未找到该基因（请确认物种与符号）", "Gene not found (check species and symbol)"))
            }
            throw error
        }

        guard g["id"].string != nil else {
            throw APIError.notFound(DT.t("未找到该基因（请确认物种与符号）", "Gene not found (check species and symbol)"))
        }

        let geneId = g["id"].string ?? ""
        let displayName = g["display_name"].string ?? symbol
        let desc = g["description"].string ?? ""
        let organism = g["species"].string ?? species

        let item = ResultItem(
            id: geneId,
            title: "\(displayName) — \(desc)",
            subtitle: organism,
            badge: geneId,
            meta: g["biotype"].string,
            extra: ["id": geneId, "symbol": displayName]
        )

        return SearchResult(items: [item], total: 1)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let geneId = context?["id"] ?? id

        // Fetch gene info, sequence, and xrefs in parallel
        async let infoResult = fetchGeneInfo(geneId)
        async let seqResult = fetchSequence(geneId)
        async let xrefResult = fetchXrefs(geneId)

        let info = try await infoResult
        let seq = try? await seqResult
        let xrefs = try? await xrefResult

        var rows: [KVRow] = [
            KVRow("Ensembl ID", info.id, copyable: true),
            KVRow(DT.t("符号", "Symbol"), info.displayName),
            KVRow(DT.t("类型", "Type"), info.objectType),
            KVRow("Biotype", info.biotype),
        ]
        if !info.description.isEmpty { rows.append(KVRow(DT.t("描述", "Description"), info.description)) }
        if !info.source.isEmpty { rows.append(KVRow(DT.t("来源", "Source"), info.source)) }
        if !info.assemblyName.isEmpty { rows.append(KVRow(DT.t("组装", "Assembly"), info.assemblyName)) }
        if !info.version.isEmpty { rows.append(KVRow(DT.t("版本", "Version"), info.version)) }
        if !info.seqRegion.isEmpty { rows.append(KVRow(DT.t("染色体", "Chromosome"), info.seqRegion)) }
        if info.start > 0 { rows.append(KVRow(DT.t("位置", "Location"), "\(info.start)-\(info.end)")) }
        if !info.strand.isEmpty { rows.append(KVRow(DT.t("链", "Strand"), info.strand)) }
        if info.length > 0 { rows.append(KVRow(DT.t("长度", "Length"), "\(info.length) bp")) }

        var sections: [KVSection] = [KVSection(title: DT.t("基因信息", "Gene Info"), rows: rows)]

        // Sequence section
        if let seq = seq, !seq.seq.isEmpty {
            var seqRows: [KVRow] = []
            if !seq.desc.isEmpty { seqRows.append(KVRow(DT.t("描述", "Description"), seq.desc)) }
            seqRows.append(KVRow(DT.t("分子类型", "Molecule Type"), seq.moltype))
            seqRows.append(KVRow(DT.t("长度", "Length"), "\(seq.length) bp\(seq.truncated ? DT.t(" (已截断)", " (truncated)") : "")"))
            sections.append(KVSection(title: DT.t("序列", "Sequence"), rows: seqRows))
        }

        // Xrefs section
        if let xrefs = xrefs, !xrefs.isEmpty {
            let xrefRows = xrefs.prefix(20).map { x in
                KVRow(x.dbName, "\(x.id)\(x.description.isEmpty ? "" : " — \(x.description)")", copyable: true)
            }
            sections.append(KVSection(title: DT.t("交叉引用", "Cross References"), rows: xrefRows))
        }

        // Build xlinks from xrefs
        var xlinkList: [XLink] = []
        if let xrefs = xrefs {
            for x in xrefs {
                if x.dbName.lowercased().contains("uniprot") {
                    xlinkList.append(XLink(toolId: "uniprot", query: x.id, label: "UniProt: \(x.id)"))
                } else if x.dbName.lowercased().contains("pubmed") {
                    xlinkList.append(XLink(toolId: "pubmed", query: x.id, label: "PubMed: \(x.id)"))
                }
            }
        }

        var actions: [DetailAction] = []
        if let seq = seq, !seq.seq.isEmpty {
            let header = ">\(info.displayName) \(seq.desc)"
            actions.append(DetailAction(label: DT.t("复制序列", "Copy Sequence"), payload: seq.seq, style: .primary))
            actions.append(DetailAction(label: DT.t("复制 FASTA", "Copy FASTA"), payload: ExportUtil.fasta(header: header, sequence: seq.seq), style: .secondary))
        }

        return DetailModel(
            headerTitle: "\(info.displayName) — \(info.description)",
            headerSubtitle: info.id,
            headerMeta: [info.biotype, info.organism].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: [],
            actions: actions,
            xlinks: xlinkList,
            webUrl: "https://www.ensembl.org/\(info.organism)/Gene/Summary?g=\(info.id)"
        )
    }

    // MARK: - Data types

    struct GeneInfo {
        var id: String
        var displayName: String
        var organism: String
        var objectType: String
        var biotype: String
        var description: String
        var source: String
        var assemblyName: String
        var version: String
        var seqRegion: String
        var start: Int
        var end: Int
        var strand: String
        var length: Int
    }

    struct SeqInfo {
        var seq: String
        var desc: String
        var moltype: String
        var length: Int
        var truncated: Bool
    }

    struct XrefInfo {
        var dbName: String
        var id: String
        var description: String
    }

    // MARK: - Fetching

    private func fetchGeneInfo(_ id: String) async throws -> GeneInfo {
        let url = "\(base)/lookup/id/\(urlEncodePath(id))?content-type=application/json"
        let g = try await APIClient.shared.getJSON(url)
        // lookup/id 把位置信息平铺在顶层；兼容未来可能出现的嵌套 location
        let loc = g["location"].dictValue.isEmpty ? g : g["location"]
        let start = loc["start"].int ?? 0
        let end = loc["end"].int ?? 0
        let strandInt = loc["strand"].int ?? 0
        return GeneInfo(
            id: g["id"].string ?? id,
            displayName: g["display_name"].string ?? "",
            organism: g["species"].string ?? "",
            objectType: g["object_type"].string ?? "",
            biotype: g["biotype"].string ?? "",
            description: g["description"].string ?? "",
            source: g["source"].string ?? "",
            assemblyName: g["assembly_name"].string ?? "",
            version: g["version"].string ?? "",
            seqRegion: loc["seq_region_name"].string ?? "",
            start: start,
            end: end,
            strand: strandInt == 0 ? "" : (strandInt > 0 ? DT.t("正链 (+)", "Plus strand (+)") : DT.t("反链 (−)", "Minus strand (−)")),
            length: (start > 0 && end > 0) ? abs(end - start) + 1 : 0
        )
    }

    private func fetchSequence(_ id: String) async throws -> SeqInfo {
        let url = "\(base)/sequence/id/\(urlEncodePath(id))?content-type=application/json"
        let j = try await APIClient.shared.getJSON(url)
        var seq = j["seq"].string ?? ""
        let maxLen = 60000
        var truncated = false
        if seq.count > maxLen {
            seq = String(seq.prefix(maxLen))
            truncated = true
        }
        return SeqInfo(
            seq: seq,
            desc: j["desc"].string ?? "",
            moltype: j["moltype"].string ?? "",
            length: seq.count,
            truncated: truncated
        )
    }

    private func fetchXrefs(_ id: String) async throws -> [XrefInfo] {
        let url = "\(base)/xrefs/id/\(urlEncodePath(id))?content-type=application/json"
        let arr = try await APIClient.shared.getJSON(url)
        return arr.arrayValue.compactMap { x in
            guard let dbName = x["db_display_name"].string, let displayId = x["display_id"].string else { return nil }
            return XrefInfo(
                dbName: dbName,
                id: displayId,
                description: x["description"].string ?? ""
            )
        }
    }

}
