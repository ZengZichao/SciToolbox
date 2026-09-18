import SwiftUI

// MARK: - SearchScreen (search + results list; detail shown in separate column)

/// 搜索容器：搜索栏 + 数据来源标注 + 结果列表。
/// 详情不再在此视图内展示，而是通过 onItemTapped 回调传递给父级三栏布局的右侧详情栏。
struct SearchScreen: View {
    let provider: any ToolProvider
    var onItemTapped: ((ResultItem) -> Void)? = nil
    /// A4：查询词变化上报父级（供「返回上一工具」恢复上下文）。
    var onQueryChanged: ((String) -> Void)? = nil

    @State private var query = ""
    @State private var viewState: ViewState = .home
    @State private var searchResult: SearchResult?
    @State private var error: String?
    @State private var selectedPickerId: String = ""
    @State private var selectedItemId: String? = nil

    // Pagination state
    @State private var currentOffset = 0
    @State private var isLoadingMore = false
    /// 加载更多失败时的错误文案（P1-12：失败不再静默降级）
    @State private var loadMoreError: String?
    @State private var lastQuery = ""
    /// 结果内筛选关键字（前端过滤已加载的结果）
    @State private var inResultFilter = ""

    /// Cancels previous search Task to prevent stale results (race-condition guard)
    @State private var searchTask: Task<Void, Never>?
    /// Debounce task for picker changes (matches home page 500ms rhythm)
    @State private var pickerDebounceTask: Task<Void, Never>?

    // Focus state
    @FocusState private var isSearchFocused: Bool
    /// B8：仅首次进入该工具时自动聚焦（避免 ⌘K 跳转 / 工具切换时反复抢焦点）。
    @State private var hasFocusedOnce = false

    // History
    @StateObject private var history = SearchHistory.shared
    @StateObject private var favorites = LocalFavorites.shared

    // 批量选择
    @State private var selectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showAddToCollection = false
    /// D12：单行「加入集合」候选。
    @State private var singleCandidate: CollectionCandidate?

    /// C9：跨库互链跳转后自动带出首条详情
    @State private var autoOpenDetail = false
    /// P2-12：GTDB 空查询域级浏览是否已预置（仅首次）
    @State private var hasPresetGTDBSearch = false

    // F19：NCBI 节流提示 / F20：缓存命中提示
    @State private var showThrottleHint = false
    @State private var showCacheHint = false
    @State private var hintDismissTask: Task<Void, Never>?

    enum ViewState {
        case home, loading, results, error
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar area
            VStack(spacing: Theme.sp1 + 2) {
                SearchBar(
                    text: $query,
                    placeholder: provider.placeholder,
                    isFocused: $isSearchFocused,
                    trailingLabel: L10n.t(.identify),
                    trailingAction: {
                        NotificationCenter.default.post(
                            name: .smartRoute,
                            object: nil,
                            userInfo: ["input": query]
                        )
                    }
                ) {
                    performSearch()
                }

                // 键盘提示（G21/G22：可发现性）
                HStack(spacing: Theme.sp2) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.ink4)
                    Text(L10n.t(.keyboardHint))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Spacer()
                }

