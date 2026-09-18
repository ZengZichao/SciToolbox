import SwiftUI

// MARK: - SearchBar (minimal: borderless input, subtle accent button)

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onSearch: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// External focus binding — allows parent to auto-focus on appear
    var isFocused: FocusState<Bool>.Binding
    /// 可选的后置按钮（如「识别」智能路由）
    var trailingLabel: String? = nil
    var trailingAction: (() -> Void)? = nil

    init(text: Binding<String>, placeholder: String, isFocused: FocusState<Bool>.Binding,
         trailingLabel: String? = nil, trailingAction: (() -> Void)? = nil,
         onSearch: @escaping () -> Void) {
        self._text = text
        self.placeholder = placeholder
        self.isFocused = isFocused
        self.trailingLabel = trailingLabel
        self.trailingAction = trailingAction
        self.onSearch = onSearch
    }

    var body: some View {
        HStack(spacing: Theme.sp2) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.ink3)
                .font(.system(size: 13))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.fsBody))
                .focused(isFocused)
                .onSubmit { onSearch() }
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

            if let label = trailingLabel, let action = trailingAction {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: Theme.fsBody, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(label)
            }

            Button(action: onSearch) {
                Text(L10n.t(.search))
                    .font(.system(size: Theme.fsBody, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.sp4)
                    .padding(.vertical, Theme.sp1 + 2)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.search))
        }
        .padding(.horizontal, Theme.sp4)
        .padding(.vertical, Theme.sp3)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLg)
                .strokeBorder(isFocused.wrappedValue ? Theme.accent : Theme.line,
                              lineWidth: isFocused.wrappedValue ? 1.5 : 0.5)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused.wrappedValue)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: text.isEmpty)
    }
}

// MARK: - StateView (minimal: centered, quiet)

struct StateView: View {
    enum State {
        case loading(text: String = L10n.t(.loadingDetail))
        case empty(text: String = L10n.t(.emptyQuery))
        case error(message: String, retry: (() -> Void)? = nil)
    }

    let state: State

