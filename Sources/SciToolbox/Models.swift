import Foundation

// MARK: - Tool Category

enum ToolCategory: String, CaseIterable, Identifiable {
    case taxonomy = "taxonomy"
    case gene = "gene"
    case protein = "protein"
    case functionCategory = "function"
    case literature = "literature"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .taxonomy: L10n.t(.catTaxonomy)
        case .gene: L10n.t(.catGene)
        case .protein: L10n.t(.catProtein)
        case .functionCategory: L10n.t(.catFunction)
        case .literature: L10n.t(.catLiterature)
        }
    }
    /// 单字缩写（H24：分类线索在颜色之外叠加文本标签，色觉障碍用户也能区分）。
    var abbreviation: String {
        switch self {
        case .taxonomy: L10n.t(.catAbbrTaxonomy)
        case .gene: L10n.t(.catAbbrGene)
        case .protein: L10n.t(.catAbbrProtein)
        case .functionCategory: L10n.t(.catAbbrFunction)
        case .literature: L10n.t(.catAbbrLiterature)
        }
    }
}

// MARK: - Search Result

struct SearchResult {
    var items: [ResultItem]
    var total: Int?
    var hasMore: Bool = false
}

struct ResultItem: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var badge: String?
    var meta: String?
    /// Extra context passed to detail request (e.g. accession, taxid)
    var extra: [String: String]?
}

// MARK: - Detail Model

struct DetailModel {
    var headerTitle: String
    var headerSubtitle: String?
    var headerMeta: [String]?
    var sections: [KVSection]
    var freeTextBlocks: [FreeTextBlock]
    var actions: [DetailAction]
    var xlinks: [XLink]
    var webUrl: String?
    /// Optional preview image URL (e.g. PDB structure image, AlphaFold cartoon)
    var imageUrl: String?

    init(headerTitle: String, headerSubtitle: String? = nil, headerMeta: [String]? = nil,
         sections: [KVSection] = [], freeTextBlocks: [FreeTextBlock] = [],
         actions: [DetailAction] = [], xlinks: [XLink] = [],
         webUrl: String? = nil, imageUrl: String? = nil) {
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.headerMeta = headerMeta
        self.sections = sections
        self.freeTextBlocks = freeTextBlocks
        self.actions = actions
        self.xlinks = xlinks
        self.webUrl = webUrl
        self.imageUrl = imageUrl
    }
}

struct KVSection: Identifiable, Hashable {
    var id = UUID()
    var title: String?
    var rows: [KVRow]
}

struct KVRow: Hashable {
    var key: String
    var value: String
    var copyable: Bool
    /// 可选：点击 value 在浏览器打开此 URL（如 DOI 链接）。
    var link: URL?
    /// 可选：点击 value 触发跨库互链跳转（如 PDB/GO/Pfam accession）。
    var xlinkTarget: XLink?
    init(_ key: String, _ value: String, copyable: Bool = false,
         link: URL? = nil, xlinkTarget: XLink? = nil) {
        self.key = key
        self.value = value
        self.copyable = copyable
        self.link = link
        self.xlinkTarget = xlinkTarget
    }
}

struct FreeTextBlock: Identifiable {
    var id = UUID()
    var title: String?
    var text: String
    var copyable: Bool
}

struct DetailAction: Identifiable {
    var id = UUID()
    var label: String
    var payload: String
    var style: ActionStyle
    /// 动作类型：`.copy` 复制 payload 到剪贴板；`.export` 将 payload 写入文件。
    var kind: Kind = .copy
    /// 当 `kind == .export` 时使用的文件名与扩展名（不含点）。
    var exportFileName: String?
    var exportExt: String?

    enum ActionStyle { case primary, secondary }
    enum Kind: Hashable { case copy, export }
}

struct XLink: Identifiable, Hashable {
    var id = UUID()
    var toolId: String
    var query: String
    var label: String
}

// MARK: - Picker Option (for tools like KEGG/Ensembl that need a selector)

struct PickerOption: Identifiable, Hashable {
    var id: String
    var label: String
    var example: String?
}

// MARK: - Dynamic JSON helper (for parsing complex API responses)

struct JSON {
    let value: Any

    init(_ value: Any) { self.value = value }
    init?(_ data: Data) {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }
        self.value = parsed
    }

    var string: String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
    /// 带默认值的字符串提取，避免字段缺失时静默得到 nil（解析健壮性增强）。
    func string(or default: String) -> String {
        (value as? String) ?? (value as? NSNumber)?.stringValue ?? `default`
    }
    var int: Int? {
        if let n = value as? NSNumber { return n.intValue }
        // NCBI esearch/esummary 的 count、slen 等字段在 JSON 中为字符串（如 "15234"）
        if let s = value as? String, let i = Int(s) { return i }
        return nil
    }
    /// 带默认值的整数提取。
    func int(or default: Int) -> Int {
        (value as? NSNumber)?.intValue ?? `default`
    }
    var double: Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
    var bool: Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
    var arrayValue: [JSON] {
        (value as? [Any])?.map(JSON.init) ?? []
    }
    var dictValue: [String: JSON] {
        guard let d = value as? [String: Any] else { return [:] }
        return d.mapValues(JSON.init)
    }
    var isNull: Bool { value is NSNull }

    subscript(key: String) -> JSON {
        JSON(dictValue[key]?.value ?? NSNull())
    }
    subscript(index: Int) -> JSON {
        let arr = arrayValue
        guard index >= 0, index < arr.count else { return JSON(NSNull()) }
        return arr[index]
    }

    var isEmpty: Bool {
        if let d = value as? [String: Any] { return d.isEmpty }
        if let a = value as? [Any] { return a.isEmpty }
        if let s = value as? String { return s.isEmpty }
        return isNull
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case network(String)
    case timeout
    case http(Int)
    case parse(String)
    case notFound(String)
    case invalidInput(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .network(let msg): L10n.t(.networkError, msg)
        case .timeout: L10n.t(.timeoutError)
        case .http(let code):
            switch code {
            case 429: L10n.t(.http429)
            case 404: L10n.t(.http404)
            case 500...599: L10n.t(.http5xx, code)
            default: L10n.t(.httpOther, code)
            }
        case .parse(let msg): L10n.t(.parseError, msg)
        case .notFound(let msg): msg
        case .invalidInput(let msg): msg
        case .server(let msg): msg
        }
    }
}
