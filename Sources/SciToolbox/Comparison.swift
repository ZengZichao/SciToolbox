import Foundation
import SwiftUI

// MARK: - 跨库对比（C10 / C11）
//
// C11：各 Provider 的详情版面不统一，跨库阅读需重新「学习」每个库的字段。
// 这里在 DetailModel 层抽出一组**统一对比字段**（名称 / 来源库 / 分类 / 物种描述 /
// 关键属性），不改动任何 Provider，即可生成跨库对齐的对比表。
//
// C10：详情栏支持把多条目加入对比，并以并排对齐表呈现，满足科研「同时看
// PDB 结构 + UniProt 功能 + GO 术语」的并排对比需求。

/// 对齐对比表中的一行（以 canonical `id` 作为跨条目对齐键）。
struct CompareField: Identifiable, Hashable {
    let id: String        // 跨条目对齐键（统一字段用固定键，属性用 "attr:<原字段名>"）
    let label: String     // 展示键名
    let value: String
    let copyable: Bool
}

/// 一条对比条目（承载已抓取或待抓取的详情）。
struct ComparisonItem: Identifiable {
    let id = UUID()
    let toolId: String
    let toolName: String
    let category: ToolCategory
    let itemId: String
    let query: String?
    let context: [String: String]?
    var detail: DetailModel?
}

/// 对比容器（全局单例）：管理已加入对比的条目，按需异步抓取缺失详情。
final class ComparisonStore: ObservableObject, @unchecked Sendable {
    static let shared = ComparisonStore()

    /// 最多并排对比条目数（兼顾窄栏可读性与性能）。
    static let maxItems = 4

    @Published private(set) var items: [ComparisonItem] = []

    func contains(toolId: String, itemId: String) -> Bool {
        items.contains { $0.toolId == toolId && $0.itemId == itemId }
    }

    /// 加入对比。detail 可预填（详情头部加入时已有）；否则异步抓取。
    func add(toolId: String, toolName: String, category: ToolCategory,
             itemId: String, query: String? = nil, context: [String: String]? = nil,
             detail: DetailModel? = nil) {
        guard !contains(toolId: toolId, itemId: itemId) else {
            Clipboard.showToast(L10n.t(.alreadyInCompare))
            return
        }
        guard items.count < ComparisonStore.maxItems else {
            Clipboard.showToast(L10n.t(.compareLimit, ComparisonStore.maxItems))
            return
        }
        let item = ComparisonItem(toolId: toolId, toolName: toolName, category: category,
                                  itemId: itemId, query: query, context: context, detail: detail)
        items.append(item)
        Clipboard.showToast(L10n.t(.addedToCompare, items.count, ComparisonStore.maxItems))
        if detail == nil { loadDetail(for: item.id) }
    }

    func remove(_ item: ComparisonItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    private func loadDetail(for cid: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == cid }) else { return }
        let item = items[idx]
        guard let provider = ToolRegistry.shared.find(id: item.toolId) else { return }
        Task {
            do {
                let model = try await provider.detail(id: item.itemId, context: item.context)
                await MainActor.run {
                    guard let i = self.items.firstIndex(where: { $0.id == cid }) else { return }
                    self.items[i].detail = model
                    self.objectWillChange.send()
                }
            } catch {
                await MainActor.run {
                    guard let i = self.items.firstIndex(where: { $0.id == cid }) else { return }
                    self.items[i].detail = DetailModel(
                        headerTitle: item.itemId,
                        sections: [KVSection(title: L10n.t(.hint), rows: [
                            KVRow(DT.t("状态", "Status"), L10n.t(.detailLoadFailed, error.localizedDescription))
                        ])]
                    )
                    self.objectWillChange.send()
                }
            }
        }
    }
}

// MARK: - DetailModel 统一对比字段（C11）