    var body: some View {
        VStack(spacing: Theme.sp3) {
            switch state {
            case .loading(let text):
                ProgressView()
                    .controlSize(.small)
                Text(text)
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)
            case .empty(let text):
                Text(text)
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.sp8)
            case .error(let message, let retry):
                VStack(spacing: Theme.sp3) {
                    VStack(spacing: Theme.sp2) {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.semanticError.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(Theme.semanticError.opacity(0.08))
                            .clipShape(Circle())
                        Text(message)
                            .font(.system(size: Theme.fsBody))
                            .foregroundColor(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.sp8)
                    }
                    // F17：错误态提供「重试」按钮，消除"网络错后只能重输"的挫败点
                    if let retry {
                        Button(action: retry) {
                            Label(L10n.t(.retry), systemImage: "arrow.clockwise")
                                .font(.system(size: Theme.fsSmall, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.sp4)
                                .padding(.vertical, Theme.sp2)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(L10n.t(.retry))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ResultList (minimal: clean rows, hairline dividers)

struct ResultList: View {
    let items: [ResultItem]
    @Binding var selectedItemId: String?
    let onTap: (ResultItem) -> Void
    var onLoadMore: (() -> Void)? = nil
    var isLoadingMore: Bool = false
    var hasMore: Bool = false
    /// 加载更多失败时的错误文案（P1-12：失败不再静默降级）
    var loadMoreError: String? = nil

    // 批量选择
    var selectionEnabled: Bool = false
    @Binding var selectedIds: Set<String>

    // 展示增强：关键词高亮 / 收藏标记 / 分类色
    var query: String? = nil
    var favoritedIds: Set<String> = []
    var accentColor: Color = Theme.accent
    /// 单行「加入集合」入口（D12）：hover 时在行尾显示 📁 按钮。
    var onAddToCollection: ((ResultItem) -> Void)? = nil
    /// C10：单行「加入对比」入口：hover 时在行尾显示 ＋ 按钮。
    var onAddToCompare: ((ResultItem) -> Void)? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    ResultRow(
                        item: item,
                        isSelected: selectedItemId == item.id,
                        onTap: {
                            selectedItemId = item.id
                            onTap(item)
                        },
                        selectionEnabled: selectionEnabled,
                        selectionMarked: selectedIds.contains(item.id),
                        onToggleSelection: {
                            if selectedIds.contains(item.id) {
                                selectedIds.remove(item.id)
                            } else {
                                selectedIds.insert(item.id)
                            }
                        },
                        query: query,
                        isFavorited: favoritedIds.contains(item.id),
                        accentColor: accentColor,
                        onAddToCollection: onAddToCollection,
                        onAddToCompare: onAddToCompare
                    )
                    thinDivider()
                }

                // Load more
                if hasMore {
                    softDivider()
                    if let loadMoreError, !loadMoreError.isEmpty {
                        VStack(spacing: Theme.sp2) {
                            Text(loadMoreError)
                                .font(.system(size: Theme.fsSmall))
                                .foregroundColor(Theme.semanticError)
                                .multilineTextAlignment(.center)
                            Button(action: { onLoadMore?() }) {
                                Text(L10n.t(.retry))
                                    .font(.system(size: Theme.fsSmall, weight: .medium))
                                    .foregroundColor(Theme.accent)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        .padding(.vertical, Theme.sp3)
                    } else if isLoadingMore {
                        HStack(spacing: Theme.sp2) {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Text(L10n.t(.loadingMore))
                                .font(.system(size: Theme.fsSmall))
                                .foregroundColor(Theme.ink3)
                            Spacer()
                        }
                        .padding(.vertical, Theme.sp3)
                    } else {
                        Button(action: { onLoadMore?() }) {
                            HStack(spacing: Theme.sp2) {
                                Spacer()
                                Text(L10n.t(.loadMore))
                                    .font(.system(size: Theme.fsSmall, weight: .medium))
                                    .foregroundColor(Theme.accent)
                                Spacer()
                            }
                            .padding(.vertical, Theme.sp3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(L10n.t(.loadMore))
                    }
                }
            }
        }
    }
}

struct ResultRow: View {
    let item: ResultItem
    var isSelected: Bool = false
    let onTap: () -> Void

    // 批量选择
        var selectionEnabled: Bool = false
        var selectionMarked: Bool = false
        var onToggleSelection: (() -> Void)? = nil

        // 展示增强：关键词高亮 / 已收藏标记 / 分类色
        var query: String? = nil
        var isFavorited: Bool = false
        var accentColor: Color = Theme.accent
    /// 单行「加入集合」（D12）：hover 时显示。
    var onAddToCollection: ((ResultItem) -> Void)? = nil
    /// C10：单行「加入对比」入口（hover 时显示）。
    var onAddToCompare: ((ResultItem) -> Void)? = nil

        @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: selectionEnabled ? { onToggleSelection?() } : onTap) {
            HStack(spacing: Theme.sp3) {
                // Selection checkbox
                if selectionEnabled {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(selectionMarked ? accentColor : Theme.ink3, lineWidth: 1.5)
                            .fill(selectionMarked ? accentColor : Color.clear)
                            .frame(width: 18, height: 18)
                        if selectionMarked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .accessibilityHidden(true)
                }

                // Category color dot (visual memory anchor per database)
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 2)

                // Left accent bar (visible when selected)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? accentColor : Color.clear)
                    .frame(width: 2.5)
                    .padding(.vertical, 4)

                // Badge: minimal monospace text, no background fill
                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: Theme.fsSmall, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? accentColor : Theme.ink3)
                        .lineLimit(1)
                        .frame(minWidth: 60, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 1) {
                    highlightedText(item.title,
                                    baseColor: isSelected ? accentColor : Theme.ink,
                                    font: .system(size: Theme.fsBody),
                                    lineLimit: 2)
                    if let subtitle = item.subtitle {
                        highlightedText(subtitle,
                                        baseColor: Theme.ink2,
                                        font: .system(size: Theme.fsSmall),
                                        lineLimit: 1)
                    }
                    if let meta = item.meta {
                        Text(meta)
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // 收藏标记（视觉锚点）
                if isFavorited {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.systemYellow))
                        .accessibilityHidden(true)
                        .padding(.trailing, 2)
                }

                // D12：单行「加入集合」入口（hover 时显示，避免常驻干扰）
                if let onAddToCollection, isHovered, !selectionEnabled {
                    Button(action: { onAddToCollection(item) }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.ink3)
                            .padding(2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(L10n.t(.addToCollection))
                    .accessibilityLabel(L10n.t(.addToCollection))
                }

                // C10：单行「加入对比」入口（hover 时显示）
                if let onAddToCompare, isHovered, !selectionEnabled {
                    Button(action: { onAddToCompare(item) }) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.ink3)
                            .padding(2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(L10n.t(.addCompare))
                    .accessibilityLabel(L10n.t(.addCompare))
                }

                if !selectionEnabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(isSelected ? accentColor.opacity(0.5) : Theme.ink4)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.vertical, Theme.sp3 + 2)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        // P2-9：多选模式下向 VoiceOver 暴露选中态
        .accessibilityAddTraits(selectionMarked ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint(L10n.t(.selectItem))
    }

    private var backgroundFill: Color {
        if isSelected {
            let isDark = colorScheme == .dark
            // P2-10：选中态复用分类色（与侧边栏选中一致的视觉签名），而非固定品牌蓝
            return accentColor.opacity(isDark ? 0.15 : 0.10)
        }
        if isHovered {
            return Theme.hoverBackground
        }
        return Color.clear
    }

    /// 在 title/subtitle 中高亮命中的检索关键词（大小写不敏感，支持多段命中）。
    private func highlightedText(_ text: String, baseColor: Color, font: Font, lineLimit: Int) -> some View {
        let q = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            return Text(text).foregroundColor(baseColor).font(font).lineLimit(lineLimit)
        }
        var result = Text("")
        var pos = text.startIndex
        while pos < text.endIndex,
              let range = text[pos...].range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            if pos < range.lowerBound {
                result = result + Text(text[pos..<range.lowerBound]).foregroundColor(baseColor).font(font)
            }
            result = result
                + Text(text[range])
                    .foregroundColor(Theme.accent)
                    .fontWeight(.semibold)
                    .font(font)
            pos = range.upperBound   // 先推进 pos，再判断是否到达末尾（P1-8：避免整段重复）
        }
        if pos < text.endIndex {
            result = result + Text(text[pos...]).foregroundColor(baseColor).font(font)
        }
        return result.lineLimit(lineLimit)
    }
}

// MARK: - KeyValueDetail (minimal: wide key-value pairs, no card boxes)

struct KeyValueDetail: View {
    let model: DetailModel
    var accentColor: Color = Theme.accent
    var isFavorited: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    var onAddToCollection: (() -> Void)? = nil
    /// P1-8：编辑收藏备注（已收藏时星标旁显示）。
    var onEditNote: (() -> Void)? = nil
    /// C10：详情头部「加入对比」入口。
    var onAddToCompare: (() -> Void)? = nil
    let onCopy: (String) -> Void
    let onAction: (DetailAction) -> Void
    let onXLink: (XLink) -> Void
    /// P1-5：⌘点击 XLink 时仅预览详情（不改动中间栏）。
    var onPreviewXLink: ((XLink) -> Void)? = nil

    /// P2-16：超长 KV 值默认折叠为 3 行，可展开。
    @State private var expandedKVRows: Set<String> = []
    private let kvCollapseThreshold = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sp6) {
                // Header
                headerView

                // Preview image (e.g. PDB structure, AlphaFold cartoon)
                if let imageUrl = model.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            HStack {
                                Spacer()
                                ProgressView().controlSize(.small)
                                Spacer()
                            }
                            .frame(height: 220)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 280)
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
                        case .failure:
                            // Failure placeholder: visible icon instead of silent empty
                            HStack {
                                Spacer()
                                VStack(spacing: Theme.sp2) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundColor(Theme.ink4)
                                    Text(L10n.t(.imageFailed))
                                        .font(.system(size: Theme.fsCaption))
                                        .foregroundColor(Theme.ink4)
                                }
                                Spacer()
                            }
                            .frame(height: 220)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .accessibilityLabel(L10n.t(.structurePreview))
                    .padding(.bottom, Theme.sp2)
                }

