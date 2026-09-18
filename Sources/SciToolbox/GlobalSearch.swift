import SwiftUI

// MARK: - 全库搜索（P1-4：兑现「一站式检索」承诺）

/// 聚合检索服务：对全部 Provider 并发发起 search(query:)。
/// NCBI 类请求由 APIClient 的 RequestThrottle 自动串行化（3s 间隔），
/// 单库失败不影响其他库。
enum AggregatedSearchService {
    static func searchAll(_ query: String, providers: [any ToolProvider]) async -> [String: (items: [ResultItem], error: String?)] {
        await withTaskGroup(of: (String, [ResultItem], String?).self) { group in
            for p in providers {
                group.addTask {
                    do {
                        let r = try await p.search(query: query, offset: 0, pickerId: nil)
                        return (p.id, r.items, nil)
                    } catch {
                        return (p.id, [], error.localizedDescription)
                    }
                }
            }
            var dict: [String: ([ResultItem], String?)] = [:]
            for await (id, items, err) in group {
                dict[id] = (items, err)
            }
            return dict
        }
    }
}

// MARK: - GlobalSearchField（首页「全库搜索」输入框）

/// 首页智能识别框下方的全库搜索入口：输入任意关键词，在所有数据库并行检索。
struct GlobalSearchField: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            HStack(spacing: Theme.sp2) {
                Image(systemName: "globe.asia.australia")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                Text(L10n.t(.globalSearch))
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .textCase(.uppercase)
                    .tracking(Theme.trackSection)
            }

            HStack(spacing: Theme.sp2) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.ink3)
                    .font(.system(size: 13))

                TextField(L10n.t(.globalSearchDesc, ToolRegistry.shared.providers.count), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.fsBody))
                    .focused($isFocused)
                    .onSubmit { submit() }
                    .submitLabel(.search)

                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.ink2)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .transition(.opacity)
                    .accessibilityLabel(L10n.t(.clearSearch))
                }

                Button(action: submit) {
                    Text(L10n.t(.globalSearch))
                        .font(.system(size: Theme.fsBody, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.sp4)
                        .padding(.vertical, Theme.sp1 + 2)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.globalSearch))
            }
            .padding(.horizontal, Theme.sp4)
            .padding(.vertical, Theme.sp3)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLg)
                    .strokeBorder(isFocused ? Theme.accent : Theme.line,
                                  lineWidth: isFocused ? 1.5 : 0.5)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)

            Text(L10n.t(.globalSearchDesc, ToolRegistry.shared.providers.count))
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.ink3)
        }
        .padding(.horizontal, Theme.sp6)
        // P1-6：首页 ⌘F 聚焦智能识别/全库搜索
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Clipboard.showToast(L10n.t(.inputKeyword))
            return
        }
        NotificationCenter.default.post(
            name: .openGlobalSearch,
            object: nil,
            userInfo: ["query": trimmed]
        )
        isFocused = false
    }
}

// MARK: - GlobalSearchScreen（全库搜索结果，按分类分组）

struct GlobalSearchScreen: View {
    let query: String
    var onItemTapped: ((ResultItem, any ToolProvider) -> Void)? = nil

    @EnvironmentObject var registry: ToolRegistry
    @State private var isLoading = true
    @State private var results: [String: (items: [ResultItem], error: String?)] = [:]
    @State private var searchTask: Task<Void, Never>?

