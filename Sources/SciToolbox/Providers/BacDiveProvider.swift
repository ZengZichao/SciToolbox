import Foundation

// MARK: - BacDive Provider

/// BacDive strain database — DSMZ REST API v2.
final class BacDiveProvider: ToolProvider {
    let id = "bacdive"
    var name: String { DT.t("BacDive 菌株", "BacDive Strains") }
    let category: ToolCategory = .taxonomy
    let iconName = "ladybug"
    var placeholder: String { DT.t("属名 或 属名 种名", "Genus or Genus species") }
    var dataSourceNote: String { DT.t("数据来源：BacDive (api.bacdive.dsmz.de)", "Data source: BacDive (api.bacdive.dsmz.de)") }

    private let base = "https://api.bacdive.dsmz.de"

    func search(query: String) async throws -> SearchResult {
        let parts = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard let genus = parts.first else {
            throw APIError.invalidInput(DT.t("请输入属名", "Please enter a genus"))
        }
        let species = parts.count > 1 ? parts[1] : ""

        let url = species.isEmpty
            ? "\(base)/v2/taxon/\(urlEncodePath(genus))"
            : "\(base)/v2/taxon/\(urlEncodePath(genus))/\(urlEncodePath(species))"

        let data = try await APIClient.shared.getJSON(url)
        let ids = data["results"].arrayValue.prefix(60).compactMap { $0.string }
        let count = data["count"].int ?? ids.count

        guard !ids.isEmpty else { return SearchResult(items: [], total: 0) }

        // Fetch summaries for first 10 IDs
        var summaries: [String: (name: String, strain: String, typeStrain: String, dsm: String)] = [:]
        let preview = Array(ids.prefix(10))
        if !preview.isEmpty {
            do {
                let fetchURL = "\(base)/v2/fetch/\(preview.joined(separator: ";"))"
                let fd = try await APIClient.shared.getJSON(fetchURL)
                let res = fd["results"].dictValue
                for (id, strainData) in res {
                    let s = extractStrain(strainData)
                    summaries[id] = (s.fullName, s.strainDesignation, s.typeStrain, s.dsmNumber)
                }
            } catch {
                // Summary fetch failure doesn't block main results
            }
        }

        var items: [ResultItem] = []
        for id in ids {
            let summary = summaries[id]
            items.append(ResultItem(
                id: id,
                title: summary?.name ?? "BacDive ID: \(id)",
                subtitle: summary?.strain,
                badge: id,
                meta: summary?.typeStrain.isEmpty == false ? "Type strain" : nil,
                extra: ["bacdiveId": id]
            ))
        }

        return SearchResult(items: items, total: count)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let bacdiveId = context?["bacdiveId"] ?? id
        let url = "\(base)/v2/fetch/\(urlEncodePath(bacdiveId))"
        let fd = try await APIClient.shared.getJSON(url)
        let res = fd["results"].dictValue
        let rec = res[bacdiveId] ?? res.values.first ?? JSON([:])
        let s = extractStrain(rec)

        guard !s.bacdiveId.isEmpty else {
            throw APIError.notFound(DT.t("未找到该菌株", "Strain not found"))
        }

        var sections: [KVSection] = []

        // Basic info
        var infoRows: [KVRow] = [
            KVRow("BacDive ID", s.bacdiveId, copyable: true),
            KVRow(DT.t("DSM 编号", "DSM Number"), s.dsmNumber, copyable: true),
            KVRow(DT.t("全名", "Full Name"), s.fullName),
            KVRow(DT.t("菌株编号", "Strain Designation"), s.strainDesignation),
        ]
        if !s.typeStrain.isEmpty { infoRows.append(KVRow("Type strain", s.typeStrain)) }
        if !s.ncbiTaxId.isEmpty { infoRows.append(KVRow("NCBI TaxID", s.ncbiTaxId, copyable: true)) }
        if !s.description.isEmpty { infoRows.append(KVRow(DT.t("描述", "Description"), s.description)) }
        sections.append(KVSection(title: DT.t("基本信息", "Basic Info"), rows: infoRows))

        // Taxonomy
        let taxRows: [KVRow] = [
            KVRow(DT.t("域", "Domain"), s.taxonomy.domain),
            KVRow(DT.t("门", "Phylum"), s.taxonomy.phylum),
            KVRow(DT.t("纲", "Class"), s.taxonomy.class_),
            KVRow(DT.t("目", "Order"), s.taxonomy.order),
            KVRow(DT.t("科", "Family"), s.taxonomy.family),
            KVRow(DT.t("属", "Genus"), s.taxonomy.genus),
            KVRow(DT.t("种", "Species"), s.taxonomy.species),
        ].filter { !$0.value.isEmpty }
        if !taxRows.isEmpty {
            sections.append(KVSection(title: DT.t("分类", "Taxonomy"), rows: taxRows))
        }

        // Morphology
        let morphRows: [KVRow] = [
            KVRow(DT.t("革兰氏染色", "Gram Stain"), s.morphology.gramStain),
            KVRow(DT.t("细胞形态", "Cell Shape"), s.morphology.cellShape),
            KVRow(DT.t("细胞长度", "Cell Length"), s.morphology.cellLength),
            KVRow(DT.t("细胞宽度", "Cell Width"), s.morphology.cellWidth),
            KVRow(DT.t("运动性", "Motility"), s.morphology.motility),
        ].filter { !$0.value.isEmpty }
        if !morphRows.isEmpty {
            sections.append(KVSection(title: DT.t("形态", "Morphology"), rows: morphRows))
        }

        // Culture conditions
        var cultRows: [KVRow] = []
        if !s.medium.name.isEmpty { cultRows.append(KVRow(DT.t("培养基", "Medium"), s.medium.name)) }
        if !s.growthTemp.optimum.isEmpty { cultRows.append(KVRow(DT.t("最适温度", "Optimum Temp"), "\(s.growthTemp.optimum) °C")) }
        if !s.growthTemp.minimum.isEmpty { cultRows.append(KVRow(DT.t("最低温度", "Min Temp"), "\(s.growthTemp.minimum) °C")) }
        if !s.growthTemp.maximum.isEmpty { cultRows.append(KVRow(DT.t("最高温度", "Max Temp"), "\(s.growthTemp.maximum) °C")) }
        if !s.growthPh.optimum.isEmpty { cultRows.append(KVRow(DT.t("最适 pH", "Optimum pH"), s.growthPh.optimum)) }
        if !s.oxygenTolerance.isEmpty { cultRows.append(KVRow(DT.t("需氧性", "Oxygen"), s.oxygenTolerance)) }
        if !cultRows.isEmpty {
            sections.append(KVSection(title: DT.t("培养条件", "Culture Conditions"), rows: cultRows))
        }

        // Sequence info
        var seqRows: [KVRow] = []
        if !s.gcContent.isEmpty { seqRows.append(KVRow(DT.t("GC 含量", "GC Content"), s.gcContent)) }
        if !s.genome.accession.isEmpty { seqRows.append(KVRow(DT.t("基因组", "Genome"), s.genome.accession, copyable: true)) }
        if !s.sequence16s.accession.isEmpty {
            seqRows.append(KVRow("16S rRNA", "\(s.sequence16s.accession) (\(s.sequence16s.length) bp)", copyable: true))
        }
        if !seqRows.isEmpty {
            sections.append(KVSection(title: DT.t("序列信息", "Sequence Info"), rows: seqRows))
        }

        // Enzymes
        if !s.enzymes.isEmpty {
            sections.append(KVSection(title: DT.t("酶活性", "Enzymes"), rows: s.enzymes.prefix(30).map { e in
                KVRow(e.ec, "\(e.value) — \(e.activity)")
            }))
        }

        // Literature
        if !s.literature.isEmpty {
            sections.append(KVSection(title: DT.t("文献", "References"), rows: s.literature.map { l in
                let parts = [l.authors, l.journal, l.year].filter { !$0.isEmpty }
                return KVRow(l.year, "\(l.title)\(parts.isEmpty ? "" : " — \(parts.joined(separator: ", "))")")
            }))
        }

        var xlinks: [XLink] = []
        if !s.ncbiTaxId.isEmpty {
            xlinks.append(XLink(toolId: "ncbi_taxonomy", query: s.ncbiTaxId, label: DT.t("NCBI 分类: \(s.fullName)", "NCBI Taxonomy: \(s.fullName)")))
        }

        return DetailModel(
            headerTitle: s.fullName.isEmpty ? "BacDive \(s.bacdiveId)" : s.fullName,
            headerSubtitle: s.strainDesignation.isEmpty ? "BacDive ID: \(s.bacdiveId)" : s.strainDesignation,
            headerMeta: [s.typeStrain.isEmpty ? nil : "Type strain", s.dsmNumber.isEmpty ? nil : "DSM \(s.dsmNumber)"].compactMap { $0 },
            sections: sections,
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制 BacDive ID", "Copy BacDive ID"), payload: s.bacdiveId, style: .secondary)],
            xlinks: xlinks,
            webUrl: "https://bacdive.dsmz.de/strain/\(s.bacdiveId)"
        )
    }

