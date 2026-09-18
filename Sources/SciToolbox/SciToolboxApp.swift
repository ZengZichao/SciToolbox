import SwiftUI
import AppKit

// MARK: - SciToolbox App Entry (minimal)

@main
struct SciToolboxApp: App {
    @StateObject private var registry = ToolRegistry.shared
    @StateObject private var toast = AppToast.shared
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var appLanguage = AppLanguage.shared
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(registry)
                .overlay(alignment: .bottom) {
                    if toast.isVisible {
                        ToastView(
                            message: toast.message ?? "",
                            onUndo: toast.undoAction.map { undo in { undo() } }
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .top) {
                    if !network.isOnline {
                        OfflineBanner()
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .onChange(of: appearance) { _, newValue in
                    Appearance.apply(newValue)
                }
                .onAppear {
                    Appearance.apply(appearance)
                    ThinScrollbar.apply()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // ⌘, 打开设置窗口（确保在所有 macOS 版本上可用）
            CommandGroup(replacing: .appSettings) {
                Button(L10n.t(.cmdSettings)) {
                    if NSApp.responds(to: Selector(("showSettingsWindow:"))) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else if NSApp.responds(to: Selector(("showPreferencesWindow:"))) {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    } else {
                        NotificationCenter.default.post(name: .navigateToTool, object: nil, userInfo: ["toolId": "settings"])
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu(L10n.t(.toolMenu)) {
                ForEach(registry.providers, id: \.id) { provider in
                    Button(provider.name) {
                        NotificationCenter.default.post(
                            name: .navigateToTool,
                            object: nil,
                            userInfo: ["toolId": provider.id]
                        )
                    }
                }
            }
            // ⌘K Command Palette
            CommandGroup(after: .toolbar) {
                Button(L10n.t(.cmdPalette)) {
                    NotificationCenter.default.post(name: .showCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            // P1-6：⌘F 聚焦当前搜索框（或首页智能识别框）
            CommandGroup(after: .textEditing) {
                Button(L10n.t(.cmdFocusSearch)) {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            // P0-2：⌘[ / ⌘] 在详情浏览历史间上一条 / 下一条
            CommandGroup(after: .textEditing) {
                Button(L10n.t(.cmdDetailPrev)) {
                    NotificationCenter.default.post(name: .detailPrevious, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)
                Button(L10n.t(.cmdDetailNext)) {
                    NotificationCenter.default.post(name: .detailNext, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }
            // P2-11：⌘\ 切换侧边栏显示
            CommandGroup(after: .sidebar) {
                Button(L10n.t(.cmdToggleSidebar)) {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
            // P2-17：快捷键速查
            CommandMenu(L10n.t(.helpMenu)) {
                Button(L10n.t(.cmdShortcuts)) {
                    NotificationCenter.default.post(name: .showShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Toast View (quiet pill + optional undo button)

struct ToastView: View {
    let message: String
    var onUndo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.sp3) {
            Text(message)
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.ink2)
            if let onUndo {
                Button(action: {
                    AppToast.shared.performUndo()
                    onUndo()
                }) {
                Text(L10n.t(.undo))
                    .font(.system(size: Theme.fsSmall, weight: .medium))
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.undoAction))
            }
        }
        .padding(.horizontal, Theme.sp3)
        .padding(.vertical, Theme.sp2)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .strokeBorder(Theme.lineStrong, lineWidth: 0.5)
        )
        .padding(.bottom, Theme.sp6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(onUndo != nil ? String(format: L10n.t(.toastWithUndo), message) : message)
    }
}

// MARK: - Offline Banner (network connectivity warning)

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: Theme.sp2) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12))
            Text(L10n.t(.offlineBanner))
                .font(.system(size: Theme.fsSmall))
        }
        .foregroundColor(.white)
        .padding(.horizontal, Theme.sp4)
        .padding(.vertical, Theme.sp2)
        .frame(maxWidth: .infinity)
        .background(Theme.warningBanner)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t(.offlineBanner))
    }
}

// MARK: - ContentView (Three-Column Navigation)

struct ContentView: View {
    @EnvironmentObject var registry: ToolRegistry
    @State private var selectedToolId: String? = "home"
    @State private var prefillQuery: String?
    @State private var detailModel: DetailModel?
    @State private var detailLoading = false
    @State private var detailError: String?
    @State private var detailItemId: String? = nil
    @State private var detailToolId: String? = nil
    /// 当前详情的来源上下文（如 Europe PMC 的 source/id），加入集合时一并保存以便后续重新拉取。
    @State private var detailContext: [String: String]? = nil
    @AppStorage("sidebarDensity") private var sidebarDensity: String = "normal"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Navigation history for breadcrumb / back（跨库 / 跨工具跳转来路，A4）
    struct NavEntry: Identifiable {
        let id = UUID()
        let toolId: String
        let query: String?
        let toolName: String
    }
    @State private var navHistory: [NavEntry] = []
    /// 各工具最近一次查询词（供「返回上一工具」恢复检索上下文，A4）。
    @State private var toolQueries: [String: String] = [:]

    // P0-2：详情浏览历史栈（与跨库 navHistory 解耦），支持上一条 / 下一条回溯
    struct DetailVisit: Identifiable {
        let id = UUID()
        let toolId: String
        let itemId: String
        let query: String?
        /// P2-5：保存 context（如 EuropePMC 的 source/id、UniProt 的 accession），回溯时才能取到正确条目
        let context: [String: String]?
    }
    @State private var detailHistory: [DetailVisit] = []
    @State private var detailCursor: Int = -1

    // Command palette
    @State private var showCommandPalette = false

    // Favorites
    @StateObject private var favorites = LocalFavorites.shared

    // History
    @StateObject private var history = SearchHistory.shared

    // Collections（项目集合 / 课题）
    @StateObject private var collections = CollectionStore.shared

    // 观察界面语言：切换语言时触发 ContentView 重建渲染，主窗口文本即时切换
    @StateObject private var appLanguage = AppLanguage.shared

    // 智能识别路由弹窗
    @State private var showRouteSheet = false
    @State private var routeMatches: [AccessionRouter.Match] = []

    // 详情页「加入集合」弹窗
    @State private var showAddToCollection = false
    @State private var collectionCandidates: [CollectionCandidate] = []

    // P1-4：全库搜索
    @State private var globalQuery: String? = nil

    // P1-8：收藏备注编辑弹窗
    @State private var showNoteEditor = false
    @State private var noteEditorText = ""
    @State private var noteEditorTargetId: String? = nil   // FavoriteItem.id

    // P2-17：快捷键速查弹窗
    @State private var showShortcuts = false

    // P2-11：侧边栏可见性（⌘\ 切换）
    @AppStorage("sidebarVisible") private var sidebarVisible = true

    // A1：侧边栏分组折叠状态（会话内记忆）
    @State private var collapsedSections: Set<String> = []

    // C10：跨库并排对比容器与对比视图开关
    @ObservedObject private var comparison = ComparisonStore.shared
    @State private var compareMode = false

    private var density: SidebarDensity {
        SidebarDensity(rawValue: sidebarDensity) ?? .normal
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            // Column 1: Sidebar (custom: ScrollView + LazyVStack for full visual control)
            VStack(spacing: 0) {
                // Branding header
                brandingHeader

                // Scrollable sidebar list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // ── 首页（顶级，无分组）──
                        SidebarItemView(
                            icon: "house",
                            text: L10n.t(.home),
                            color: Theme.accent,
                            isSelected: selectedToolId == "home",
                            density: density
                        ) {
                            selectTool("home")
                        }

                        // ── 分类工具组（A1：分组标题可折叠）──
                        ForEach(registry.grouped(), id: \.category) { group in
                            let key = "cat-\(group.category.rawValue)"
                            SidebarSectionHeader(
                                title: group.category.name,
                                color: Theme.categoryColor(group.category),
                                density: density,
                                badge: group.category.abbreviation,
                                isCollapsed: collapsedSections.contains(key),
                                onToggle: { toggleSection(key) }
                            )

                            if !collapsedSections.contains(key) {
                                ForEach(group.items, id: \.id) { tool in
                                    SidebarItemView(
                                        icon: tool.iconName,
                                        text: tool.name,
                                        color: Theme.categoryColor(group.category),
                                        isSelected: selectedToolId == tool.id,
                                        density: density,
                                        isIndented: true
                                    ) {
                                        selectTool(tool.id)
                                    }
                                }
                            }
                        }

                        // ── 收藏与历史（A1：可折叠）──
                        let favKey = "fav"
                        SidebarSectionHeader(
                            title: L10n.t(.favoritesAndHistory),
                            color: Theme.accent,
                            density: density,
                            isCollapsed: collapsedSections.contains(favKey),
                            onToggle: { toggleSection(favKey) }
                        )
                        if !collapsedSections.contains(favKey) {
                            SidebarItemView(
                                icon: "star",
                                text: L10n.t(.favorites),
                                color: Theme.accent,
                                isSelected: selectedToolId == "favorites",
                                density: density,
                                isIndented: true
                            ) {
                                selectTool("favorites")
                            }
                            SidebarItemView(
                                icon: "clock.arrow.circlepath",
                                text: L10n.t(.history),
                                color: Theme.accent,
                                isSelected: selectedToolId == "history",
                                density: density,
                                isIndented: true
                            ) {
                                selectTool("history")
                            }
                            SidebarItemView(
                                icon: "folder",
                                text: L10n.t(.collections),
                                color: Theme.accent,
                                isSelected: selectedToolId == "collections",
                                density: density,
                                isIndented: true
                            ) {
                                selectTool("collections")
                            }
                        }

                        // ── 其他（A1：可折叠）──
                        let miscKey = "misc"
                        SidebarSectionHeader(
                            title: L10n.t(.others),
                            color: Theme.ink3,
                            density: density,
                            isCollapsed: collapsedSections.contains(miscKey),
                            onToggle: { toggleSection(miscKey) }
                        )
                        if !collapsedSections.contains(miscKey) {
                            // A2/A3：侧边栏「设置」点击直接打开系统设置窗口，消除双入口形态不一致
                            SidebarItemView(
                                icon: "gearshape",
                                text: L10n.t(.settings),
                                color: Theme.ink3,
                                isSelected: false,
                                density: density,
                                isIndented: true
                            ) {
                                openSystemSettings()
                            }
                        }

                        // Bottom spacer
                        Color.clear.frame(height: Theme.sp4)
                    }
                }
            }
            .background(Theme.sidebarBackground)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            // Column 2: Content (search + results, or home, or settings)
            contentColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
        } detail: {
            // Column 3: Detail
            detailColumn
                .navigationSplitViewColumnWidth(min: 350, ideal: 500, max: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        // Command palette: overlay (no sheet animation — keyboard-initiated, high-frequency)
        .overlay {
            if showCommandPalette {
                ZStack {
                    // Dimming scrim
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    CommandPaletteView(isPresented: $showCommandPalette) { id, query in
                        selectTool(id)
                        // P1-6：⌘K 带查询语法（工具:查询）→ 命中 prefill 通道
                        if let q = query, !q.isEmpty {
                            prefillQuery = q
                            Task { @MainActor in
                                NotificationCenter.default.post(
                                    name: .prefillQuery,
                                    object: nil,
                                    userInfo: ["query": q]
                                )
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showCommandPalette)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTool)) { note in
            if let toolId = note.userInfo?["toolId"] as? String {
                let query = note.userInfo?["query"] as? String
                let autoDetail = (note.userInfo?["autoDetail"] as? Bool) ?? false

                // Same-tool drill: 保留旧详情（P0-3 骨架过渡精神），仅重新检索并预填查询
                if toolId == selectedToolId, let q = query, !q.isEmpty {
                    detailError = nil
                    detailContext = nil
                    prefillQuery = q
                    Task { @MainActor in
                        NotificationCenter.default.post(
                            name: .prefillQuery,
                            object: nil,
                            userInfo: ["query": q, "autoOpenDetail": autoDetail]
                        )
                    }
                } else {
                    // Cross-tool navigation: save to history for back navigation（A4）
                    if let currentToolId = selectedToolId, currentToolId != toolId {
                        navHistory.append(NavEntry(
                            toolId: currentToolId,
                            query: toolQueries[currentToolId],
                            toolName: toolDisplayName(currentToolId)
                        ))
                        if navHistory.count > 10 { navHistory.removeFirst(navHistory.count - 10) }
                    }
                    selectedToolId = toolId
                    detailContext = nil
                    if let q = query, !q.isEmpty {
                        prefillQuery = q
                        Task { @MainActor in
                            NotificationCenter.default.post(
                                name: .prefillQuery,
                                object: nil,
                                userInfo: ["query": q, "autoOpenDetail": autoDetail]
                            )
                        }
                    }
                }
            }
        }
        // P1-5：XLink 软跳转（⌘点击）——仅预览详情，不改动中间栏
        .onReceive(NotificationCenter.default.publisher(for: .previewDetail)) { note in
            if let toolId = note.userInfo?["toolId"] as? String,
               let query = note.userInfo?["query"] as? String,
               let provider = registry.find(id: toolId) {
                fetchDetail(itemId: query, provider: provider, extra: nil, recordHistory: true)
            }
        }
        .onChange(of: selectedToolId) { _, _ in
            detailModel = nil
            detailError = nil
            detailLoading = false
            detailItemId = nil
            detailToolId = nil
            detailContext = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartRoute)) { note in
            if let input = note.userInfo?["input"] as? String {
                routeAccession(input)
            }
        }
        // P0-2：详情历史 ⌘[ / ⌘] 回溯
        .onReceive(NotificationCenter.default.publisher(for: .detailPrevious)) { _ in
            goDetailPrevious()
        }
        .onReceive(NotificationCenter.default.publisher(for: .detailNext)) { _ in
            goDetailNext()
        }
        // P2-11：⌘\ 切换侧边栏
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            sidebarVisible.toggle()
        }
        // P2-17：快捷键速查
        .onReceive(NotificationCenter.default.publisher(for: .showShortcuts)) { _ in
            showShortcuts = true
        }
        // P1-4：全库搜索
        .onReceive(NotificationCenter.default.publisher(for: .openGlobalSearch)) { note in
            if let q = note.userInfo?["query"] as? String, !q.isEmpty {
                globalQuery = q
                selectedToolId = "global"
            }
        }
        .sheet(isPresented: $showRouteSheet) {
            AccessionCandidateSheet(matches: routeMatches) { match in
                showRouteSheet = false
                NotificationCenter.default.post(
                    name: .navigateToTool,
                    object: nil,
                    userInfo: ["toolId": match.toolId, "query": match.query]
                )
            }
        }
        .sheet(isPresented: $showAddToCollection) {
            AddToCollectionSheet(candidates: collectionCandidates) {
                showAddToCollection = false
            }
        }
        .sheet(isPresented: $showShortcuts) {
            ShortcutReferenceSheet()
        }
        // P1-8：收藏备注编辑
        .alert(L10n.t(.editNote), isPresented: $showNoteEditor) {
            TextField(L10n.t(.notePlaceholder), text: $noteEditorText)
            Button(L10n.t(.cancelBtn), role: .cancel) {}
            Button(L10n.t(.save)) {
                if let id = noteEditorTargetId {
                    favorites.updateNote(id: id, note: noteEditorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteEditorText.trimmingCharacters(in: .whitespacesAndNewlines))
                    Clipboard.showToast(L10n.t(.noteUpdated))
                }
                noteEditorTargetId = nil
            }
        } message: {
            Text(L10n.t(.notePlaceholder))
        }
    }

    // MARK: - Accession 智能识别路由

    private func routeAccession(_ input: String) {
        let matches = AccessionRouter.classify(input)
        guard !matches.isEmpty else {
            Clipboard.showToast(L10n.t(.smartRouteFailed))
            return
        }
        switch AccessionRouter.decide(matches) {
        case .route(let m):
            NotificationCenter.default.post(
                name: .navigateToTool,
                object: nil,
                userInfo: ["toolId": m.toolId, "query": m.query]
            )
        case .choose(let ms):
            routeMatches = ms
            showRouteSheet = true
        }
    }

    private func addCurrentToCollection() {
        guard let itemId = detailItemId,
              let toolId = detailToolId,
              let model = detailModel,
              let tool = registry.find(id: toolId) else { return }
        collectionCandidates = [CollectionCandidate(
            toolId: toolId, toolName: tool.name,
            itemId: itemId, title: model.headerTitle, subtitle: model.headerSubtitle,
            context: detailContext
        )]
        showAddToCollection = true
    }

    // MARK: - C10：跨库对比

    /// 将当前详情加入对比（已抓取详情可直接填充，无需二次请求）。
    private func addCurrentToCompare() {
        guard let itemId = detailItemId,
              let toolId = detailToolId,
              let model = detailModel,
              let tool = registry.find(id: toolId) else { return }
        comparison.add(toolId: toolId, toolName: tool.name, category: tool.category,
                       itemId: itemId, query: detailContext?["query"], context: detailContext,
                       detail: model)
    }

    /// 从对比表点击某条目：退出对比模式并在详情栏单独打开它。
    private func openSingleDetail(_ item: ComparisonItem) {
        guard let p = registry.find(id: item.toolId) else { return }
        detailToolId = item.toolId
        detailItemId = item.itemId
        detailContext = item.context
        compareMode = false
        fetchDetail(itemId: item.itemId, provider: p, extra: item.context, recordHistory: true)
    }

    // MARK: - Tool selection helper

    /// A4：侧边栏切换也进入导航栈（支持「返回上一工具」恢复上下文）；
    /// 折返到栈顶工具时直接回退，避免历史无限增长。
    private func selectTool(_ id: String) {
        guard id != selectedToolId else { return }
        if let last = navHistory.last, last.toolId == id {
            // 折返：撤销上一次跳转，恢复该工具上次查询
            navHistory.removeLast()
            selectedToolId = id
            if let q = last.query, !q.isEmpty {
                prefillQuery = q
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .prefillQuery,
                        object: nil,
                        userInfo: ["query": q]
                    )
                }
            }
        } else {
            if let currentToolId = selectedToolId {
                navHistory.append(NavEntry(
                    toolId: currentToolId,
                    query: toolQueries[currentToolId],
                    toolName: toolDisplayName(currentToolId)
                ))
                if navHistory.count > 10 { navHistory.removeFirst(navHistory.count - 10) }
            }
            selectedToolId = id
        }
    }

    private func toggleSection(_ key: String) {
        if collapsedSections.contains(key) {
            collapsedSections.remove(key)
        } else {
            collapsedSections.insert(key)
        }
    }

    /// 工具显示名（含首页 / 收藏 / 历史 / 集合等非 Provider 页签）。
    private func toolDisplayName(_ id: String) -> String {
        if let tool = registry.find(id: id) { return tool.name }
        switch id {
        case "home": return L10n.t(.home)
        case "favorites": return L10n.t(.favorites)
        case "history": return L10n.t(.history)
        case "collections": return L10n.t(.collections)
        case "settings": return L10n.t(.settings)
        case "global": return L10n.t(.globalSearch)
        default: return id
        }
    }

    /// P2-11：侧边栏可见性绑定（⌘\ 切换，跨会话记忆）。
    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = ($0 == .all) }
        )
    }

    /// A2/A3：打开设置窗口。
    /// 使用 SwiftUI Settings scene 的标准方式：通过发送 showSettingsWindow: selector 打开。
    /// 在 macOS 14+ 使用 showSettingsWindow:，旧版回退 showPreferencesWindow:。
    private func openSystemSettings() {
        // macOS 14+ (Sonoma) 使用 showSettingsWindow:
        if NSApp.responds(to: Selector(("showSettingsWindow:"))) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else if NSApp.responds(to: Selector(("showPreferencesWindow:"))) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        } else {
            // 最终回退：直接在中间栏显示 SettingsView
            selectedToolId = "settings"
        }
    }

    // MARK: - P0-2 详情浏览历史回溯

    private func goDetailPrevious() {
        guard detailCursor > 0, detailCursor < detailHistory.count else { return }
        detailCursor -= 1
        let visit = detailHistory[detailCursor]
        guard let provider = registry.find(id: visit.toolId) else { return }
        fetchDetail(itemId: visit.itemId, provider: provider, extra: visit.context, recordHistory: false)   // P2-5：带回 context
    }

    private func goDetailNext() {
        guard detailCursor >= 0, detailCursor + 1 < detailHistory.count else { return }
        detailCursor += 1
        let visit = detailHistory[detailCursor]
        guard let provider = registry.find(id: visit.toolId) else { return }
        fetchDetail(itemId: visit.itemId, provider: provider, extra: visit.context, recordHistory: false)   // P2-5：带回 context
    }

    private var canGoDetailPrevious: Bool { detailCursor > 0 }
    private var canGoDetailNext: Bool { detailCursor >= 0 && detailCursor + 1 < detailHistory.count }

    /// P1-8：详情页「编辑笔记」入口 → 弹出备注编辑。
    private func editDetailNote() {
        guard let itemId = detailItemId,
              let toolId = detailToolId,
              let fav = favorites.favorite(toolId: toolId, itemId: itemId) else { return }
        noteEditorTargetId = fav.id
        noteEditorText = fav.note ?? ""
        showNoteEditor = true
    }

    // MARK: - Branding header

    private var brandingHeader: some View {
        HStack(spacing: Theme.sp2 + 2) {
            // App icon / logo mark — 使用实际 App 图标
            AppLogoView(size: 22)

            Text("SciToolbox")
                .font(.system(size: Theme.fsBody, weight: .semibold))
                .foregroundColor(Theme.ink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, density.sidebarPadding + 2)
        .padding(.top, Theme.sp4)
        .padding(.bottom, Theme.sp3)
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        if let toolId = selectedToolId {
            if toolId == "home" {
                HomeView(onToolSelected: { id in
                    selectTool(id)
                })
                .id("home")
            } else if toolId == "settings" {
                SettingsView()
                    .id("settings")
            } else if toolId == "favorites" {
                FavoritesView()
                    .id("favorites")
            } else if toolId == "history" {
                HistoryView(onToolSelected: { id in
                    selectTool(id)
                })
                .id("history")
            } else if toolId == "collections" {
                CollectionsView(onToolSelected: { id in
                    selectTool(id)
                })
                .id("collections")
            } else if toolId == "global" {
                // P1-4：全库搜索
                GlobalSearchScreen(
                    query: globalQuery ?? "",
                    onItemTapped: { item, provider in
                        fetchDetail(itemId: item.id, provider: provider, extra: item.extra, recordHistory: true)
                    }
                )
                .id("global-\(globalQuery ?? "")")
            } else if let provider = registry.find(id: toolId) {
                SearchScreen(
                    provider: provider,
                    onItemTapped: { item in
                        fetchDetail(itemId: item.id, provider: provider, extra: item.extra, recordHistory: true)
                    },
                    onQueryChanged: { q in
                        toolQueries[provider.id] = q
                    }
                )
                .id(toolId)
                .onAppear {
                    if let q = prefillQuery, !q.isEmpty {
                        Task { @MainActor in
                            NotificationCenter.default.post(
                                name: .prefillQuery,
                                object: nil,
                                userInfo: ["query": q]
                            )
                        }
                        prefillQuery = nil
                    }
                }
            } else {
                Text(L10n.t(.toolNotFound))
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.ink3)
            }
        } else {
            HomeView(onToolSelected: { id in
                selectTool(id)
            })
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        Group {
            // C10：对比工具栏（含条目时始终显示，提供「查看对比 / 退出」「清空」）
            if !comparison.items.isEmpty {
                compareToolbar
                softDivider()
            }

            if let err = detailError {
                // F17：错误态带重试
                StateView(state: .error(message: err, retry: {
                    if let toolId = detailToolId,
                       let p = registry.find(id: toolId),
                       let itemId = detailItemId {
                        fetchDetail(itemId: itemId, provider: p, extra: detailContext, recordHistory: false)
                    }
                }))
                .transition(.opacity)
            } else if let model = detailModel {
                // C10：开启对比模式时，用并排对比表替换单条详情
                if compareMode, !comparison.items.isEmpty {
                    ComparisonView(onOpenItem: { item in openSingleDetail(item) })
                        .transition(.opacity)
                } else {
                // 详情内容（P0-3：加载新详情时保留旧内容，叠加半透明 spinner 遮罩做骨架过渡）
                VStack(spacing: 0) {
                    // P0-2/A4：面包屑常驻（只要有跨库来路或详情历史即显示）
                    if !navHistory.isEmpty || !detailHistory.isEmpty {
                        detailBreadcrumbBar
                        softDivider()
                    }
                    ZStack {
                        KeyValueDetail(
                            model: model,
                            accentColor: detailAccentColor,
                            isFavorited: isCurrentDetailFavorited,
                            onToggleFavorite: toggleCurrentFavorite,
                            onAddToCollection: addCurrentToCollection,
                            onEditNote: editDetailNote,
                            onAddToCompare: { addCurrentToCompare() },
                            onCopy: { Clipboard.copy($0, tip: L10n.t(.copied)) },
                            onAction: { action in
                                if action.kind == .export {
                                    let base = action.exportFileName ?? "citation"
                                    let ext = action.exportExt ?? "txt"
                                    let ok = ExportUtil.saveTextFile(action.payload, defaultName: base, ext: ext)
                                    if ok { Clipboard.showToast(L10n.t(.exported, "\(base).\(ext)")) }
                                } else {
                                    Clipboard.copy(action.payload, tip: action.label)
                                }
                            },
                            onXLink: { link in
                                // 硬跳转：切换中栏并自动带出详情（C9）
                                NotificationCenter.default.post(
                                    name: .navigateToTool,
                                    object: nil,
                                    userInfo: ["toolId": link.toolId, "query": link.query, "autoDetail": true]
                                )
                            },
                            onPreviewXLink: { link in
                                // P1-5：⌘点击 → 软跳转，仅预览详情不改中间栏
                                NotificationCenter.default.post(
                                    name: .previewDetail,
                                    object: nil,
                                    userInfo: ["toolId": link.toolId, "query": link.query]
                                )
                            }
                        )
                        if detailLoading {
                            loadingOverlay
                        }
                    }
                }
                .transition(.opacity)
                }
            } else if detailLoading {
                StateView(state: .loading(text: L10n.t(.loadingDetail)))
                    .transition(.opacity)
            } else {
                // Empty state — guidance card
                detailEmptyState
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: detailLoading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: detailModel != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: detailError)
    }

    /// P0-3：旧详情之上的半透明加载遮罩（而非切到空 loading 态）。
    private var loadingOverlay: some View {
        ZStack {
            Theme.cardBackground.opacity(0.35)
            ProgressView()
                .controlSize(.small)
        }
        .transition(reduceMotion ? .identity : .opacity)
        .accessibilityLabel(L10n.t(.loadingDetail))
    }

    /// C10：对比工具栏——含对比条目时显示在详情栏顶部。
    private var compareToolbar: some View {
        HStack(spacing: Theme.sp2) {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 11))
                .foregroundColor(Theme.ink3)
            Text(L10n.t(.compare))
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.ink3)
            Text("\(comparison.items.count)")
                .font(.system(size: Theme.fsCaption, weight: .semibold))
                .foregroundColor(Theme.accent)
            Spacer(minLength: 0)
            Button(action: { compareMode.toggle() }) {
                Text(compareMode ? L10n.t(.exitCompare) : L10n.t(.viewCompare))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(compareMode ? L10n.t(.exitCompare) : L10n.t(.viewCompare))
            Button(action: { comparison.clear(); compareMode = false }) {
                Text(L10n.t(.clearCompare))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.clearCompare))
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp2)
    }

    @ViewBuilder
    private var detailBreadcrumbBar: some View {
        HStack(spacing: Theme.sp2) {
            if !navHistory.isEmpty {
                Button(action: goBack) {
                    HStack(spacing: Theme.sp1) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                        Text(L10n.t(.back))
                            .font(.system(size: Theme.fsSmall))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(PressableButtonStyle())
                .help(L10n.t(.backToPrevTool))
                .accessibilityLabel(L10n.t(.backToPrevTool))

                softDivider()
                    .frame(height: 12)
            }

            // Breadcrumb path
            HStack(spacing: Theme.sp1) {
                ForEach(navHistory.suffix(3)) { entry in
                    Text(entry.toolName)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.ink3)
                }
                if let toolId = detailToolId ?? selectedToolId,
                   let tool = registry.find(id: toolId) {
                    Text(tool.name)
                        .font(.system(size: Theme.fsCaption, weight: .medium))
                        .foregroundColor(Theme.ink2)
                } else if let toolId = detailToolId ?? selectedToolId {
                    Text(toolDisplayName(toolId))
                        .font(.system(size: Theme.fsCaption, weight: .medium))
                        .foregroundColor(Theme.ink2)
                }
            }
            .lineLimit(1)

            Spacer()

            // P0-2：详情浏览历史回溯（同库 / 预览条目间游走）
            if !detailHistory.isEmpty {
                Button(action: goDetailPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(canGoDetailPrevious ? Theme.accent : Theme.ink4)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canGoDetailPrevious)
                .help(L10n.t(.prevDetail))
                .accessibilityLabel(L10n.t(.prevDetail))
                Button(action: goDetailNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(canGoDetailNext ? Theme.accent : Theme.ink4)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canGoDetailNext)
                .help(L10n.t(.nextDetail))
                .accessibilityLabel(L10n.t(.nextDetail))
            }
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp2)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var detailEmptyState: some View {
        if let toolId = selectedToolId,
           let provider = registry.find(id: toolId) {
            // Guidance card for the current tool
            VStack(spacing: Theme.sp4) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Theme.ink3)
                    .frame(width: 56, height: 56)
                    .background(Theme.cardBackground)
                    .clipShape(Circle())

                Text(provider.name)
                    .font(.system(size: Theme.fsHeadline, weight: .medium))
                    .foregroundColor(Theme.ink2)

                Text(provider.dataSourceNote)
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)

                Text(provider.placeholder)
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .padding(.horizontal, Theme.sp4)
                    .padding(.vertical, Theme.sp2)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))

                Text(L10n.t(.selectToView))
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .padding(.top, Theme.sp1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Theme.sp3) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(Theme.ink3)
                Text(L10n.t(.selectItem))
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isCurrentDetailFavorited: Bool {
        guard let itemId = detailItemId, let toolId = detailToolId else { return false }
        return favorites.isFavorited(toolId: toolId, itemId: itemId)
    }

    /// Category color for the current detail's tool — used as visual signature in detail header
    private var detailAccentColor: Color {
        if let toolId = detailToolId,
           let provider = registry.find(id: toolId) {
            return Theme.categoryColor(provider.category)
        }
        return Theme.accent
    }

    private func toggleCurrentFavorite() {
        guard let itemId = detailItemId,
              let toolId = detailToolId,
              let model = detailModel,
              let tool = registry.find(id: toolId) else { return }
        favorites.toggle(
            toolId: toolId,
            toolName: tool.name,
            itemId: itemId,
            title: model.headerTitle,
            subtitle: model.headerSubtitle,
            snapshot: Self.favoriteSnapshot(from: model)
        )
    }

    /// 将详情模型的前若干字段压平为 key/value 快照，用于收藏夹离线展示上下文。
    private static func favoriteSnapshot(from model: DetailModel) -> [String: String] {
        var dict: [String: String] = [:]
        for section in model.sections.prefix(4) {
            for row in section.rows.prefix(4) {
                guard dict.count < 10 else { return dict }
                dict[row.key] = row.value
            }
        }
        return dict
    }

    private func goBack() {
        guard let last = navHistory.popLast() else { return }
        selectedToolId = last.toolId
        detailModel = nil
        detailError = nil
        detailLoading = false
        detailItemId = nil
        detailToolId = nil
        detailContext = nil
        // A4：返回时恢复该工具上次的检索上下文
        if let q = last.query, !q.isEmpty {
            prefillQuery = q
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .prefillQuery,
                    object: nil,
                    userInfo: ["query": q]
                )
            }
        }
    }

    // MARK: - Detail fetching (with race-condition guard)

    /// Cancels the previous detail-fetch Task to prevent stale results
    /// from overwriting newer ones when users click rapidly.
    @State private var detailFetchTask: Task<Void, Never>?

    private func fetchDetail(item: ResultItem, provider: any ToolProvider) {
        fetchDetail(itemId: item.id, provider: provider, extra: item.extra, recordHistory: true)
    }

    /// 统一的详情拉取入口。
    /// - recordHistory：是否计入详情浏览历史（P0-2）。回溯导航（上一条/下一条）与失败重试传 false。
    private func fetchDetail(itemId: String, provider: any ToolProvider, extra: [String: String]?, recordHistory: Bool) {
        // Cancel any in-flight detail request (AbortController equivalent)
        detailFetchTask?.cancel()

        // P0-3：保留旧 detailModel，仅切 loading —— 详情列在旧内容上叠加 spinner 遮罩做骨架过渡
        detailLoading = true
        detailError = nil
        detailItemId = itemId
        detailToolId = provider.id
        detailContext = extra

        // P0-2：详情浏览历史入栈（与栈顶相同则不重复；回溯时不动栈）
        if recordHistory {
            if let top = detailHistory.last, top.toolId == provider.id, top.itemId == itemId {
                detailCursor = detailHistory.count - 1
            } else {
                detailHistory.append(DetailVisit(toolId: provider.id, itemId: itemId, query: nil, context: extra))
                if detailHistory.count > 50 {
                    detailHistory.removeFirst(detailHistory.count - 50)
                }
                detailCursor = detailHistory.count - 1
            }
        }

        detailFetchTask = Task {
            do {
                let model = try await provider.detail(id: itemId, context: extra)
                // Guard: ensure this task wasn't cancelled while awaiting
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.detailModel = model
                    self.detailLoading = false
                }
            } catch is CancellationError {
                // Silently ignore — a newer request supersedes this one
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.detailError = error.localizedDescription
                    self.detailLoading = false
                }
            }
        }
    }
}

