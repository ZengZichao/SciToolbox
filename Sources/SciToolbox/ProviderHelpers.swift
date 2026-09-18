import Foundation

// MARK: - Provider Helpers (shared, eliminates boilerplate across providers)

/// 跨 Provider 复用的纯函数：作者格式化、跨库互链构建、DOI/URL 解析。
/// 目的：消除 16 个 Provider 中重复的样板代码（解析健壮性与展示增强的统一基础）。

enum ProviderHelpers {

    /// 截断式作者列表格式化："A, B, C 等"（超过 max 用「等」）。
    static func formatAuthors(_ authors: [String], max: Int = 3) -> String {
        guard !authors.isEmpty else { return "" }
        if authors.count <= max {
            return authors.joined(separator: ", ")
        }
        return authors.prefix(max).joined(separator: ", ") + DT.t(" 等", " et al.")
    }

    /// 构建跨库互链。query 会做基本清理（去除首尾空白）。
    static func xlink(_ toolId: String, _ query: String, _ label: String) -> XLink {
        XLink(toolId: toolId, query: query.trimmingCharacters(in: .whitespaces), label: label)
    }

    /// 将可能的 DOI 归一化为可点击的 https URL。
    /// 支持 "10.xxxx/..." 原始 DOI 或已带 scheme 的链接；非法返回 nil。
    static func doiURL(_ doi: String) -> URL? {
        let d = doi.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty else { return nil }
        if d.lowercased().hasPrefix("http://") || d.lowercased().hasPrefix("https://") {
            return URL(string: d)
        }
        if d.lowercased().hasPrefix("doi:") {
            return URL(string: "https://doi.org/" + d.dropFirst(4))
        }
        if d.hasPrefix("10.") {
            return URL(string: "https://doi.org/" + d)
        }
        return nil
    }

    /// 是否为可识别的 URL（用于正文行内可点击渲染）。
    static func isURL(_ s: String) -> Bool {
        s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://")
    }

    /// 统一分页结果（解析一致性增强）。
    /// - fetchedTotal: API 直接给出的真实总数（如 PubMed/PDB 的 count）。为 nil 时按「本页是否装满」启发式推断。
    /// - alreadyLoaded: 翻页前已加载的条数（用于精确判断末页），首屏传 0。
    /// 返回 (total, hasMore)：total 在未知时保持 nil（由 UI 降级展示「已加载 N 条」）。
    static func paginate(items: [ResultItem], pageSize: Int, fetchedTotal: Int? = nil, alreadyLoaded: Int = 0) -> (total: Int?, hasMore: Bool) {
        if let total = fetchedTotal {
            return (total, alreadyLoaded + items.count < total)
        }
        let hasMore = items.count >= pageSize
        return (nil, hasMore)
    }
}
