import Foundation

// MARK: - AlphaFold Provider

/// AlphaFold structure database — EBI AlphaFold DB REST API.
/// Search by UniProt accession; detail returns predicted structure info + PAE/pLDDT.
/// API: https://alphafold.ebi.ac.uk/api
final class AlphaFoldProvider: ToolProvider {
    let id = "alphafold"
    var name: String { DT.t("AlphaFold 结构", "AlphaFold Structure") }
    let category: ToolCategory = .protein
    let iconName = "cube.transparent"
    var placeholder: String { DT.t("UniProt Accession（如 P04637）", "UniProt Accession (e.g. P04637)") }
    var dataSourceNote: String { DT.t("数据来源：AlphaFold DB (alphafold.ebi.ac.uk)", "Data source: AlphaFold DB (alphafold.ebi.ac.uk)") }

    private let base = "https://alphafold.ebi.ac.uk/api"

    func search(query: String) async throws -> SearchResult {
        let accession = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !accession.isEmpty else {
            throw APIError.invalidInput(DT.t("请输入 UniProt Accession", "Enter a UniProt Accession"))
        }

        // AlphaFold API returns a JSON array of predictions per UniProt accession.
        let url = "\(base)/prediction/\(urlEncodePath(accession))"
        let data: JSON
        do {
            data = try await APIClient.shared.getJSON(url)
        } catch let error as APIError {
            if case .http(let code) = error, code == 404 {
                return SearchResult(items: [], total: 0)
            }
            throw error
        }

        // The API returns an array; take the first (main) prediction.
        let rec = data.arrayValue.first ?? data
        guard let uniProtAccession = rec["uniprotAccession"].string, !uniProtAccession.isEmpty else {
            return SearchResult(items: [], total: 0)
        }

        let organism = rec["organismScientificName"].string ?? ""
        let modelVersion = String(rec["latestVersion"].int ?? 0)
        let avgPlddt = String(format: "%.1f", rec["globalMetricValue"].double ?? 0)
        let uniprotDescription = rec["uniprotDescription"].string ?? ""
        let gene = rec["gene"].string ?? ""

        let item = ResultItem(
            id: uniProtAccession,
            title: uniprotDescription.isEmpty ? uniProtAccession : uniprotDescription,
            subtitle: organism.isEmpty ? gene : "\(gene) · \(organism)",
            badge: uniProtAccession,
            meta: "v\(modelVersion) · pLDDT \(avgPlddt)",
            extra: ["accession": uniProtAccession]
        )

        return SearchResult(items: [item], total: 1)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let accession = (context?["accession"] ?? id).uppercased()
        let url = "\(base)/prediction/\(urlEncodePath(accession))"
        let data = try await APIClient.shared.getJSON(url)

        // The API returns an array; take the first (main) prediction.
        let rec = data.arrayValue.first ?? data

        let uniProtAccession = rec["uniprotAccession"].string ?? accession
        let organism = rec["organismScientificName"].string ?? ""
        let taxId = String(rec["taxId"].int ?? 0)
        let modelVersion = String(rec["latestVersion"].int ?? 0)
        let uniprotDescription = rec["uniprotDescription"].string ?? ""
        let gene = rec["gene"].string ?? ""
        let uniprotId = rec["uniprotId"].string ?? ""
        let isReviewed = rec["isReviewed"].bool ?? false
        let modelCreatedDate = rec["modelCreatedDate"].string ?? ""
        let sequenceVersionDate = rec["sequenceVersionDate"].string ?? ""
        let sequence = rec["sequence"].string ?? ""
        let entryId = rec["entryId"].string ?? ""
        let pdbUrl = rec["pdbUrl"].string ?? ""
        let paeImageUrl = rec["paeImageUrl"].string ?? ""

        // Confidence scores
        let plddt = rec["globalMetricValue"].double
        let fractionVeryLow = rec["fractionPlddtVeryLow"].double
        let fractionLow = rec["fractionPlddtLow"].double
        let fractionConfident = rec["fractionPlddtConfident"].double
        let fractionVeryHigh = rec["fractionPlddtVeryHigh"].double

        var infoRows: [KVRow] = [
            KVRow("UniProt", uniProtAccession, copyable: true,
                  xlinkTarget: ProviderHelpers.xlink("uniprot", uniProtAccession, "UniProt: \(uniProtAccession)")),
            KVRow(DT.t("描述", "Description"), uniprotDescription),
        ]
        if !gene.isEmpty { infoRows.append(KVRow(DT.t("基因", "Gene"), gene)) }
        if !uniprotId.isEmpty { infoRows.append(KVRow("UniProt ID", uniprotId, copyable: true)) }
        infoRows.append(KVRow(DT.t("物种", "Organism"), organism))
        infoRows.append(KVRow(DT.t("模型版本", "Model version"), "v\(modelVersion)"))
        if !modelCreatedDate.isEmpty { infoRows.append(KVRow(DT.t("模型创建日期", "Model creation date"), modelCreatedDate)) }
        if !sequenceVersionDate.isEmpty { infoRows.append(KVRow(DT.t("序列版本日期", "Sequence version date"), sequenceVersionDate)) }
        infoRows.append(KVRow(DT.t("已评审", "Reviewed"), isReviewed ? DT.t("是", "Yes") : DT.t("否", "No")))
        if !taxId.isEmpty && taxId != "0" { infoRows.append(KVRow("TaxID", taxId, copyable: true,
            xlinkTarget: ProviderHelpers.xlink("ncbi_taxonomy", taxId, DT.t("NCBI 分类: \(organism)", "NCBI Taxonomy: \(organism)")))) }
        if !entryId.isEmpty { infoRows.append(KVRow("Entry ID", entryId, copyable: true)) }

        var scoreRows: [KVRow] = []
        if let p = plddt { scoreRows.append(KVRow("pLDDT", String(format: "%.2f", p))) }
        if let f = fractionVeryHigh { scoreRows.append(KVRow(DT.t("极高置信度", "Very high confidence"), String(format: "%.1f%%", f * 100))) }
        if let f = fractionConfident { scoreRows.append(KVRow(DT.t("高置信度", "High confidence"), String(format: "%.1f%%", f * 100))) }
        if let f = fractionLow { scoreRows.append(KVRow(DT.t("低置信度", "Low confidence"), String(format: "%.1f%%", f * 100))) }
        if let f = fractionVeryLow { scoreRows.append(KVRow(DT.t("极低置信度", "Very low confidence"), String(format: "%.1f%%", f * 100))) }

        var sections: [KVSection] = [KVSection(title: DT.t("基本信息", "Basic Info"), rows: infoRows)]
        if !scoreRows.isEmpty {
            sections.append(KVSection(title: DT.t("置信度评分", "Confidence Scores"), rows: scoreRows))
        }

        // Sequence section
        if !sequence.isEmpty {
            var seqRows: [KVRow] = []
            seqRows.append(KVRow(DT.t("长度", "Length"), "\(sequence.count) aa"))
            seqRows.append(KVRow(DT.t("序列", "Sequence"), String(sequence.prefix(200)) + (sequence.count > 200 ? "…" : ""), copyable: true))
            sections.append(KVSection(title: DT.t("序列", "Sequence"), rows: seqRows))
        }

        // Cross-links
        var xlinks: [XLink] = []
        xlinks.append(ProviderHelpers.xlink("uniprot", uniProtAccession, "UniProt: \(uniProtAccession)"))
        if !taxId.isEmpty && taxId != "0" {
            xlinks.append(ProviderHelpers.xlink("ncbi_taxonomy", taxId, DT.t("NCBI 分类: \(organism)", "NCBI Taxonomy: \(organism)")))
        }

        // Actions
        var actions: [DetailAction] = [
            DetailAction(label: DT.t("复制 Accession", "Copy Accession"), payload: uniProtAccession, style: .secondary)
        ]
        if !sequence.isEmpty {
            let header = ">\(uniProtAccession) \(uniprotDescription)"
            actions.append(DetailAction(label: DT.t("复制序列", "Copy Sequence"), payload: sequence, style: .primary))
            actions.append(DetailAction(label: DT.t("复制 FASTA", "Copy FASTA"), payload: ExportUtil.fasta(header: header, sequence: sequence), style: .secondary))
        }
        if !pdbUrl.isEmpty {
            actions.append(DetailAction(label: DT.t("复制 PDB URL", "Copy PDB URL"), payload: pdbUrl, style: .secondary))
            // P2-10：直接改写已构造的 section（Swift 数组是值类型，:113 处已拷贝，不能再往局部 infoRows 追加）
            sections[0].rows.append(KVRow(DT.t("PDB 结构", "PDB Structure"), pdbUrl, copyable: true, link: URL(string: pdbUrl)))
        }

        // Use PAE image as preview
        let imageUrl = paeImageUrl.isEmpty
            ? "https://alphafold.ebi.ac.uk/api/preview/\(uniProtAccession)"
            : paeImageUrl

        return DetailModel(
            headerTitle: uniprotDescription.isEmpty ? uniProtAccession : uniprotDescription,
            headerSubtitle: uniProtAccession,
            headerMeta: [organism, "v\(modelVersion)"].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: [],
            actions: actions,
            xlinks: xlinks,
            webUrl: "https://alphafold.ebi.ac.uk/entry/\(uniProtAccession)",
            imageUrl: imageUrl
        )
    }

}