// MARK: - Sidebar Item View (custom: colored icons, strong selection, hover)

struct SidebarItemView: View {
    let icon: String
    let text: String
    let color: Color
    let isSelected: Bool
    let density: SidebarDensity
    var isIndented: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: density.hSpacing) {
                // Left accent bar (visible when selected)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? color : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 4)

                // Icon with category color
                Image(systemName: icon)
                    .font(.system(size: density.iconSize))
                    .foregroundColor(isSelected ? color : Theme.ink3)
                    .frame(width: density.iconFrame, height: density.iconFrame)

                // Label
                Text(text)
                    .font(.system(size: density.fontSize))
                    .foregroundColor(isSelected ? color : Theme.ink2)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, isIndented ? density.indent : 0)
            .padding(.horizontal, density.sidebarPadding)
            .frame(minHeight: density.minRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .fill(backgroundFill)
            )
            .overlay(
                // Focus ring for keyboard accessibility
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.focusRing, lineWidth: Theme.focusRingWidth)
                    .opacity(isFocused ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .focused($isFocused)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var backgroundFill: Color {
        if isSelected {
            let isDark = colorScheme == .dark
            return color.opacity(isDark ? 0.20 : 0.12)
        }
        if isHovered {
            return Theme.hoverBackground
        }
        return Color.clear
    }
}

