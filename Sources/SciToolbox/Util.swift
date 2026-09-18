import AppKit
import Network
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Clipboard

enum Clipboard {
    /// 复制文本到剪贴板并返回是否成功（F18：写入结果校验，失败时提示，避免"以为已复制"）。
    @discardableResult
    static func copy(_ text: String?, tip: String? = nil) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        if ok {
            if let tip { showToast(tip) }
        } else {
            // P2-11：复制失败用专用文案，不再与导出失败混用
            showToast(L10n.t(.copyFailed))
        }
        return ok
    }

    static func showToast(_ message: String) {
        Task { @MainActor in
            AppToast.shared.show(message)
        }
    }

    /// 带撤销能力的 Toast：删除类操作调用（P0-1：单条删除 → 可撤销）。
    static func showUndoableToast(_ message: String, undo: @escaping () -> Void) {
        Task { @MainActor in
            AppToast.shared.show(message, undo: undo)
        }
    }
}

// MARK: - Toast (simple overlay + undo support)

@MainActor
final class AppToast: ObservableObject {
    static let shared = AppToast()
    @Published var message: String?
    @Published var isVisible = false
    /// 撤销闭包（删除类操作）：Toast 右侧渲染「撤销」按钮时使用（P0-1）。
    @Published var undoAction: (() -> Void)?

    private var hideTask: Task<Void, Never>?

    /// Whether the user has enabled Reduce Motion in System Settings.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func show(_ msg: String, undo: (() -> Void)? = nil) {
        hideTask?.cancel()
        undoAction = undo
        let enterAnim = reduceMotion ? nil : Animation.easeOut(duration: 0.2)
        withAnimation(enterAnim) {
            message = msg
            isVisible = true
        }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    // Asymmetric: exit faster than enter (system response should snap)
                    let hideAnim = self.reduceMotion ? nil : Animation.easeOut(duration: 0.25)
                    withAnimation(hideAnim) {
                        self.isVisible = false
                        self.undoAction = nil
                    }
                }
            }
        }
    }

    /// 用户点击「撤销」：执行回滚并立即隐藏。
    func performUndo() {
        undoAction?()
        hideTask?.cancel()
        withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.2)) {
            isVisible = false
            undoAction = nil
        }
    }
}

// MARK: - Export helpers

enum ExportUtil {
    static func fasta(header: String, sequence: String) -> String {
        var lines = [">\(header)"]
        var idx = sequence.startIndex
        while idx < sequence.endIndex {
            let end = sequence.index(idx, offsetBy: 60, limitedBy: sequence.endIndex) ?? sequence.endIndex
            lines.append(String(sequence[idx..<end]))
            idx = end
        }
        return lines.joined(separator: "\n")
    }

    static func bibtex(pmid: String, title: String, authors: [String], journal: String, year: String) -> String {
        // P3-11：作者全名含空格/逗号会生成非法 BibTeX key，做字符清洗
        let baseKey = (authors.first ?? "Anonymous") + (year.isEmpty ? "nd" : year)
        let key = baseKey.filter { $0.isLetter || $0.isNumber }
        return """
        @article{\(key),
          title = {\(title)},
          author = {\(authors.joined(separator: " and "))},
          journal = {\(journal)},
          year = {\(year)},
          note = {PMID: \(pmid)}
        }
        """
    }

    /// RIS citation format — compatible with EndNote, Mendeley, Zotero, etc.
    static func ris(title: String, authors: [String], journal: String, year: String,
                    pmid: String = "", doi: String = "", volume: String = "", issue: String = "", pages: String = "") -> String {
        var lines = ["TY  - JOUR", "TI  - \(title)"]
        for a in authors { lines.append("AU  - \(a)") }
        if !journal.isEmpty { lines.append("JO  - \(journal)") }
        if !year.isEmpty { lines.append("PY  - \(year)") }
        if !volume.isEmpty { lines.append("VL  - \(volume)") }
        if !issue.isEmpty { lines.append("IS  - \(issue)") }
        if !pages.isEmpty { lines.append("SP  - \(pages)") }
        if !pmid.isEmpty { lines.append("AN  - PMID:\(pmid)") }
        if !doi.isEmpty { lines.append("DO  - \(doi)") }
        lines.append("ER  - ")
        return lines.joined(separator: "\n")
    }

    // MARK: - CSV builder

