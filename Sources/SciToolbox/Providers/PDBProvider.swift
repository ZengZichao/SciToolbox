import Foundation

// MARK: - PDB Provider

/// RCSB PDB structure database — direct API.
/// Search: POST https://search.rcsb.org/rcsbsearch/v2/query
/// Detail: GET https://data.rcsb.org/rest/v1/core/entry/{id}
final class PDBProvider: ToolProvider {
    let id = "pdb"
    var name: String { DT.t("RCSB PDB 结构", "RCSB PDB Structure") }
    let category: ToolCategory = .protein
    let iconName = "cube"
    var placeholder: String { DT.t("关键词或 PDB ID", "Keyword or PDB ID") }
    var dataSourceNote: String { DT.t("数据来源：RCSB PDB (data.rcsb.org)", "Data source: RCSB PDB (data.rcsb.org)") }

    private let searchURL = "https://search.rcsb.org/rcsbsearch/v2/query"
    private let entryURL = "https://data.rcsb.org/rest/v1/core/entry"

    func search(query: String) async throws -> SearchResult {
        try await search(query: query, offset: 0, pickerId: nil)
    }

    func search(query: String, offset: Int, pickerId: String?) async throws -> SearchResult {
        guard query.count >= 2 else {
            throw APIError.invalidInput(DT.t("检索词至少 2 个字符", "Search term must be at least 2 characters"))
        }

        let pageSize = 20
        // RCSB Search API v2 分页字段名为 `paginate`（`pager` 不被 schema 允许，会返回 HTTP 400）
        let body: [String: Any] = [
            "query": [
                "type": "terminal",
                "service": "full_text",
                "parameters": ["value": query]
            ],
            "return_type": "entry",
            "request_options": ["paginate": ["start": offset, "rows": pageSize]]
        ]

        let sres = try await APIClient.shared.postJSON(searchURL, body: body)
        let ids = sres["result_set"].arrayValue.compactMap { $0["identifier"].string }
        let total = sres["total_count"].int ?? ids.count

        guard !ids.isEmpty else { return SearchResult(items: [], total: 0) }

        // Fetch summary for each entry concurrently (was serial N+1)
        var items: [(Int, ResultItem)] = []
        await withTaskGroup(of: (Int, ResultItem?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    do {
                        let entry = try await self.fetchEntry(id)
                        return (index, ResultItem(
                            id: id,
                            title: entry.title,
                            subtitle: entry.descriptor,
                            badge: id,
                            meta: entry.method + (entry.resolution.isEmpty ? "" : DT.t(" · 分辨率 \(entry.resolution) Å", " · Resolution \(entry.resolution) Å")),
                            extra: ["id": id]
                        ))
                    } catch {
                        return (index, nil)
                    }
                }
            }
            for await (index, item) in group {
                if let item { items.append((index, item)) }
            }
        }
        // Restore original order (TaskGroup results are non-deterministic)
        items.sort { $0.0 < $1.0 }