extension DetailModel {
    /// 抽出跨库一致的对比字段：统一字段（名称/来源库/分类/物种描述）+ 首个信息区的关键属性。
    /// `sourceName` 与 `category` 由调用方（已知 Provider）注入，使字段跨库对齐。
    func comparisonFields(sourceName: String, category: ToolCategory) -> [CompareField] {
        var fields: [CompareField] = []
        fields.append(CompareField(id: "name", label: L10n.t(.name), value: headerTitle, copyable: true))
        fields.append(CompareField(id: "source", label: L10n.t(.source), value: sourceName, copyable: false))
        fields.append(CompareField(id: "category", label: L10n.t(.category), value: category.name, copyable: false))
        if let subtitle = headerSubtitle, !subtitle.isEmpty {
            fields.append(CompareField(id: "subtitle", label: L10n.t(.speciesDesc), value: subtitle, copyable: false))
        }
        // 首个非空 section 作为「关键属性」，按各库原字段名对齐（attr:<字段名>）。
        if let primary = sections.first(where: { !$0.rows.isEmpty }) {
            for row in primary.rows.prefix(8) {
                fields.append(CompareField(id: "attr:\(row.key)", label: row.key,
                                           value: row.value, copyable: row.copyable))
            }
        }
        return fields
    }
}

// MARK: - 对比视图（C10）

struct ComparisonView: View {
    @ObservedObject var store = ComparisonStore.shared
    var onOpenItem: ((ComparisonItem) -> Void)? = nil

    private let labelW: CGFloat = 84
    private let itemW: CGFloat = 196

    /// 计算对齐键顺序与展示标签（固定统一字段优先，再追加各库属性键）。
    private func computeOrder() -> ([String], [String: String]) {
        var order: [String] = []
        var labels: [String: String] = [:]
        let fixed: [(String, String)] = [
            ("name", L10n.t(.name)), ("source", L10n.t(.source)),
            ("category", L10n.t(.category)), ("subtitle", L10n.t(.speciesDesc))
        ]
        for (k, l) in fixed { labels[k] = l; order.append(k) }
        for item in store.items {
            guard let d = item.detail else { continue }
            for f in d.comparisonFields(sourceName: item.toolName, category: item.category) {
                if labels[f.id] == nil { labels[f.id] = f.label; order.append(f.id) }
            }
        }
        return (order, labels)
    }

    private func value(for item: ComparisonItem, key: String) -> String? {
        guard let d = item.detail else { return nil }
        return d.comparisonFields(sourceName: item.toolName, category: item.category)
            .first(where: { $0.id == key })?.value
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            if store.items.isEmpty {
                emptyHint
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    let (order, labels) = computeOrder()
                    // 表头：各条目名称 + 来源 + 移除
                    HStack(spacing: 0) {
                        Color.clear.frame(width: labelW, height: 1)
                        ForEach(store.items) { item in
                            itemHeader(item)
                                .frame(width: itemW)
                        }
                    }
                    Divider().opacity(0.6)
                    // 字段行（跨条目按统一键对齐）
                    ForEach(order, id: \.self) { key in
                        HStack(spacing: 0) {
                            Text(labels[key] ?? key)
                                .font(.system(size: Theme.fsCaption))
                                .foregroundColor(Theme.ink3)
                                .frame(width: labelW, alignment: .trailing)
                                .padding(.trailing, Theme.sp2)
                                .padding(.vertical, Theme.sp2)
                            ForEach(store.items) { item in
                                valueCell(item: item, key: key)
                                    .frame(width: itemW, alignment: .leading)
                            }
                        }
                        Divider().opacity(0.4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Theme.sp4)
            }
        }
        .background(Theme.sidebarBackground)
    }

    private var emptyHint: some View {
        VStack(spacing: Theme.sp3) {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.ink3)
            Text(L10n.t(.compareEmpty))
                .font(.system(size: Theme.fsBody))
                .foregroundColor(Theme.ink3)
            Text(L10n.t(.compareEmptyHint))
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemHeader(_ item: ComparisonItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.categoryColor(item.category))
                    .frame(width: 3, height: 16)
                Text(item.toolName)
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: { store.remove(item) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.ink4)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(L10n.t(.removeFromCompare, item.toolName))
            }
            Button(action: { onOpenItem?(item) }) {
                Text(item.detail?.headerTitle ?? item.itemId)
                    .font(.system(size: Theme.fsSmall, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(L10n.t(.viewEntryA11y, item.detail?.headerTitle ?? item.itemId))
        }
        .padding(.horizontal, Theme.sp2)
        .padding(.vertical, Theme.sp2)
    }

    private func valueCell(item: ComparisonItem, key: String) -> some View {
        Group {
            if item.detail == nil {
                Text(L10n.t(.loadingCompare))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink4)
            } else if let v = value(for: item, key: key), !v.isEmpty {
                Text(v)
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("—")
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink4)
            }
        }
        .padding(.horizontal, Theme.sp2)
        .padding(.vertical, Theme.sp2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