    /// 生成 CSV 文本（RFC 4180 风格：含逗号/引号/换行的单元格用双引号包裹并转义）。
    static func buildCSV(header: [String], rows: [[String]]) -> String {
        func escape(_ s: String) -> String {
            if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        var lines = [header.map(escape).joined(separator: ",")]
        for r in rows {
            lines.append(r.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Save panel

    /// 按扩展名选择正确的 UTType（P2-15：.json / .csv / .txt 不再一律被 Finder 识别为纯文本）。
    static func contentType(for ext: String) -> UTType {
        switch ext.lowercased() {
        case "json": return .json
        case "csv": return .commaSeparatedText
        case "fasta", "fa", "faa", "fna", "ffn": return UTType(filenameExtension: "fasta") ?? .plainText
        case "ris": return UTType(filenameExtension: "ris") ?? .plainText
        case "bib", "bibtex": return UTType(filenameExtension: "bib") ?? .plainText
        default: return .plainText
        }
    }

    /// 弹出保存面板，将文本写入用户指定文件。返回是否成功保存。
    /// P2-6：不再用 `try?` 吞掉写盘失败——失败时提示并返回 false，避免「以为已保存」。
    @discardableResult
    static func saveTextFile(_ content: String, defaultName: String, ext: String = "csv") -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName + "." + ext
        panel.allowedContentTypes = [contentType(for: ext)]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            guard let data = content.data(using: .utf8) else {
                Clipboard.showToast(L10n.t(.exportFailed2))
                return false
            }
            try data.write(to: url)
            return true
        } catch {
            Clipboard.showToast(L10n.t(.exportFailed2))
            return false
        }
    }
}

// MARK: - Network Monitor (offline awareness)

/// Monitors network connectivity using NWPathMonitor.
/// Provides a published `isOnline` flag that views can observe
/// to show friendly offline warnings instead of cryptic errors.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.scitoolbox.network-monitor", qos: .utility)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.isOnline = online
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - 领域文案本地化（Provider 层数据）

/// Provider 层 UI 文案（KV 键名、区块标题、动作按钮、meta 等）的双语入口（P0-1）。
/// 与 L10n（枚举字典）互补：此处面向「散落在 15 个 Provider 中的数据字面量」，
/// 直接给出中英两份文案，按当前语言取用。
enum DT {
    static func t(_ zh: String, _ en: String) -> String {
        switch AppLanguage.currentLang { case .zh: return zh; case .en: return en }
    }
}

// MARK: - Rank name mapping (NCBI taxonomy)

enum RankName {
    static let zhMap: [String: String] = [
        "superkingdom": "超界", "kingdom": "界", "subkingdom": "亚界",
        "superphylum": "总门", "phylum": "门", "subphylum": "亚门",
        "superclass": "总纲", "class": "纲", "subclass": "亚纲", "infraclass": "下纲",
        "cohort": "股", "superorder": "总目", "order": "目", "suborder": "亚目", "infraorder": "下目",
        "superfamily": "总科", "family": "科", "subfamily": "亚科", "tribe": "族", "subtribe": "亚族",
        "genus": "属", "subgenus": "亚属", "species": "种", "subspecies": "亚种",
        "variety": "变种", "form": "变型", "strain": "菌株", "biotype": "生物型",
        "clade": "支系", "no rank": "未定级", "isolate": "分离株"
    ]

    static let enMap: [String: String] = [
        "superkingdom": "Superkingdom", "kingdom": "Kingdom", "subkingdom": "Subkingdom",
        "superphylum": "Superphylum", "phylum": "Phylum", "subphylum": "Subphylum",
        "superclass": "Superclass", "class": "Class", "subclass": "Subclass", "infraclass": "Infraclass",
        "cohort": "Cohort", "superorder": "Superorder", "order": "Order", "suborder": "Suborder", "infraorder": "Infraorder",
        "superfamily": "Superfamily", "family": "Family", "subfamily": "Subfamily", "tribe": "Tribe", "subtribe": "Subtribe",
        "genus": "Genus", "subgenus": "Subgenus", "species": "Species", "subspecies": "Subspecies",
        "variety": "Variety", "form": "Form", "strain": "Strain", "biotype": "Biotype",
        "clade": "Clade", "no rank": "No rank", "isolate": "Isolate"
    ]

    static func localized(_ rank: String) -> String {
        switch AppLanguage.currentLang {
        case .zh: return zhMap[rank] ?? rank
        case .en: return enMap[rank] ?? rank
        }
    }

    /// 保留 cn 别名以兼容旧调用点。
    static func cn(_ rank: String) -> String { localized(rank) }
}

// MARK: - GTDB rank names

enum GTDBRank {
    static let zhNames: [String: String] = [
        "d": "域", "p": "门", "c": "纲", "o": "目", "f": "科", "g": "属", "s": "种"
    ]
    static let enNames: [String: String] = [
        "d": "Domain", "p": "Phylum", "c": "Class", "o": "Order", "f": "Family", "g": "Genus", "s": "Species"
    ]
    static func name(_ prefix: String) -> String {
        switch AppLanguage.currentLang {
        case .zh: return zhNames[prefix] ?? prefix
        case .en: return enNames[prefix] ?? prefix
        }
    }
}