    private struct ToolGroup: Identifiable {
        let id: String  // category.rawValue
        let category: ToolCategory
        let providers: [any ToolProvider]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            thinDivider()
            if isLoading {
                StateView(state: .loading(text: L10n.t(.loadingDetail)))
            } else {
                resultsList
            }
        }
        .navigationTitle(L10n.t(.globalSearch))
        .onAppear { runSearch() }
        .onDisappear { searchTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: Theme.sp3) {
            Image(systemName: "globe.asia.australia")
                .font(.system(size: 14))
                .foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(.globalSearch))
                    .font(.system(size: Theme.fsHeadline, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text("“\(query)”")
                    .font(.system(size: Theme.fsSmall, design: .monospaced))
                    .foregroundColor(Theme.ink2)
            }
            Spacer()
            Button(action: runSearch) {
                Label(L10n.t(.reSearch), systemImage: "arrow.clockwise")
                    .font(.system(size: Theme.fsSmall))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp4)
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.sp4) {
                let groups = groupedResults
                if groups.isEmpty {
                    StateView(state: .empty(text: L10n.t(.noResultMatch, query)))
                        .padding(.top, Theme.sp6)
                } else {
                    ForEach(groups) { group in
                        categorySection(group)
                    }
                    .padding(.bottom, Theme.sp6)
                }
            }
            .padding(.top, Theme.sp4)
        }
    }

    private func categorySection(_ group: ToolGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            HStack(spacing: Theme.sp2) {
                Text(group.category.abbreviation)
                    .font(.system(size: Theme.fsCaption, weight: .semibold))
                    .foregroundColor(Theme.categoryColor(group.category))
                    .frame(width: 16, height: 16)
                    .background(Theme.categoryColor(group.category).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(group.category.name)
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .textCase(.uppercase)
                    .tracking(Theme.trackSection)
                Spacer()
            }
            .padding(.horizontal, Theme.sp5)

            VStack(spacing: 0) {
                ForEach(group.providers, id: \.id) { provider in
                    providerSection(provider)
                    softDivider()
                }
            }
            .cardStyle()
            .padding(.horizontal, Theme.sp5)
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: any ToolProvider) -> some View {
        let result = results[provider.id]
        let items = result?.items ?? []
        let err = result?.error
        let color = Theme.categoryColor(provider.category)

        VStack(alignment: .leading, spacing: Theme.sp1) {
            // 库头：图标 + 名称 + 命中数 + 「在 X 库中打开」
            HStack(spacing: Theme.sp2) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(provider.name)
                    .font(.system(size: Theme.fsSmall, weight: .medium))
                    .foregroundColor(Theme.ink)
                if !items.isEmpty {
                    Text(L10n.t(.resultCountShort, items.count))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                } else if err != nil {
                    Text(L10n.t(.failed))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.semanticWarning)
                }
                Spacer(minLength: 0)
                Button(action: {
                    NotificationCenter.default.post(
                        name: .navigateToTool,
                        object: nil,
                        userInfo: ["toolId": provider.id, "query": query]
                    )
                }) {
                    Text(L10n.t(.routeTo, provider.name))
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.routeTo, provider.name))
            }
            .padding(.horizontal, Theme.sp3)
            .padding(.top, Theme.sp2)

            // 该库命中条目（最多 5 条）
            if !items.isEmpty {
                ForEach(items.prefix(5)) { item in
                    Button(action: { onItemTapped?(item, provider) }) {
                        HStack(spacing: Theme.sp2) {
                            if let badge = item.badge {
                                Text(badge)
                                    .font(.system(size: Theme.fsSmall, design: .monospaced))
                                    .foregroundColor(Theme.ink3)
                                    .frame(minWidth: 50, alignment: .leading)
                                    .lineLimit(1)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title)
                                    .font(.system(size: Theme.fsSmall))
                                    .foregroundColor(Theme.ink)
                                    .lineLimit(1)
                                if let sub = item.subtitle {
                                    Text(sub)
                                        .font(.system(size: Theme.fsCaption))
                                        .foregroundColor(Theme.ink3)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .light))
                                .foregroundColor(Theme.ink4)
                        }
                        .padding(.horizontal, Theme.sp3)
                        .padding(.vertical, Theme.sp1 + 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(L10n.t(.viewDetailA11y, item.title))
                }
                if items.count > 5 {
                    Text(L10n.t(.resultCount, items.count - 5))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                        .padding(.horizontal, Theme.sp3)
                        .padding(.bottom, Theme.sp1)
                }
            } else if let err {
                Text(L10n.t(.fetchFailed, err))
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .padding(.horizontal, Theme.sp3)
                    .padding(.bottom, Theme.sp1)
                    .lineLimit(2)
            } else {
                Text(L10n.t(.noResultMatch, query))
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .padding(.horizontal, Theme.sp3)
                    .padding(.bottom, Theme.sp1)
            }
        }
        .padding(.bottom, Theme.sp2)
    }

    private var groupedResults: [ToolGroup] {
        ToolCategory.allCases.compactMap { cat in
            let providers = registry.providers.filter { $0.category == cat }
            guard !providers.isEmpty else { return nil }
            return ToolGroup(id: cat.rawValue, category: cat, providers: providers)
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        isLoading = true
        results = [:]
        let q = query
        let providers = registry.providers
        searchTask = Task {
            let result = await AggregatedSearchService.searchAll(q, providers: providers)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                results = result
                isLoading = false
            }
        }
    }
}