    // MARK: - Strain extraction

    struct StrainData {
        var bacdiveId: String = ""
        var dsmNumber: String = ""
        var fullName: String = ""
        var strainDesignation: String = ""
        var typeStrain: String = ""
        var ncbiTaxId: String = ""
        var description: String = ""
        var taxonomy: (domain: String, phylum: String, class_: String, order: String, family: String, genus: String, species: String) = ("", "", "", "", "", "", "")
        var morphology: (gramStain: String, cellShape: String, cellLength: String, cellWidth: String, motility: String) = ("", "", "", "", "")
        var medium: (name: String, link: String) = ("", "")
        var growthTemp: (optimum: String, minimum: String, maximum: String) = ("", "", "")
        var growthPh: (optimum: String, minimum: String, maximum: String, range: String) = ("", "", "", "")
        var oxygenTolerance: String = ""
        var enzymes: [(value: String, activity: String, ec: String)] = []
        var gcContent: String = ""
        var genome: (accession: String, description: String) = ("", "")
        var sequence16s: (accession: String, length: String) = ("", "")
        var literature: [(title: String, authors: String, journal: String, year: String, pubmed: String, doi: String)] = []
    }

    private func extractStrain(_ d: JSON) -> StrainData {
        var s = StrainData()
        let gen = d["General"]
        let ntc = d["Name and taxonomic classification"]
        let morph = d["Morphology"]
        let cellM = morph["cell morphology"]
        let cul = d["Culture and growth conditions"]
        let phys = d["Physiology and metabolism"]
        let seq = d["Sequence information"]

        s.bacdiveId = gen["BacDive-ID"].string ?? ""
        s.dsmNumber = gen["DSM-Number"].string ?? ""
        s.fullName = ntc["full scientific name"].string ?? ""
        s.strainDesignation = ntc["strain designation"].string ?? ""
        s.typeStrain = ntc["type strain"].string ?? ""
        s.description = gen["description"].string ?? ""

        let taxId = gen["NCBI tax id"]
        s.ncbiTaxId = taxId["NCBI tax id"].string ?? ""

        s.taxonomy = (
            ntc["domain"].string ?? "",
            ntc["phylum"].string ?? "",
            ntc["class"].string ?? "",
            ntc["order"].string ?? "",
            ntc["family"].string ?? "",
            ntc["genus"].string ?? "",
            ntc["species"].string ?? ""
        )

        s.morphology = (
            cellM["gram stain"].string ?? "",
            cellM["cell shape"].string ?? "",
            cellM["cell length"].string ?? "",
            cellM["cell width"].string ?? "",
            cellM["motility"].string ?? ""
        )

        // Growth temperature
        let temps = cul["culture temp"].arrayValue
        for t in temps {
            let type = t["type"].string ?? ""
            let temp = t["temperature"].string ?? ""
            if type == "optimum" { s.growthTemp.optimum = temp }
            else if type == "minimum" { s.growthTemp.minimum = temp }
            else if type == "maximum" { s.growthTemp.maximum = temp }
        }

        // Growth pH
        let phs = cul["culture pH"].arrayValue
        for p in phs {
            let type = p["type"].string ?? ""
            let ph = p["pH"].string ?? ""
            if type == "optimum" { s.growthPh.optimum = ph }
            else if type == "minimum" { s.growthPh.minimum = ph }
            else if type == "maximum" { s.growthPh.maximum = ph }
            else if type == "PH range" { s.growthPh.range = ph }
        }

        let medium = cul["culture medium"]
        s.medium = (medium["name"].string ?? "", medium["link"].string ?? "")

        s.oxygenTolerance = phys["oxygen tolerance"]["oxygen tolerance"].string ?? ""

        // Enzymes
        s.enzymes = phys["enzymes"].arrayValue.prefix(60).map { e in
            (e["value"].string ?? "", e["activity"].string ?? "", e["ec"].string ?? "")
        }

        // Sequence info
        s.gcContent = seq["GC content"]["GC-content"].string ?? ""
        s.genome = (
            seq["Genome sequences"]["INSDC accession"].string ?? "",
            seq["Genome sequences"]["description"].string ?? ""
        )
        s.sequence16s = (
            seq["16S sequences"]["accession"].string ?? "",
            seq["16S sequences"]["length"].string ?? ""
        )

        // Literature
        s.literature = d["Literature"].arrayValue.prefix(15).map { l in
            (l["title"].string ?? "", l["authors"].string ?? "", l["journal"].string ?? "",
             l["year"].string ?? "", l["Pubmed-ID"].string ?? "", l["DOI"].string ?? "")
        }

        return s
    }

}