                // Action buttons (primary actions only, inline)
                if !model.actions.isEmpty {
                    actionsView
                }

                // Sections
                ForEach(model.sections) { section in
                    if !section.rows.isEmpty {
                        sectionView(section)
                    }
                }

                // Free text blocks
                ForEach(model.freeTextBlocks) { block in
                    freeTextBlockView(block)
                }

                // XLinks
                if !model.xlinks.isEmpty {
                    xlinkView
                }

                // Web URL — P0-3：消除强制解包崩溃风险，仅接受 http/https
                SafeLink(urlString: model.webUrl)
                    .padding(.top, Theme.sp2)
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.top, Theme.sp5)
            .padding(.bottom, Theme.sp8)
            .frame(maxWidth: 720)
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: Theme.sp3) {
            // Category color signature rail (visual memory anchor per database)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: Theme.sp1 + 2) {
                Text(model.headerTitle)
                    .font(.system(size: Theme.fsLargeTitle, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .tracking(Theme.trackTitle)
                    .textSelection(.enabled)
                if let subtitle = model.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: Theme.fsBody))
                        .foregroundColor(Theme.ink2)
                        .textSelection(.enabled)
                }
                if let meta = model.headerMeta, !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.ink3)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if let onToggle = onToggleFavorite {
                Button(action: onToggle) {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(isFavorited ? accentColor : Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(isFavorited ? L10n.t(.unfavorite) : L10n.t(.favorite))
            }

            // P1-8：已收藏时提供「编辑笔记」入口
            if isFavorited, let onEditNote {
                Button(action: onEditNote) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .help(L10n.t(.editNote))
                .accessibilityLabel(L10n.t(.editNote))
            }

            if let onAdd = onAddToCollection {
                Button(action: onAdd) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.addToCollection))
            }

            if let onAddCompare = onAddToCompare {
                Button(action: onAddCompare) {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .help(L10n.t(.addCompare))
                .accessibilityLabel(L10n.t(.addCompare))
            }
        }
        .padding(.bottom, Theme.sp1)
    }

    private var actionsView: some View {
        FlowLayout(spacing: Theme.sp2) {
            ForEach(model.actions) { action in
                Button(action: { onAction(action) }) {
                    Text(action.label)
                        .font(.system(size: Theme.fsSmall, weight: .medium))
                        .foregroundColor(action.style == .primary ? .white : Theme.ink2)
                        .padding(.horizontal, Theme.sp3)
                        .padding(.vertical, Theme.sp1 + 2)
                        .background(action.style == .primary ? Theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSm)
                                .strokeBorder(action.style == .primary ? Color.clear : Theme.lineStrong, lineWidth: 0.5)
                        )
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private func sectionView(_ section: KVSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = section.title {
                Text(title)
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .textCase(.uppercase)
                    .tracking(Theme.trackSection)
                    .padding(.bottom, Theme.sp2)
            }
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { idx, row in
                    HStack(alignment: .top, spacing: Theme.sp4) {
                        Text(row.key)
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink3)
                            .frame(minWidth: 88, maxWidth: 120, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.top, 1)
                        // P3-3：展开态 key 用 section.id（UUID），避免不同 section 同索引+同名冲突
                        valueView(row, keyPrefix: section.id.uuidString)
                        if row.copyable {
                            Button(action: { onCopy(row.value) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.ink3)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .opacity(0.6)
                            .accessibilityLabel(L10n.t(.copyKey, row.key))
                        }
                    }
                    .padding(.vertical, Theme.sp1 + 2)
                    if idx < section.rows.count - 1 {
                        softDivider()
                    }
                }
            }
        }
        .padding(Theme.sp4)
        .cardStyle()
    }

    /// 正文行内可点击渲染：优先使用显式 link / xlinkTarget，其次自动识别 URL。
    /// P2-16：超长文本默认折叠为 3 行并支持展开。
    private func valueView(_ row: KVRow, keyPrefix: String) -> some View {
        let rowKey = "\(keyPrefix)-\(row.key)"
        let isExpanded = expandedKVRows.contains(rowKey)
        let isLong = row.value.count > kvCollapseThreshold

        // 非长文本：沿用原渲染
        if !isLong {
            return AnyView(simpleValueView(row))
        }

        // 长文本：折叠 + 展开/收起（与 FreeTextBlockCard 行为一致）
        return AnyView(
            VStack(alignment: .leading, spacing: Theme.sp1) {
                Text(row.value)
                    .font(.system(size: Theme.fsBody, design: row.copyable ? .monospaced : .default))
                    .foregroundColor(Theme.ink)
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: { toggleExpanded(rowKey) }) {
                    Text(isExpanded ? L10n.t(.collapse) : L10n.t(.expandAll))
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(isExpanded ? L10n.t(.collapse) : L10n.t(.expandAll))
            }
        )
    }

    private func toggleExpanded(_ key: String) {
        if expandedKVRows.contains(key) {
            expandedKVRows.remove(key)
        } else {
            expandedKVRows.insert(key)
        }
    }

    /// 短文本 / 链接型 KV 值的原渲染逻辑。
    @ViewBuilder
    private func simpleValueView(_ row: KVRow) -> some View {
        let text = Text(row.value)
            .font(.system(size: Theme.fsBody, design: row.copyable ? .monospaced : .default))
            .textSelection(.enabled)

        if let link = row.link {
            Link(destination: link) {
                HStack(spacing: 3) {
                    text
                    Image(systemName: "arrow.up.right").font(.system(size: 9))
                }
            }
            .foregroundColor(Theme.accent)
        } else if let x = row.xlinkTarget {
            Button(action: { onXLink(x) }) {
                HStack(spacing: 3) {
                    text
                    Image(systemName: "link").font(.system(size: 9))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(Theme.accent)
        } else if ProviderHelpers.isURL(row.value), let url = URL(string: row.value) {
            Link(destination: url) {
                HStack(spacing: 3) {
                    text
                    Image(systemName: "arrow.up.right").font(.system(size: 9))
                }
            }
            .foregroundColor(Theme.accent)
        } else {
            text.foregroundColor(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func freeTextBlockView(_ block: FreeTextBlock) -> some View {
        FreeTextBlockCard(block: block, onCopy: onCopy)
    }

    private var xlinkView: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            Text(L10n.t(.crossLinks))
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.ink3)
                .textCase(.uppercase)
                .tracking(Theme.trackSection)
            FlowLayout(spacing: Theme.sp2) {
                ForEach(model.xlinks) { link in
                    Button(action: {
                        // P1-5：⌘点击仅预览详情（软跳转），普通点击为硬跳转（切换中栏）
                        if NSEvent.modifierFlags.contains(.command), let preview = onPreviewXLink {
                            preview(link)
                        } else {
                            onXLink(link)
                        }
                    }) {
                        Text(link.label)
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, Theme.sp2 + 2)
                            .padding(.vertical, Theme.sp1)
                            .background(Theme.accent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusSm)
                                    .strokeBorder(Theme.accent.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help(L10n.t(.xlinkDesc))
                }
            }
        }
        .padding(Theme.sp4)
        .cardStyle()
    }
}

// MARK: - FreeTextBlockCard (long-text collapse support)

/// 长文本卡片：超过阈值时默认折叠为 N 行，并提供「展开全文 / 收起」切换。
private struct FreeTextBlockCard: View {
    let block: FreeTextBlock
    let onCopy: (String) -> Void
    @State private var expanded = false

    private let threshold = 200

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            HStack {
                if let title = block.title {
                    Text(title)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                        .textCase(.uppercase)
                        .tracking(Theme.trackSection)
                }
                Spacer()
                if block.copyable {
                    Button(action: { onCopy(block.text) }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.ink3)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .opacity(0.6)
                    .accessibilityLabel(L10n.t(.copyKey, block.title ?? ""))
                }
            }

            if block.text.count > threshold && !expanded {
                Text(block.text)
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.ink2)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                Button(action: { expanded = true }) {
                    Text(L10n.t(.expandFull))
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(L10n.t(.expandFull))
            } else {
                Text(block.text)
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.ink2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                if block.text.count > threshold {
                    Button(action: { expanded = false }) {
                        Text(L10n.t(.collapse))
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(L10n.t(.collapse))
                }
            }
        }
        .padding(Theme.sp4)
        .cardStyle()
        // H25：VoiceOver 用户可感知折叠态与内容规模
        .accessibilityValue(block.text.count > threshold && !expanded
            ? L10n.t(.collapse) : L10n.t(.expandFull))
    }
}

// MARK: - SafeLink（外部链接安全渲染，P0-3）

/// 外部 URL 安全链接：仅接受 http/https，其余（空值、异常 scheme、非法 URL）静默不渲染。
/// 消除 `URL(string:)!` 强制解包导致的崩溃风险。
struct SafeLink: View {
    let urlString: String?
    var label: String = L10n.t(.viewOnWebsite)

    var body: some View {
        if let urlString,
           let url = URL(string: urlString),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            Link(destination: url) {
                HStack(spacing: Theme.sp1 + 2) {
                    Text(label)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.accent)
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - FlowLayout (simple wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Only wrap if we're past the start of a line (prevents infinite wrap for oversized items)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Only wrap if we're past the start of a line
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