                // F19：NCBI 节流排队提示（不打断，仅提示）
                if showThrottleHint {
                    HStack(spacing: Theme.sp2) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(L10n.t(.throttleHint))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // F20：缓存命中提示（数据新鲜度感知）
                if showCacheHint {
                    HStack(spacing: Theme.sp2) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.ink4)
                        Text(L10n.t(.cacheHint))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Result filter (displayed below search bar for providers with picker options)
                // B5：顶部选择器明确为「检索范围」（重新检索语义），与下方本地过滤区分
                if let options = provider.pickerOptions, !options.isEmpty {
                    HStack(spacing: Theme.sp1 + 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.ink3)
                        Text(L10n.t(.searchScope))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                        if options.count > 4 {
                            // Menu style for many options (prevents overflow in narrow columns)
                            Picker(L10n.t(.searchScope), selection: $selectedPickerId) {
                                ForEach(options) { opt in
                                    Text(opt.label).tag(opt.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        } else {
                            // 自定义药丸式选择器：比 segmented 更轻量、更融合
                            ForEach(options) { opt in
                                let isSelected = selectedPickerId == opt.id
                                Button(action: { selectedPickerId = opt.id }) {
                                    Text(opt.label)
                                        .font(.system(size: Theme.fsCaption, weight: isSelected ? .medium : .regular))
                                        .foregroundColor(isSelected ? Theme.accent : Theme.ink3)
                                        .padding(.horizontal, Theme.sp2 + 2)
                                        .padding(.vertical, Theme.sp1)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.radiusSm)
                                                .fill(isSelected ? Theme.accent.opacity(0.10) : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.radiusSm)
                                                .strokeBorder(isSelected ? Theme.accent.opacity(0.25) : Theme.line, lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(PressableButtonStyle())
                                .accessibilityLabel(L10n.t(.searchScope))
                                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                // Data source note
                Text(provider.dataSourceNote)
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.inkSource)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.top, Theme.sp4)
            .padding(.bottom, Theme.sp3)

            // 批量选择工具条
            if viewState == .results {
                selectionToolbar
            }

            // 结果内筛选条（仅在有结果时显示）
            if viewState == .results,
               let result = searchResult, !result.items.isEmpty {
                inResultFilterBar
            }

            thinDivider()

            // Content area
            Group {
                switch viewState {
                case .home:
                    homeHint
                case .loading:
                    StateView(state: .loading())
                case .results:
                    let items = displayItems
                    if items.isEmpty {
                        if let result = searchResult, !result.items.isEmpty {
                            // 结果内筛选无匹配
                            VStack(spacing: Theme.sp3) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundColor(Theme.ink3)
                                Text(L10n.t(.noFilterMatch, inResultFilter))
                                    .font(.system(size: Theme.fsBody))
                                    .foregroundColor(Theme.ink3)
                                Text(L10n.t(.filterGuidance, result.items.count))
                                    .font(.system(size: Theme.fsSmall))
                                    .foregroundColor(Theme.ink3)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // P2-13：空结果差异化引导（区分"确实无结果"与建议动作）
                            VStack(spacing: Theme.sp3) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundColor(Theme.ink3)
                                Text(L10n.t(.noResultMatch, lastQuery))
                                    .font(.system(size: Theme.fsBody))
                                    .foregroundColor(Theme.ink3)
                                Text(L10n.t(.noResultGuidance))
                                    .font(.system(size: Theme.fsSmall))
                                    .foregroundColor(Theme.ink3)
                                // 呼应 P1-4：一键全库搜索
                                Button(action: {
                                    NotificationCenter.default.post(
                                        name: .openGlobalSearch,
                                        object: nil,
                                        userInfo: ["query": lastQuery]
                                    )
                                }) {
                                    Label(L10n.t(.searchInAll, lastQuery), systemImage: "globe.asia.australia")
                                        .font(.system(size: Theme.fsSmall, weight: .medium))
                                        .foregroundColor(Theme.accent)
                                        .padding(.horizontal, Theme.sp3)
                                        .padding(.vertical, Theme.sp1 + 2)
                                        .background(Theme.accent.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        ResultList(
                            items: items,
                            selectedItemId: $selectedItemId,
                            onTap: { item in onItemTapped?(item) },
                            onLoadMore: (searchResult?.hasMore ?? false) && !inResultFilterActive ? { loadMore() } : nil,
                            isLoadingMore: isLoadingMore,
                            hasMore: (searchResult?.hasMore ?? false) && !inResultFilterActive,
                            loadMoreError: loadMoreError,
                            selectionEnabled: selectionMode,
                            selectedIds: $selectedIds,
                            query: lastQuery,
                            favoritedIds: favoritedIds,
                            accentColor: Theme.categoryColor(provider.category),
                            onAddToCollection: { item in presentSingleAddToCollection(item) },
                            onAddToCompare: { item in
                                ComparisonStore.shared.add(
                                    toolId: provider.id,
                                    toolName: provider.name,
                                    category: provider.category,
                                    itemId: item.id,
                                    query: item.title,
                                    context: item.extra
                                )
                            }
                        )
                    }
                case .error:
                    if let msg = error {
                        // F17：错误态一键重试；P2-13：429/解析失败差异化文案由 APIError 提供
                        StateView(state: .error(message: msg, retry: { performSearch() }))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // P2-9：结果列表方向键导航（搜索框聚焦时不抢占）
            .onKeyPress(.upArrow) {
                guard viewState == .results, !isSearchFocused, !displayItems.isEmpty else { return .ignored }
                moveSelection(offset: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard viewState == .results, !isSearchFocused, !displayItems.isEmpty else { return .ignored }
                moveSelection(offset: 1)
                return .handled
            }
        }
        .navigationTitle(provider.name)
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $showAddToCollection) {
            AddToCollectionSheet(candidates: sheetCandidates()) { showAddToCollection = false }
        }
        .onAppear {
            if selectedPickerId.isEmpty {
                selectedPickerId = provider.defaultPickerId ?? provider.pickerOptions?.first?.id ?? ""
            }
            // B8：仅首次进入该工具时自动聚焦，避免反复切换时抢焦点
            if !hasFocusedOnce {
                isSearchFocused = true
                hasFocusedOnce = true
            }
            // P2-12：GTDB 首次进入即预置空查询，兑现「留空浏览域级」的占位符承诺
            if provider.id == "gtdb_official", !hasPresetGTDBSearch, viewState == .home {
                hasPresetGTDBSearch = true
                preseedGTDBSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prefillQuery)) { note in
            if let q = note.userInfo?["query"] as? String, !q.isEmpty {
                query = q
                // C9：跨库互链跳转后自动带出首条详情
                autoOpenDetail = (note.userInfo?["autoOpenDetail"] as? Bool) ?? false
                performSearch()
            }
        }
        // P1-6：⌘F 聚焦当前搜索框
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchFocused = true
        }
        // F19：NCBI 节流排队提示
        .onReceive(NotificationCenter.default.publisher(for: .throttleWaiting)) { _ in
            showThrottleHint = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .throttleResumed)) { _ in
            showThrottleHint = false
        }
        // F20：缓存命中提示（短暂显示）
        .onReceive(NotificationCenter.default.publisher(for: .cacheHit)) { _ in
            showCacheHint = true
            hintDismissTask?.cancel()
            hintDismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run { showCacheHint = false }
                }
            }
        }
        .onChange(of: query) { _, newValue in
            onQueryChanged?(newValue)
        }
        .onChange(of: selectedPickerId) { _, _ in
            // Re-trigger search when the result filter changes (with debounce)
            if !lastQuery.isEmpty {
                pickerDebounceTask?.cancel()
                pickerDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                    if !Task.isCancelled {
                        await MainActor.run {
                            performSearch()
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        switch viewState {
        case .results:
            if let r = searchResult {
                if r.hasMore {
                    if let total = r.total {
                        return L10n.t(.resultCountTotal, r.items.count, total)
                    }
                    return L10n.t(.resultLoaded, r.items.count)
                }
                return L10n.t(.resultCount, r.total ?? r.items.count)
            }
            return ""
        default: return ""
        }
    }

    private var homeHint: some View {
        ScrollView {
            VStack(spacing: Theme.sp5) {
                // Placeholder hint
                Text(provider.placeholder)
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.ink3)
                    .padding(.top, Theme.sp6)

                // Show example hint if picker has example
                if let options = provider.pickerOptions,
                   let selected = options.first(where: { $0.id == selectedPickerId }),
                   let example = selected.example {
                    HStack(spacing: Theme.sp1 + 2) {
                        Text(L10n.t(.example))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                        Button(action: {
                            query = example
                            performSearch()
                        }) {
                            Text(example)
                                .font(.system(size: Theme.fsSmall, design: .monospaced))
                                .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                    .padding(.top, Theme.sp1)
                }

                // Query history
                let toolHistory = history.entries(for: provider.id)
                if !toolHistory.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.sp2) {
                        HStack {
                            Text(L10n.t(.recent))
                                .font(.system(size: Theme.fsCaption))
                                .foregroundColor(Theme.ink3)
                                .textCase(.uppercase)
                                .tracking(Theme.trackSection)
                            Spacer()
                            Button(action: {
                                history.clear(toolId: provider.id)
                            }) {
                                Text(L10n.t(.clear))
                                    .font(.system(size: Theme.fsCaption))
                                    .foregroundColor(Theme.ink3)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel(L10n.t(.clear))
                        }

                        ForEach(toolHistory.prefix(8)) { entry in
                            HStack(spacing: Theme.sp2) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.ink3)
                                Button(action: {
                                    query = entry.query
                                    performSearch()
                                }) {
                                    Text(entry.query)
                                        .font(.system(size: Theme.fsSmall, design: .monospaced))
                                        .foregroundColor(Theme.ink2)
                                        .lineLimit(1)
                                }
                                .buttonStyle(PressableButtonStyle())
                                Spacer(minLength: 0)
                                Text(entry.relativeTime)
                                    .font(.system(size: Theme.fsCaption))
                                    .foregroundColor(Theme.ink3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, Theme.sp6)
                    .padding(.top, Theme.sp4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 批量选择工具条

    private var selectionToolbar: some View {
        VStack(spacing: Theme.sp2) {
            HStack(spacing: Theme.sp2) {
                if selectionMode {
                    Button(action: { selectionMode = false; selectedIds = [] }) {
                        Text(L10n.t(.done))
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(PressableButtonStyle())
                    Button(action: toggleSelectAll) {
                        Text(isAllSelected ? L10n.t(.deselectAll) : L10n.t(.selectAll))
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink2)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(isAllSelected ? L10n.t(.deselectAll) : L10n.t(.selectAll))
                    Spacer()
                    Text(L10n.t(.selected, selectedIds.count))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                } else {
                    Spacer()
                    Button(action: { selectionMode = true; selectedIds = [] }) {
                        Label(L10n.t(.select), systemImage: "checkmark.circle")
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink2)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(L10n.t(.enterMultiSelect))
                }
            }

            if selectionMode && !selectedIds.isEmpty {
                batchActionsView
            }
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp2)
    }

    private var batchActionsView: some View {
        FlowLayout(spacing: Theme.sp2) {
            batchButton(L10n.t(.copyAccessions), systemImage: "list.clipboard") { batchCopyAccessions() }
            batchButton(L10n.t(.batchFavorite), systemImage: "star") { batchFavorite() }
            batchButton(L10n.t(.addToCollection), systemImage: "folder.badge.plus") { showAddToCollection = true }
            batchButton(L10n.t(.exportTable), systemImage: "square.and.arrow.up") { batchExportTable() }
        }
    }

    private func batchButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: Theme.fsSmall, weight: .medium))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, Theme.sp3)
                .padding(.vertical, Theme.sp1 + 2)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                        .strokeBorder(Theme.lineStrong, lineWidth: 0.5)
                )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var allItems: [ResultItem] { searchResult?.items ?? [] }
    /// P2-9：全选/取消全选判据——与 toggleSelectAll 引用同一个集合，避免标签与动作相反
    private var isAllSelected: Bool { !allItems.isEmpty && selectedIds.count == allItems.count }

    private var currentItems: [ResultItem] {
        (searchResult?.items ?? []).filter { selectedIds.contains($0.id) }
    }

    // MARK: - 结果内筛选（前端过滤已加载结果）

    private var favoritedIds: Set<String> {
        Set(favorites.favorites.filter { $0.toolId == provider.id }.map { $0.itemId })
    }

    private var inResultFilterActive: Bool {
        !inResultFilter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var displayItems: [ResultItem] {
        guard inResultFilterActive else { return searchResult?.items ?? [] }
        let q = inResultFilter.lowercased()
        return (searchResult?.items ?? []).filter {
            $0.title.lowercased().contains(q) ||
            ($0.subtitle?.lowercased().contains(q) ?? false) ||
            ($0.meta?.lowercased().contains(q) ?? false) ||
            ($0.badge?.lowercased().contains(q) ?? false)
        }
    }

    private var inResultFilterBar: some View {
        VStack(spacing: Theme.sp1 + 2) {
            HStack(spacing: Theme.sp2) {
                Image(systemName: "line.horizontal.3.decrease.circle")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.ink3)
                // B5/P2-14：明确「本地过滤」语义，避免与顶部「检索范围」混淆
                TextField(L10n.t(.localFilter, searchResult?.items.count ?? 0), text: $inResultFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.fsSmall))
                if inResultFilterActive {
                    Button(action: { inResultFilter = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.ink2)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(L10n.t(.clearLocalFilterA11y))
                }
            }
            // B6：过滤激活时明确提示「加载更多已暂停」，并提供一键恢复
            if inResultFilterActive {
                HStack(spacing: Theme.sp2) {
                    Text(L10n.t(.filterHint, searchResult?.items.count ?? 0))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Spacer()
                    Button(action: { inResultFilter = "" }) {
                        Text(L10n.t(.clearAndRestore))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp2)
    }

    private func toggleSelectAll() {
        if isAllSelected {
            selectedIds = []
        } else {
            selectedIds = Set(allItems.map { $0.id })
        }
    }

    private func batchCopyAccessions() {
        let lines = currentItems.map { $0.badge ?? $0.id }
        guard !lines.isEmpty else { return }
        Clipboard.copy(lines.joined(separator: "\n"), tip: L10n.t(.copied))
    }

    private func batchFavorite() {
        let items = currentItems
        guard !items.isEmpty else { return }
        for item in items {
            favorites.add(toolId: provider.id, toolName: provider.name,
                          itemId: item.id, title: item.title, subtitle: item.subtitle)
        }
        // P3-10 / P1-8：批量收藏提示「已收藏 N 条」而非「已复制」
        Clipboard.showToast(L10n.t(.batchFavorited, items.count))
    }

    private func batchExportTable() {
        let items = currentItems
        guard !items.isEmpty else { return }
        let rows = items.map { [$0.badge ?? $0.id, $0.title, $0.subtitle ?? "", $0.meta ?? ""] }
        // P1-7：CSV 表头与列内容一一对应（编号/标题/副标题/其他信息）
        let csv = ExportUtil.buildCSV(header: [L10n.t(.csvAccession), L10n.t(.csvTitle), L10n.t(.csvSubtitle), L10n.t(.csvMeta)], rows: rows)
        let ok = ExportUtil.saveTextFile(csv, defaultName: "SciToolbox_\(provider.name)", ext: "csv")
        if ok { Clipboard.showToast(L10n.t(.exported, "\(items.count)")) }
    }

    private func batchCandidates() -> [CollectionCandidate] {
        currentItems.map {
            CollectionCandidate(
                toolId: provider.id, toolName: provider.name,
                itemId: $0.id, title: $0.title, subtitle: $0.subtitle,
                context: $0.extra
            )
        }
    }

    // MARK: - D12 单行加入集合

    /// 从结果行 hover 的「📁」入口，把单条加入集合。
    private func presentSingleAddToCollection(_ item: ResultItem) {
        singleCandidate = CollectionCandidate(
            toolId: provider.id, toolName: provider.name,
            itemId: item.id, title: item.title, subtitle: item.subtitle,
            context: item.extra
        )
        showAddToCollection = true
    }

    /// sheet 候选：单行加入时用单候选，否则用批量候选。
    private func sheetCandidates() -> [CollectionCandidate] {
        if let single = singleCandidate {
            singleCandidate = nil
            return [single]
        }
        return batchCandidates()
    }

    // MARK: - P2-9 方向键导航

    private func moveSelection(offset: Int) {
        let items = displayItems
        guard !items.isEmpty else { return }
        let currentIdx = items.firstIndex { $0.id == selectedItemId } ?? -1
        let newIdx = min(max(currentIdx + offset, 0), items.count - 1)
        let item = items[newIdx]
        selectedItemId = item.id
        onItemTapped?(item)
    }

    // MARK: - Actions

    /// P2-12：GTDB 空查询直接调用 provider.search（绕过空查询拦截），进入域级浏览。
    private func preseedGTDBSearch() {
        viewState = .loading
        error = nil
        lastQuery = ""
        searchTask = Task {
            do {
                let result = try await provider.search(query: "", offset: 0, pickerId: nil)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResult = result
                    viewState = .results
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.viewState = .error
                }
            }
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            // B7：空查询静默无反馈 → 明确提示
            Clipboard.showToast(L10n.t(.emptyQuery))
            return
        }

        // Offline guard: show friendly message instead of cryptic network error
        if !NetworkMonitor.shared.isOnline {
            error = L10n.t(.offline)
            viewState = .error
            return
        }

        // Cancel any in-flight search to prevent stale results
        searchTask?.cancel()

        viewState = .loading
        error = nil
        loadMoreError = nil
        lastQuery = q
        currentOffset = 0
        selectedItemId = nil
        selectedIds = []
        inResultFilter = ""

        let shouldAutoOpen = autoOpenDetail
        autoOpenDetail = false

        searchTask = Task {
            do {
                let result = try await provider.search(query: q, offset: 0, pickerId: selectedPickerId.isEmpty ? nil : selectedPickerId)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResult = result
                    viewState = .results
                    // Record to history
                    history.add(toolId: provider.id, toolName: provider.name, query: q)
                    // C9：跨库互链跳转后自动带出首条详情
                    if shouldAutoOpen, let first = result.items.first {
                        onItemTapped?(first)
                    }
                }
            } catch is CancellationError {
                // Silently ignore — a newer search supersedes this one
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription
                    self.viewState = .error
                }
            }
        }
    }

    private func loadMore() {
        guard !isLoadingMore, let r = searchResult, r.hasMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        // P1-9：已加载条数即为下一页起点（items 是累计追加，不能再叠加 currentOffset）
        let nextOffset = r.items.count
        Task {
            do {
                let more = try await provider.search(query: lastQuery, offset: nextOffset, pickerId: selectedPickerId.isEmpty ? nil : selectedPickerId)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResult?.items.append(contentsOf: more.items)
                    searchResult?.hasMore = more.hasMore
                    currentOffset = nextOffset
                    isLoadingMore = false
                }
            } catch is CancellationError {
                await MainActor.run { isLoadingMore = false }
            } catch {
                await MainActor.run {
                    isLoadingMore = false
                    loadMoreError = error.localizedDescription
                }
            }
        }
    }
}