        return SearchResult(items: items.map(\.1), total: total, hasMore: offset + items.count < total)
    }

    func detail(id: String, context: [String: String]?) async throws -> DetailModel {
        let pdbId = (context?["id"] ?? id).uppercased()
        let entry = try await fetchEntry(pdbId)

        // Fetch polymer entities to get UniProt cross-references
        let uniprotIds = (try? await fetchPolymerEntities(pdbId, entityCount: entry.entityCount)) ?? []

        var infoRows: [KVRow] = [KVRow(DT.t("实验方法", "Experimental method"), entry.method)]
        if !entry.resolution.isEmpty { infoRows.append(KVRow(DT.t("分辨率", "Resolution"), "\(entry.resolution) Å")) }
        if !entry.releaseDate.isEmpty { infoRows.append(KVRow(DT.t("发布日期", "Release date"), entry.releaseDate)) }
        if !entry.molecularWeight.isEmpty { infoRows.append(KVRow(DT.t("分子量", "Molecular weight"), entry.molecularWeight)) }
        infoRows.append(KVRow(DT.t("聚合物实体", "Polymer entities"), "\(entry.entityCount)"))
        if entry.monomerCount > 0 { infoRows.append(KVRow(DT.t("单体数", "Monomers"), "\(entry.monomerCount)")) }
        if !entry.polymerComposition.isEmpty { infoRows.append(KVRow(DT.t("组成", "Composition"), entry.polymerComposition)) }

        var citeRows: [KVRow] = []
        if !entry.citationTitle.isEmpty { citeRows.append(KVRow(DT.t("标题", "Title"), entry.citationTitle)) }
        if !entry.journal.isEmpty { citeRows.append(KVRow(DT.t("期刊", "Journal"), "\(entry.journal)\(entry.year.isEmpty ? "" : DT.t("（\(entry.year)）", "(\(entry.year))"))")) }
        if !entry.authors.isEmpty { citeRows.append(KVRow(DT.t("作者", "Authors"), ProviderHelpers.formatAuthors(entry.authors), copyable: entry.authors.count > 3)) }
        if !entry.pubmed.isEmpty {
            citeRows.append(KVRow("PubMed", entry.pubmed, copyable: true,
                xlinkTarget: ProviderHelpers.xlink("pubmed", entry.pubmed, "PubMed: \(entry.pubmed)")))
        }
        if !entry.doi.isEmpty { citeRows.append(KVRow("DOI", entry.doi, copyable: true, link: ProviderHelpers.doiURL(entry.doi))) }

        var sections: [KVSection] = [KVSection(title: DT.t("结构信息", "Structure Info"), rows: infoRows)]
        if !citeRows.isEmpty {
            sections.append(KVSection(title: DT.t("主要引用", "Primary Citation"), rows: citeRows))
        }

        var xlinks: [XLink] = []
        if !entry.pubmed.isEmpty {
            xlinks.append(ProviderHelpers.xlink("pubmed", entry.pubmed, "PubMed: \(entry.pubmed)"))
        }
        for uid in uniprotIds.prefix(5) {
            xlinks.append(ProviderHelpers.xlink("uniprot", uid, "UniProt: \(uid)"))
        }

        // Structure preview image (RCSB CDN: /images/structures/{id_lower}_assembly-1.jpeg)
        let pdbLower = pdbId.lowercased()
        let imageUrl = "https://cdn.rcsb.org/images/structures/\(pdbLower)_assembly-1.jpeg"

        return DetailModel(
            headerTitle: entry.title.isEmpty ? pdbId : entry.title,
            headerSubtitle: pdbId,
            headerMeta: [entry.method, entry.resolution.isEmpty ? "" : "\(entry.resolution) Å"].filter { !$0.isEmpty },
            sections: sections,
            freeTextBlocks: [],
            actions: [DetailAction(label: DT.t("复制 PDB ID", "Copy PDB ID"), payload: pdbId, style: .secondary)],
            xlinks: xlinks,
            webUrl: entry.webUrl,
            imageUrl: imageUrl
        )
    }

    // MARK: - Entry fetching

    struct PDBEntry {
        var id: String
        var title: String
        var descriptor: String
        var method: String
        var resolution: String
        var authors: [String]
        var citationTitle: String
        var journal: String
        var year: String
        var pubmed: String
        var doi: String
        var releaseDate: String
        var molecularWeight: String
        var entityCount: Int
        var monomerCount: Int
        var polymerComposition: String
        var webUrl: String
    }

    private func fetchEntry(_ id: String) async throws -> PDBEntry {
        let url = "\(entryURL)/\(urlEncodePath(id))"
        let d = try await APIClient.shared.getJSON(url)

        let info = d["rcsb_entry_info"]
        let cit = d["rcsb_primary_citation"]
        let struct_ = d["struct"]
        let exptl = d["exptl"].arrayValue

        let methods = info["experimental_method"].string
            ?? exptl.first?["method"].string
            ?? ""
        let resArr = info["resolution_combined"].arrayValue

        return PDBEntry(
            id: d["entry"]["id"].string ?? id,
            title: struct_["title"].string ?? "",
            descriptor: struct_["pdbx_descriptor"].string ?? "",
            method: methods,
            resolution: resArr.first?.string ?? "",
            authors: cit["rcsb_authors"].arrayValue.compactMap { $0.string },
            citationTitle: cit["title"].string ?? "",
            journal: cit["journal_abbrev"].string ?? "",
            year: cit["year"].string ?? "",
            pubmed: cit["pdbx_database_id_PubMed"].string ?? cit["rcsb_database_id_PubMed"].string ?? "",
            doi: cit["pdbx_database_id_DOI"].string ?? cit["rcsb_database_id_DOI"].string ?? "",
            releaseDate: d["rcsb_accession_info"]["initial_release_date"].string ?? "",
            molecularWeight: info["molecular_weight"].string ?? "",
            entityCount: info["entity_count"].int ?? 0,
            monomerCount: info["deposited_polymer_monomer_count"].int ?? 0,
            polymerComposition: info["polymer_composition"].string ?? "",
            webUrl: "https://www.rcsb.org/structure/\(id)"
        )
    }

    // MARK: - Polymer entities (for UniProt cross-references)

    /// Fetches UniProt accession IDs from all polymer entities of this PDB entry.
    private func fetchPolymerEntities(_ pdbId: String, entityCount: Int) async throws -> [String] {
        guard entityCount > 0 else { return [] }
        var ids = Set<String>()
        await withTaskGroup(of: [String].self) { group in
            for entityId in 1...entityCount {
                group.addTask {
                    let url = "https://data.rcsb.org/rest/v1/core/polymer_entity/\(pdbId)/\(entityId)"
                    guard let d = try? await APIClient.shared.getJSON(url) else { return [] }
                    return d["rcsb_polymer_entity_container_identifiers"]["uniprot_ids"].arrayValue.compactMap { $0.string }
                }
            }
            for await result in group {
                ids.formUnion(result)
            }
        }
        return Array(ids)
    }
}
