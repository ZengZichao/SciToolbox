import Foundation

// MARK: - Accession Router (智能识别路由)

/// 粘贴一段文本（accession / DOI / 基因符号 / PMID / TaxID 等），
/// 自动判断其类型并路由到对应工具。
///
/// 设计原则（架构权衡）：
/// - 纯函数、无副作用、无网络请求 —— 仅做字符串模式识别。
/// - 返回「带置信度的候选列表」而非单一结果：遇到歧义（如 4 字母既可能是 PDB 也可能是基因符号，
///   纯数字既可能是 PMID 也可能是 TaxID）时交给 UI 让用户选择，避免在用户无感知时错误跳转。
/// - 路由决策（直接跳转 vs 弹窗选择）由调用方（ContentView）根据 `confidence` 阈值决定，
///   本类型只负责「识别」。
struct AccessionRouter {

    /// 单个识别结果
    struct Match: Identifiable, Hashable {
        let id = UUID()
        /// 目标工具 id（对应 ToolProvider.id）
        let toolId: String
        /// 用于该工具检索的查询串（已做必要的归一化，如 DOI 原样、PDB 转大写）
        let query: String
        /// 置信度 0...1
        let confidence: Double
        /// 人类可读的识别理由（用于歧义弹窗展示）
        let reason: String
    }

    // MARK: - 单条识别

    /// 识别一段输入，返回按置信度降序排列、按 toolId 去重后的候选列表。
    static func classify(_ raw: String) -> [Match] {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }

        var matches: [Match] = []

        // 1) DOI → Europe PMC（同时也被 PubMed 支持，但 Europe PMC 更通用）
        if let range = input.range(of: #"10\.\d{4,9}/[^\s]+"#, options: .regularExpression) {
            let doi = String(input[range])
            matches.append(Match(toolId: "europepmc", query: doi,
                                 confidence: 0.95, reason: "DOI → Europe PMC"))
        }

        // 2) GO 术语（GO:0008150）
        if input.matches(#"(?i)^GO:\d+$"#) {
            matches.append(Match(toolId: "go", query: input.uppercased(),
                                 confidence: 0.95, reason: DT.t("GO 术语编号", "GO term ID")))
        }

        // 3) Ensembl ID（ENSG / ENST / ENSP / ENSG...）
        if input.matches(#"(?i)^ENS[FGTPE]\d{11}$"#) {
            matches.append(Match(toolId: "ensembl", query: input,
                                 confidence: 0.95, reason: "Ensembl ID"))
        }

        // 4) Pfam 结构域（PF00001）
        if input.matches(#"^PF\d{5}$"#) {
            matches.append(Match(toolId: "pfam", query: input.uppercased(),
                                 confidence: 0.90, reason: DT.t("Pfam 结构域", "Pfam domain")))
        }

        // 5) KEGG 条目（K/C/M/D/H + 5 位数字）
        if input.matches(#"^[KCMDH]\d{5}$"#) {
            matches.append(Match(toolId: "kegg", query: input.uppercased(),
                                 confidence: 0.85, reason: DT.t("KEGG 条目", "KEGG entry")))
        }

        // 6) UniProt Accession（官方正则：6 位或 10 位）
        if input.matches(#"^[OPQ][0-9][A-Z0-9]{3}[0-9]$|^[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2}$"#) {
            matches.append(Match(toolId: "uniprot", query: input,
                                 confidence: 0.90, reason: "UniProt Accession"))
        }

        // 7) PDB 结构 ID（4 位，以数字开头，如 1ABC / 4HHB）
        //    P2-1：排除纯数字，避免把 TaxID / 4 位 PMID 高置信度误路由到 PDB
        if input.matches(#"^[0-9][A-Za-z0-9]{3}$"#), !input.matches(#"^\d+$"#) {
            matches.append(Match(toolId: "pdb", query: input.uppercased(),
                                 confidence: 0.95, reason: DT.t("PDB 结构 ID", "PDB structure ID")))
        }

        // 8) 4 位全大写字母：既可能是 PDB 也可能是基因符号（歧义，低置信度双候选）
        if input.matches(#"^[A-Z]{4}$"#) {
            matches.append(Match(toolId: "pdb", query: input.uppercased(),
                                 confidence: 0.50, reason: DT.t("可能为 PDB ID", "Maybe a PDB ID")))
            matches.append(Match(toolId: "ncbi_gene", query: input,
                                 confidence: 0.50, reason: DT.t("可能为基因符号", "Maybe a gene symbol")))
        }

        // 9) 基因符号（字母开头，可含数字，长度 ≥ 2，且未被上面更精确的规则命中）
        if input.matches(#"^[A-Za-z][A-Za-z0-9]*$"#), input.count >= 2 {
            if !matches.contains(where: { $0.toolId == "ncbi_gene" }) {
                let conf: Double = (input.contains(where: { $0.isNumber }) || input.count > 4) ? 0.85 : 0.60
                matches.append(Match(toolId: "ncbi_gene", query: input,
                                     confidence: conf, reason: DT.t("基因符号", "Gene symbol")))
            }
        }

        // 10) 纯数字：PMID 与 TaxID 无法仅凭形态区分（歧义，双候选）；
        //     P2-1：4 位纯数字补充 PDB 低置信度第三候选，使歧义弹窗覆盖全部三种可能
        if input.matches(#"^\d+$"#) {
            matches.append(Match(toolId: "pubmed", query: input,
                                 confidence: 0.70, reason: DT.t("可能为 PubMed ID", "Maybe a PubMed ID")))
            matches.append(Match(toolId: "ncbi_taxonomy", query: input,
                                 confidence: 0.70, reason: DT.t("可能为 TaxID", "Maybe a TaxID")))
            if input.count == 4 {
                matches.append(Match(toolId: "pdb", query: input,
                                     confidence: 0.45, reason: DT.t("可能为 PDB ID", "Maybe a PDB ID")))
            }
        }

        // 去重：同 toolId 仅保留最高置信度候选
        var best: [String: Match] = [:]
        for m in matches {
            if let existing = best[m.toolId] {
                if m.confidence > existing.confidence { best[m.toolId] = m }
            } else {
                best[m.toolId] = m
            }
        }
        return Array(best.values).sorted { $0.confidence > $1.confidence }
    }

    // MARK: - 路由决策建议

    /// 根据候选列表给出路由建议：
    /// - `.route(match)`：置信度足够高且明显优于次优候选 → 直接跳转
    /// - `.choose(matches)`：存在歧义 → 由 UI 弹窗让用户选择
    enum RoutingDecision {
        case route(Match)
        case choose([Match])
    }

    /// 判定阈值：
    /// - 单一候选 → 直接跳转
    /// - 最高置信度 ≥ 0.85 且 与次优候选差距 ≥ 0.2 → 直接跳转（足够确定）
    /// - 其余 → 弹窗选择
    static func decide(_ matches: [Match]) -> RoutingDecision {
        guard !matches.isEmpty else { return .choose([]) }
        if matches.count == 1 { return .route(matches[0]) }
        let top = matches[0]
        let second = matches[1]
        if top.confidence >= 0.85 && (top.confidence - second.confidence) >= 0.2 {
            return .route(top)
        }
        return .choose(matches)
    }
}
