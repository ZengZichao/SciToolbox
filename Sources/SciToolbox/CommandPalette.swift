import SwiftUI

// MARK: - CommandPalette (⌘K keyboard shortcut to quickly switch tools)

/// A lightweight command palette overlay. Triggered by ⌘K.
/// Lets users type to filter all 16 tools and press Enter to navigate.
/// Supports ↑↓ arrow key navigation with highlighted current row.
///
/// P1-6：支持带查询语法 —— 输入 `uniprot:P12345` 或 `P12345 @uniprot`，
/// 选中后一并携带查询词跳转，命中现有 prefill 通道，省去二次输入。
struct CommandPaletteView: View {
    @EnvironmentObject var registry: ToolRegistry
    @Binding var isPresented: Bool
    /// 回调参数：(toolId, query?)
    let onSelect: (String, String?) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 解析后的查询词（`工具:查询` / `查询 @工具` 语法，P1-6）。
    private var parsedQuery: String? {
        let t = searchText.trimmingCharacters(in: .whitespaces)
        if let idx = t.firstIndex(of: ":") {
            let queryPart = t[t.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            return queryPart.isEmpty ? nil : queryPart
        }
        if let at = t.lastIndex(of: "@") {
            let queryPart = t[..<at].trimmingCharacters(in: .whitespaces)
            return queryPart.isEmpty ? nil : queryPart
        }
        return nil
    }

    private var filterText: String {
        let t = searchText.trimmingCharacters(in: .whitespaces)
        if let idx = t.firstIndex(of: ":") {
            return String(t[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        if let at = t.lastIndex(of: "@") {
            return String(t[t.index(after: at)...]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    private var filteredTools: [(any ToolProvider)] {
        let all = registry.providers
        let key = filterText
        guard !key.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(key)
                || $0.dataSourceNote.localizedCaseInsensitiveContains(key)
                || $0.id.localizedCaseInsensitiveContains(key)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: Theme.sp2) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.ink3)
                    .font(.system(size: 14))
                TextField(L10n.t(.cmdPalettePlaceholder), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.fsBody))
                    .focused($isFocused)
                    .submitLabel(.go)
                    .onSubmit {
                        if !filteredTools.isEmpty {
                            select(filteredTools[min(selectedIndex, filteredTools.count - 1)].id)
                        }
                    }
                    .onKeyPress(.escape) {
                        isPresented = false
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if selectedIndex > 0 {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.1)) {
                                selectedIndex -= 1
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if selectedIndex < filteredTools.count - 1 {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.1)) {
                                selectedIndex += 1
                            }
                        }
                        return .handled
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        selectedIndex = 0
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.ink2)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(L10n.t(.clearSearch))
                }
            }
            .padding(.horizontal, Theme.sp4)
            .padding(.vertical, Theme.sp3)

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredTools.enumerated()), id: \.element.id) { index, tool in
                            Button(action: { select(tool.id) }) {
                                HStack(spacing: Theme.sp3) {
                                    Image(systemName: tool.iconName)
                                        .font(.system(size: 14))
                                        .foregroundColor(index == selectedIndex ? Theme.accent : Theme.ink3)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tool.name)
                                            .font(.system(size: Theme.fsBody))
                                            .foregroundColor(index == selectedIndex ? Theme.accent : Theme.ink)
                                        Text(tool.dataSourceNote)
                                            .font(.system(size: Theme.fsCaption))
                                            .foregroundColor(Theme.ink3)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if let q = parsedQuery, index == selectedIndex {
                                        Text(L10n.t(.queryLabel, q))
                                            .font(.system(size: Theme.fsCaption, design: .monospaced))
                                            .foregroundColor(Theme.accent)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, Theme.sp4)
                                .padding(.vertical, Theme.sp2 + 2)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                                        .fill(index == selectedIndex ? Theme.hoverBackground : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .id(index)
                            softDivider()
                        }
                        if filteredTools.isEmpty {
                            Text(L10n.t(.noMatchTool))
                                .font(.system(size: Theme.fsBody))
                                .foregroundColor(Theme.ink3)
                                .padding(.vertical, Theme.sp6)
                        }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLg)
                .strokeBorder(Theme.lineStrong, lineWidth: 0.5)
        )
        .frame(width: 460, height: 380)
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onAppear {
            isFocused = true
            selectedIndex = 0
        }
    }

    private func select(_ id: String) {
        onSelect(id, parsedQuery)
        isPresented = false
    }
}