// MARK: - Sidebar Section Header (category-colored, collapsible, full-width)

struct SidebarSectionHeader: View {
    let title: String
    let color: Color
    let density: SidebarDensity
    /// H24：单字分类缩写徽标（分/基/蛋/功/文），色觉障碍用户也能区分。
    var badge: String? = nil
    /// A1：分组可折叠。
    var isCollapsed: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.sp2) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            if let badge {
                Text(badge)
                    .font(.system(size: Theme.fsCaption, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 16, height: 16)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.ink3)
                .textCase(.uppercase)
                .tracking(Theme.trackSection)
            Spacer(minLength: 0)
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Theme.ink4)
                }
                .buttonStyle(PressableButtonStyle())
                .help(isCollapsed ? L10n.t(.expandSection) : L10n.t(.collapseSection))
                .accessibilityLabel(isCollapsed ? L10n.t(.expandSection) : L10n.t(.collapseSection))
            }
        }
        .padding(.horizontal, density.sidebarPadding)
        .padding(.top, Theme.sp4)
        .padding(.bottom, Theme.sp1)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle?()
        }
    }
}

extension Notification.Name {
    static let prefillQuery = Notification.Name("prefillQuery")
    static let showCommandPalette = Notification.Name("showCommandPalette")
    static let smartRoute = Notification.Name("smartRoute")
    static let navigateToTool = Notification.Name("navigateToTool")
    /// P1-5：XLink 软跳转（⌘点击，仅预览详情，不改中间栏）。
    static let previewDetail = Notification.Name("previewDetail")
    /// P1-6：⌘F 聚焦当前搜索框（或首页智能识别框）。
    static let focusSearch = Notification.Name("focusSearch")
    /// P0-2：详情历史 ⌘[ / ⌘]。
    static let detailPrevious = Notification.Name("detailPrevious")
    static let detailNext = Notification.Name("detailNext")
    /// P2-11：⌘\ 切换侧边栏。
    static let toggleSidebar = Notification.Name("toggleSidebar")
    /// P2-17：⌘/ 打开快捷键速查。
    static let showShortcuts = Notification.Name("showShortcuts")
    /// P1-4：全库搜索（userInfo["query"]）。
    static let openGlobalSearch = Notification.Name("openGlobalSearch")
}

