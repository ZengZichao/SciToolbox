import SwiftUI

// MARK: - HomeView (overview: recent queries, favorites, category browse)

/// 概览首页：不再逐条罗列全部工具（避免与侧边栏导航重复），
/// 改为「最近查询 + 收藏 + 分类浏览」的启动台。
/// 点击分类可下钻到该分类的工具列表（按需展开，非默认常驻）。
struct HomeView: View {
    @EnvironmentObject var registry: ToolRegistry
    var onToolSelected: ((String) -> Void)? = nil
    @StateObject private var favorites = LocalFavorites.shared
    @StateObject private var history = SearchHistory.shared
    @State private var activeCategory: ToolCategory? = nil
    /// G22：首启速览卡（可在设置中重看）
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// P2-17：首页快捷键折叠区
    @State private var showShortcuts = false
    /// P1-10：统一使用 SwiftUI reduceMotion 环境值
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sp8) {
            if let cat = activeCategory {
                categoryDetail(cat)
            } else {
            // 品牌标题：放置在搜索框之上，作为首页视觉起点
            headerBlock
            // G22：首启速览卡（可关闭）
            if !hasSeenOnboarding {
                onboardingCard
                    .padding(.top, Theme.sp4)
            }
            AccessionSmartField()
                .padding(.top, Theme.sp4)
            GlobalSearchField()
                .padding(.top, Theme.sp2)
            recentQueriesBlock
                favoritesBlock
                categoriesBlock
                    if history.entries.isEmpty && favorites.favorites.isEmpty {
                        emptyGuidance
                    }
                }
                Spacer(minLength: Theme.sp8)
            }
        }
        .navigationTitle("")
    }

    // MARK: - G22 首启速览卡

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            HStack(spacing: Theme.sp2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                Text(L10n.t(.quickStart))
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .textCase(.uppercase)
                    .tracking(Theme.trackSection)
                Spacer()
                Button(action: { withAnimation(reduceMotion ? nil : .default) { hasSeenOnboarding = true } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .help(L10n.t(.onboardingClose))
                .accessibilityLabel(L10n.t(.onboardingHelp))
            }

            FlowLayout(spacing: Theme.sp2) {
                onboardChip(L10n.t(.smartIdentify), icon: "sparkle.magnifyingglass", desc: L10n.t(.smartIdentifyDesc))
                onboardChip(L10n.t(.globalSearch), icon: "globe.asia.australia", desc: L10n.t(.globalSearchDesc))
                onboardChip(L10n.t(.xlink), icon: "link", desc: L10n.t(.xlinkDesc))
                onboardChip(L10n.t(.cmdK), icon: "keyboard", desc: L10n.t(.cmdKDesc))
                onboardChip(L10n.t(.collectionsFeature), icon: "folder", desc: L10n.t(.collectionsDesc))
            }
        }
        .padding(Theme.sp4)
        .cardStyle()
        .padding(.horizontal, Theme.sp6)
    }

    private func onboardChip(_ title: String, icon: String, desc: String) -> some View {
        HStack(spacing: Theme.sp2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: Theme.fsSmall, weight: .medium))
                    .foregroundColor(Theme.ink)
                Text(desc)
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
            }
        }
        .padding(.horizontal, Theme.sp3)
        .padding(.vertical, Theme.sp2)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: Theme.sp1 + 2) {
            Text(L10n.t(.homeTitle))
                .font(.system(size: Theme.fsDisplay, weight: .bold))
                .foregroundColor(Theme.ink)
                .tracking(Theme.trackLarge)
            Text(L10n.t(.homeSubtitle, ToolRegistry.shared.providers.count))
                .font(.system(size: Theme.fsBody))
                .foregroundColor(Theme.ink3)
        }
        .padding(.horizontal, Theme.sp6)
        .padding(.top, Theme.sp6)
    }

    // MARK: - Recent queries

    @ViewBuilder
    private var recentQueriesBlock: some View {
        if !history.entries.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sp3) {
                sectionHeader(title: L10n.t(.recentQueries), actionTitle: L10n.t(.all), action: { onToolSelected?("history") })
                VStack(spacing: 0) {
                    ForEach(Array(history.entries.prefix(6))) { entry in
                        recentQueryRow(entry)
                        thinDivider()
                    }
                }
                .cardStyle()
                .padding(.horizontal, Theme.sp6)
            }
        }
    }

    private func recentQueryRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: Theme.sp3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundColor(Theme.ink3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.sp1) {
                    Text(entry.toolName)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Text("·")
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Text(entry.relativeTime)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                }
                Text(entry.query)
                    .font(.system(size: Theme.fsBody, design: .monospaced))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: { rerun(entry) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.rerunQueryA11y, entry.query))
        }
        .padding(.horizontal, Theme.sp3)
        .padding(.vertical, Theme.sp2 + 2)
    }

    private func rerun(_ entry: HistoryEntry) {
        NotificationCenter.default.post(
            name: .navigateToTool,
            object: nil,
            userInfo: ["toolId": entry.toolId, "query": entry.query]
        )
    }

    // MARK: - Favorites

    @ViewBuilder
    private var favoritesBlock: some View {
        if !favorites.favorites.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sp3) {
                sectionHeader(title: L10n.t(.favoritesLabel), actionTitle: L10n.t(.all), action: { onToolSelected?("favorites") })
                let recent = Array(favorites.favorites.prefix(6))
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Theme.sp3) {
                    ForEach(recent) { fav in
                        favoritePreviewCard(fav)
                    }
                }
                .padding(.horizontal, Theme.sp6)
            }
        }
    }

    private func favoritePreviewCard(_ fav: FavoriteItem) -> some View {
        Button(action: { onToolSelected?("favorites") }) {
            VStack(alignment: .leading, spacing: Theme.sp1) {
                HStack(spacing: Theme.sp1) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accent.opacity(0.7))
                    Text(fav.toolName)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                        .lineLimit(1)
                }
                Text(fav.title)
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.sp2 + 2)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(L10n.t(.openFavoritesA11y, fav.title))
    }

    // MARK: - Categories

    @ViewBuilder
    private var categoriesBlock: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            sectionHeader(title: L10n.t(.browseCategories), actionTitle: nil, action: nil)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.sp3) {
                ForEach(registry.grouped(), id: \.category) { group in
                    categoryCard(group.category, count: group.items.count)
                }
            }
            .padding(.horizontal, Theme.sp6)
        }
    }

    private func categoryCard(_ cat: ToolCategory, count: Int) -> some View {
        Button(action: { activeCategory = cat }) {
            HStack(spacing: Theme.sp3) {
                // H24：颜色之外叠加单字缩写标签
                Text(cat.abbreviation)
                    .font(.system(size: Theme.fsCaption, weight: .semibold))
                    .foregroundColor(Theme.categoryColor(cat))
                    .frame(width: 18, height: 18)
                    .background(Theme.categoryColor(cat).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.name)
                        .font(.system(size: Theme.fsBody))
                        .foregroundColor(Theme.ink)
                    Text(L10n.t(.toolCount, count))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(Theme.ink4)
            }
            .padding(.horizontal, Theme.sp3)
            .padding(.vertical, Theme.sp3)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(L10n.t(.browseCategoryA11y, cat.name))
    }

    // MARK: - Category detail (drill-down)

    @ViewBuilder
    private func categoryDetail(_ cat: ToolCategory) -> some View {
        VStack(alignment: .leading, spacing: Theme.sp4) {
            Button(action: { activeCategory = nil }) {
                HStack(spacing: Theme.sp1) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .medium))
                    Text(L10n.t(.backToOverview))
                        .font(.system(size: Theme.fsSmall))
                    Spacer()
                    HStack(spacing: Theme.sp1) {
                        Circle()
                            .fill(Theme.categoryColor(cat))
                            .frame(width: 6, height: 6)
                        Text(cat.name)
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink3)
                    }
                }
                .foregroundColor(Theme.accent)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.backToOverview))
            .padding(.horizontal, Theme.sp6)
            .padding(.top, Theme.sp4)

            if let group = registry.grouped().first(where: { $0.category == cat }) {
                VStack(spacing: 0) {
                    ForEach(group.items, id: \.id) { tool in
                        ToolTile(provider: tool) { onToolSelected?(tool.id) }
                        thinDivider()
                    }
                }
                .padding(.horizontal, Theme.sp6)
            }
        }
    }

    // MARK: - Empty guidance (new user)

    @ViewBuilder
    private var emptyGuidance: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            HStack(spacing: Theme.sp2) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.ink3)
                Text(L10n.t(.emptyGuidance))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)
            }
            .padding(.horizontal, Theme.sp6)
            // P2-17：快捷键折叠区（可发现性）
            Button(action: { withAnimation(reduceMotion ? nil : .default) { showShortcuts.toggle() } }) {
                HStack(spacing: Theme.sp2) {
                    Image(systemName: showShortcuts ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.ink4)
                    Text(L10n.t(.keyboardShortcuts))
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.accent)
                }
                .padding(.horizontal, Theme.sp6)
            }
            .buttonStyle(PressableButtonStyle())

            if showShortcuts {
                VStack(alignment: .leading, spacing: Theme.sp1 + 2) {
                    shortcutRow(L10n.t(.shortcutCmdK), L10n.t(.shortcutCmdKDesc))
                    shortcutRow(L10n.t(.shortcutCmdF), L10n.t(.shortcutCmdFDesc))
                    shortcutRow(L10n.t(.shortcutCmdBracket), L10n.t(.shortcutCmdBracketDesc))
                    shortcutRow(L10n.t(.shortcutCmdBackslash), L10n.t(.shortcutCmdBackslashDesc))
                    shortcutRow(L10n.t(.shortcutCmdSlash), L10n.t(.shortcutCmdSlashDesc))
                    shortcutRow(L10n.t(.shortcutCmdClick), L10n.t(.shortcutCmdClickDesc))
                }
                .padding(.horizontal, Theme.sp6)
                .transition(.opacity)
            }
        }
        .padding(.bottom, Theme.sp4)
    }

    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack(spacing: Theme.sp3) {
            Text(keys)
                .font(.system(size: Theme.fsSmall, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.accent)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.ink2)
        }
    }

    // MARK: - Section header

    private func sectionHeader(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: Theme.sp2) {
            Text(title)
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.ink3)
                .textCase(.uppercase)
                .tracking(Theme.trackSection)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: Theme.sp1) {
                        Text(actionTitle)
                            .font(.system(size: Theme.fsSmall))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .light))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("\(actionTitle)，\(title)")
            }
        }
        .padding(.horizontal, Theme.sp6)
    }
}

// MARK: - ToolTile (minimal: icon + text, no card, hover highlight)

struct ToolTile: View {
    let provider: any ToolProvider
    let onTap: () -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.sp3) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.ink2)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name)
                        .font(.system(size: Theme.fsBody))
                        .foregroundColor(Theme.ink)
                    Text(provider.dataSourceNote)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(Theme.ink4)
            }
            .padding(.horizontal, Theme.sp3)
            .padding(.vertical, Theme.sp2 + 2)
            .background(isHovered ? Theme.cardBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
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
        .accessibilityLabel(provider.name)
        .accessibilityHint(L10n.t(.browseCategoryA11y, provider.name))
    }
}