// MARK: - ShortcutReferenceSheet（快捷键速查，P2-17 / G21 / G22）

struct ShortcutReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct ShortcutRow: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private var rows: [ShortcutRow] {
        [
            ShortcutRow(keys: L10n.t(.shortcutCmdK), action: L10n.t(.shortcutCmdKDesc)),
            ShortcutRow(keys: L10n.t(.shortcutCmdF), action: L10n.t(.shortcutCmdFDesc)),
            ShortcutRow(keys: L10n.t(.shortcutCmdBracket), action: L10n.t(.shortcutCmdBracketDesc)),
            ShortcutRow(keys: L10n.t(.shortcutCmdBackslash), action: L10n.t(.shortcutCmdBackslashDesc)),
            ShortcutRow(keys: L10n.t(.shortcutCmdSlash), action: L10n.t(.shortcutCmdSlashDesc)),
            ShortcutRow(keys: L10n.t(.shortcutCmdComma), action: L10n.t(.shortcutCmdCommaDesc)),
            ShortcutRow(keys: L10n.t(.shortcutEsc), action: L10n.t(.shortcutEscDesc)),
            ShortcutRow(keys: L10n.t(.shortcutArrows), action: L10n.t(.shortcutArrowsDesc)),
            ShortcutRow(keys: L10n.t(.shortcutCmdClick), action: L10n.t(.shortcutCmdClickDesc))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.sp2) {
                Text(L10n.t(.shortcutRefTitle))
                    .font(.system(size: Theme.fsHeadline, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.ink3)
                        .font(.system(size: 16))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.close))
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.vertical, Theme.sp4)

            Divider()

            ScrollView {
                VStack(spacing: Theme.sp2) {
                    ForEach(rows) { row in
                        HStack(spacing: Theme.sp4) {
                            Text(row.keys)
                                .font(.system(size: Theme.fsBody, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.accent)
                                .frame(width: 110, alignment: .leading)
                            Text(row.action)
                                .font(.system(size: Theme.fsSmall))
                                .foregroundColor(Theme.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, Theme.sp4)
                        .padding(.vertical, Theme.sp2)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
                    }
                }
                .padding(Theme.sp4)
            }
        }
        .frame(width: 520, height: 380)
    }
}
