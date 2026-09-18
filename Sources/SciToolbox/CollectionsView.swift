import SwiftUI
import AppKit

// MARK: - CollectionsView（项目集合列表）

struct CollectionsView: View {
    @StateObject private var store = CollectionStore.shared
    @EnvironmentObject var registry: ToolRegistry
    @State private var activeId: String? = nil
    /// 与收藏/历史页保持一致的可选回调（本视图内部通过 NotificationCenter 直接跳转，此处保留以匹配调用点）。
    var onToolSelected: ((String) -> Void)? = nil
    /// P0-1：删除集合二次确认
    @State private var confirmDeleteId: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let id = activeId, let collection = store.collections.first(where: { $0.id == id }) {
                CollectionDetailView(collectionId: collection.id, onBack: { activeId = nil })
                    .id(collection.id)
            } else {
                listView
            }
        }
        .navigationTitle(L10n.t(.collectionsTitle))
        .confirmationDialog(
            confirmDeleteId.flatMap { id in store.collections.first { $0.id == id }.map { c in L10n.t(.confirmDeleteCollection, c.name, c.entries.count) } } ?? L10n.t(.confirmDeleteCollection2, ""),
            isPresented: Binding(
                get: { confirmDeleteId != nil },
                set: { if !$0 { confirmDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.t(.deleteCollection), role: .destructive) {
                if let id = confirmDeleteId {
                    store.delete(id: id)
                    Clipboard.showToast(L10n.t(.deletedCollection))
                }
                confirmDeleteId = nil
            }
            Button(L10n.t(.cancelBtn), role: .cancel) { confirmDeleteId = nil }
        } message: {
            Text(L10n.t(.deleteCollectionMsg))
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.sp3) {
                Text(L10n.t(.collectionsTitle))
                    .font(.system(size: Theme.fsHeadline, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(L10n.t(.collectionCount, store.collections.count))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink3)

                Spacer()

                if !store.collections.isEmpty {
                    Button(action: { exportJSON() }) {
                        Label(L10n.t(.exportAll), systemImage: "square.and.arrow.up")
                            .font(.system(size: Theme.fsSmall))
                    }
                    .buttonStyle(PressableButtonStyle())
                }

                Button(action: { createCollection() }) {
                    Label(L10n.t(.newCollection), systemImage: "plus")
                        .font(.system(size: Theme.fsSmall, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.sp3)
                        .padding(.vertical, Theme.sp1 + 2)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.newCollection))
            }
            .padding(.horizontal, Theme.sp6)
            .padding(.vertical, Theme.sp4)

            thinDivider()

            if store.collections.isEmpty {
                StateView(state: .empty(text: L10n.t(.collectionsEmpty)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.collections) { c in
                            CollectionRowView(
                                collection: c,
                                onOpen: { activeId = c.id },
                                onDelete: { confirmDeleteId = c.id }
                            )
                            thinDivider()
                        }
                    }
                }
            }
        }
    }

    private func createCollection() {
        let c = store.create(name: L10n.t(.newTopic, store.collections.count + 1))
        activeId = c.id
    }

    private func exportJSON() {
        let fileName = "SciToolbox\(L10n.t(.collectionsTitle)).json"
        let content = store.exportAsJSON()
        // P2-6：写盘失败不再静默
        let ok = ExportUtil.saveTextFile(content, defaultName: fileName, ext: "json")
        if ok {
            Clipboard.showToast(L10n.t(.exported, fileName))
        }
    }
}

// MARK: - CollectionRowView（集合行；独立 View，hover 状态按行隔离）

private struct CollectionRowView: View {
    let collection: SciCollection
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.sp3) {
            Image(systemName: "folder")
                .font(.system(size: 14))
                .foregroundColor(Theme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.sp1) {
                    Text(collection.name)
                        .font(.system(size: Theme.fsBody))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                    Text(collection.relativeUpdated)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                }
                Text(L10n.t(.entityCount, collection.entries.count))
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.ink2)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(Theme.ink4)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.ink3)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.deleteCollectionA11y, collection.name))
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp3)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .fill(isHovered ? Theme.hoverBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t(.openCollectionA11y, collection.name))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.t(.entityCount, collection.entries.count))
    }
}

// MARK: - CollectionDetailView（集合内的实体）

struct CollectionDetailView: View {
    let collectionId: String
    let onBack: () -> Void

    @StateObject private var store = CollectionStore.shared
    @EnvironmentObject var registry: ToolRegistry
    @State private var showCompare = false
    @State private var showRename = false
    @State private var renameText = ""
    /// P1-8：课题笔记编辑
    @State private var showNoteEditor = false
    @State private var noteEditorText = ""
    /// P1-8：实体行内笔记编辑
    @State private var editingEntryNoteId: String? = nil
    @State private var entryNoteDraft = ""
    /// P0-1：删除集合确认
    @State private var confirmDeleteCollection = false

    private var collection: SciCollection? { store.collections.first { $0.id == collectionId } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.sp2) {
                Button(action: onBack) {
                    HStack(spacing: Theme.sp1) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                        Text(L10n.t(.back))
                            .font(.system(size: Theme.fsSmall))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.backToList))

                Spacer()

                if let c = collection {
                    Menu {
                        Button(L10n.t(.rename)) { startRename() }
                        Button(L10n.t(.editCollectionNote)) { startNoteEdit() }
                        Button(L10n.t(.exportCSV)) { exportCSV(c) }
                        Button(L10n.t(.exportJSON)) { exportJSON(c) }
                        Divider()
                        Button(role: .destructive) { confirmDeleteCollection = true } label: {
                            Text(L10n.t(.deleteCollection))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: Theme.fsBody))
                            .foregroundColor(Theme.ink2)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.vertical, Theme.sp2)

            HStack(spacing: Theme.sp2) {
                Image(systemName: "folder.fill")
                    .foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(collection?.name ?? "")
                        .font(.system(size: Theme.fsHeadline, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    if let note = collection?.note, !note.isEmpty {
                        Text("📝 \(note)")
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink3)
                            .lineLimit(1)
                    }
                }
                if let c = collection {
                    Text(L10n.t(.entityCount, c.entries.count))
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.ink3)
                }
                Spacer()
                if let c = collection, !c.entries.isEmpty {
                    // P1-7：重命名语义，副标题说明用途
                    Button(action: { showCompare = true }) {
                        Label(L10n.t(.batchVerify), systemImage: "tablecells")
                            .font(.system(size: Theme.fsSmall, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.sp3)
                            .padding(.vertical, Theme.sp1 + 2)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help(L10n.t(.refreshLatest))
                    .accessibilityLabel(L10n.t(.batchVerify))
                }
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.bottom, Theme.sp3)

            thinDivider()

            if let c = collection, c.entries.isEmpty {
                StateView(state: .empty(text: L10n.t(.collectionEmpty)))
            } else if let c = collection {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(c.entries) { entry in
                            entryRow(entry)
                            thinDivider()
                        }
                    }
                }
            } else {
                StateView(state: .empty(text: L10n.t(.collectionNotExist)))
            }
        }
        .navigationTitle(collection?.name ?? L10n.t(.collectionsTitle))
        .sheet(isPresented: $showCompare) {
            if let c = collection {
                CollectionCompareView(collectionId: c.id)
            }
        }
        .alert(L10n.t(.renameCollection), isPresented: $showRename) {
            TextField(L10n.t(.namePlaceholder), text: $renameText)
            Button(L10n.t(.cancelBtn), role: .cancel) {}
            Button(L10n.t(.save)) { store.rename(id: collectionId, name: renameText) }
        } message: {
            Text(L10n.t(.namePrompt))
        }
        // P1-8：课题笔记编辑
        .alert(L10n.t(.editCollectionNote), isPresented: $showNoteEditor) {
            TextField(L10n.t(.collectionNotePlaceholder), text: $noteEditorText)
            Button(L10n.t(.cancelBtn), role: .cancel) {}
            Button(L10n.t(.save)) {
                store.updateNote(id: collectionId, note: noteEditorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteEditorText.trimmingCharacters(in: .whitespacesAndNewlines))
                Clipboard.showToast(L10n.t(.collectionNoteUpdated))
            }
        } message: {
            Text(L10n.t(.collectionNotePrompt))
        }
        // P0-1：删除集合确认
        .confirmationDialog(L10n.t(.confirmDeleteCollection2, collection?.name ?? ""), isPresented: $confirmDeleteCollection, titleVisibility: .visible) {
            Button(L10n.t(.deleteCollection), role: .destructive) {
                store.delete(id: collectionId)
                onBack()
            }
            Button(L10n.t(.cancelBtn), role: .cancel) {}
        } message: {
            Text(L10n.t(.deleteCollectionMsg2, collection?.entries.count ?? 0))
        }
    }

    private func entryRow(_ entry: CollectionEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.sp1) {
            HStack(spacing: Theme.sp3) {
                let provider = registry.find(id: entry.toolId)
                let color = (provider?.category).map { Theme.categoryColor($0) } ?? Theme.ink3
                Image(systemName: provider?.iconName ?? "doc")
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)

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
                    Text(entry.title)
                        .font(.system(size: Theme.fsBody))
                        .foregroundColor(Theme.ink)
                        .lineLimit(2)
                    if let sub = entry.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink2)
                            .lineLimit(1)
                    }
                    if let note = entry.note, !note.isEmpty, editingEntryNoteId != entry.id {
                        Text("📝 \(note)")
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink3)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                // P1-8：实体备注编辑
                Button(action: {
                    editingEntryNoteId = entry.id
                    entryNoteDraft = entry.note ?? ""
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .help(L10n.t(.editNote))
                .accessibilityLabel(L10n.t(.editEntryNoteA11y, entry.title))

                Button(action: { reopen(entry) }) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.openInToolA11y, entry.toolName, entry.title))

                // P0-1：移除实体 → 可撤销 Toast
                Button(action: {
                    if let removed = store.removeEntryWithItem(collectionId: collectionId, entryId: entry.id) {
                        Clipboard.showUndoableToast(L10n.t(.removedFromCollection), undo: {
                            store.restoreEntry(removed, to: collectionId)
                        })
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ink3)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.removeFromCollectionA11y))
            }
            .padding(.horizontal, Theme.sp5)
            .padding(.top, Theme.sp3)

            // P1-8：行内备注编辑
            if editingEntryNoteId == entry.id {
                HStack(spacing: Theme.sp2) {
                    TextField(L10n.t(.entityNotePlaceholder), text: $entryNoteDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.fsSmall))
                        .padding(.horizontal, Theme.sp3)
                        .padding(.vertical, Theme.sp1 + 2)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.line, lineWidth: 0.5))
                    Button(L10n.t(.save)) {
                        store.updateEntryNote(collectionId: collectionId, entryId: entry.id,
                                              note: entryNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : entryNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        editingEntryNoteId = nil
                        Clipboard.showToast(L10n.t(.noteUpdated))
                    }
                    .font(.system(size: Theme.fsSmall, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.sp3)
                    .padding(.vertical, Theme.sp1 + 2)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .buttonStyle(PressableButtonStyle())
                    Button(L10n.t(.cancelBtn)) { editingEntryNoteId = nil }
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.ink3)
                        .buttonStyle(PressableButtonStyle())
                }
                .padding(.horizontal, Theme.sp5)
                .padding(.bottom, Theme.sp3)
            } else {
                Color.clear.frame(height: Theme.sp1)
            }
        }
    }

    private func reopen(_ entry: CollectionEntry) {
        NotificationCenter.default.post(
            name: .navigateToTool,
            object: nil,
            // P3-9：带 autoDetail，重查后直接打开该条详情
            userInfo: ["toolId": entry.toolId, "query": entry.itemId, "autoDetail": true]
        )
    }

    private func startRename() {
        renameText = collection?.name ?? ""
        showRename = true
    }

    private func startNoteEdit() {
        noteEditorText = collection?.note ?? ""
        showNoteEditor = true
    }

    private func exportCSV(_ c: SciCollection) {
        let rows = c.entries.map { [$0.toolName, $0.itemId, $0.title, $0.subtitle ?? ""] }
        // P2-8 / P1-7：专用表头键，避免复用按钮文案且列头与列内容一一对应
        let csv = ExportUtil.buildCSV(header: [L10n.t(.csvSource), L10n.t(.csvAccession), L10n.t(.csvTitle), L10n.t(.csvSubtitle)], rows: rows)
        let ok = ExportUtil.saveTextFile(csv, defaultName: "SciToolbox_\(c.name)", ext: "csv")
        if ok { Clipboard.showToast(L10n.t(.exported, "CSV")) }
    }

    private func exportJSON(_ c: SciCollection) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(c) else { return }
        let ok = ExportUtil.saveTextFile(String(data: data, encoding: .utf8) ?? "", defaultName: "SciToolbox_\(c.name)", ext: "json")
        if ok { Clipboard.showToast(L10n.t(.exported, "JSON")) }
    }
}

// MARK: - CollectionCompareView（批量核对 / 重新拉取）

/// 对集合内所有实体逐一重新拉取详情（best-effort），并汇总成可对比的表格。
/// 拉取失败时使用条目存储的标题/副标题作为回退，保证「留痕」始终可见。
/// P1-7 / D13：逐项状态 + 总体进度 + 节流预估 + 行内重试，消除黑盒等待。
struct CollectionCompareView: View {
    let collectionId: String

    @StateObject private var store = CollectionStore.shared
    @EnvironmentObject var registry: ToolRegistry
    @Environment(\.dismiss) private var dismiss

    enum EntryStatus { case pending, loading, success, failed }
    @State private var statuses: [String: EntryStatus] = [:]
    @State private var details: [String: DetailModel] = [:]
    @State private var errors: [String: String] = [:]
    @State private var isRunning = false
    @State private var loadTask: Task<Void, Never>?

    private var entries: [CollectionEntry] {
        store.collections.first { $0.id == collectionId }?.entries ?? []
    }

    private var completedCount: Int {
        statuses.values.filter { $0 == .success || $0 == .failed }.count
    }

    private var failedCount: Int {
        statuses.values.filter { $0 == .failed }.count
    }

    /// 命中 NCBI E-utilities 的条目数（受 3s 节流串行化）。
    private var ncbiCount: Int {
        entries.filter { isNCBIClient($0.toolId) }.count
    }

    private func isNCBIClient(_ toolId: String) -> Bool {
        let id = toolId.lowercased()
        return id.contains("ncbi") || id == "pubmed"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.sp2) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t(.batchVerify))
                        .font(.system(size: Theme.fsHeadline, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text(L10n.t(.batchVerifyHint, entries.count))
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.ink3)
                }
                Spacer()
                Button(action: { exportTable() }) {
                    Label(L10n.t(.exportTable2), systemImage: "square.and.arrow.up")
                        .font(.system(size: Theme.fsSmall))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.exportCompareTableA11y))
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

            // 总体进度（P1-7）
            if !entries.isEmpty {
                VStack(spacing: Theme.sp2) {
                    HStack(spacing: Theme.sp2) {
                        Text(L10n.t(.progress, completedCount, entries.count))
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink2)
                        Spacer()
                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                        } else if completedCount == entries.count {
                            Text(failedCount > 0 ? L10n.t(.completed, failedCount) : L10n.t(.allComplete))
                                .font(.system(size: Theme.fsSmall))
                                .foregroundColor(failedCount > 0 ? Theme.semanticWarning : Theme.semanticSuccess)
                        } else {
                            Text(L10n.t(.notStarted))
                                .font(.system(size: Theme.fsSmall))
                                .foregroundColor(Theme.ink3)
                        }
                    }
                    ProgressView(value: Double(completedCount), total: Double(max(entries.count, 1)))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                    // F19 / P1-7：节流预估提示
                    if ncbiCount > 0 {
                        Text(L10n.t(.ncbiEstimate, ncbiCount, ncbiCount * 3))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if completedCount < entries.count && !isRunning {
                        Button(action: startLoad) {
                            Label(L10n.t(.startVerify), systemImage: "play.fill")
                                .font(.system(size: Theme.fsSmall, weight: .medium))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.sp5)
                .padding(.vertical, Theme.sp3)
            }

            Divider()

            if entries.isEmpty {
                StateView(state: .empty(text: L10n.t(.compareNoEntries)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            compareRow(entry)
                            softDivider()
                        }
                    }
                    .padding(.vertical, Theme.sp2)
                }
            }
        }
        .frame(width: 680, height: 500)
        .onAppear { startLoad() }
        .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private func compareRow(_ entry: CollectionEntry) -> some View {
        let model = details[entry.id]
        let status = statuses[entry.id] ?? .pending
        let title = model?.headerTitle ?? entry.title
        let subtitle = (model?.headerSubtitle) ?? entry.subtitle ?? ""
        let provider = registry.find(id: entry.toolId)
        let color = (provider?.category).map { Theme.categoryColor($0) } ?? Theme.ink3

        HStack(spacing: Theme.sp3) {
            // 状态图标
            Group {
                switch status {
                case .pending:
                    Circle()
                        .strokeBorder(Theme.ink4, lineWidth: 1)
                        .frame(width: 12, height: 12)
                case .loading:
                    ProgressView()
                        .controlSize(.mini)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.semanticSuccess)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.semanticError)
                }
            }
            .frame(width: 16)
            .accessibilityLabel(statusLabel(status))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.sp1) {
                    Text(entry.toolName)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(color)
                    if status == .failed, let err = errors[entry.id] {
                        Text(L10n.t(.fetchFailed, err))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.semanticError)
                            .lineLimit(1)
                    } else if status == .pending {
                        Text(L10n.t(.waiting))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                    }
                }
                Text(title)
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.ink)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            // 失败重试（P1-7）
            if status == .failed {
                Button(action: { Task { await loadOne(entry) } }) {
                    Label(L10n.t(.retry), systemImage: "arrow.clockwise")
                        .font(.system(size: Theme.fsSmall))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.retry))
            }

            Button(action: {
                NotificationCenter.default.post(name: .navigateToTool, object: nil,
                    userInfo: ["toolId": entry.toolId, "query": entry.itemId])
                dismiss()
            }) {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(Theme.ink3)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(.openInToolA11y, entry.toolName, title))
        }
        .padding(.horizontal, Theme.sp5)
        .padding(.vertical, Theme.sp3)
    }

    private func statusLabel(_ status: EntryStatus) -> String {
        switch status {
        case .pending: L10n.t(.pending)
        case .loading: L10n.t(.loading)
        case .success: L10n.t(.success)
        case .failed: L10n.t(.failed)
        }
    }

    private func startLoad() {
        guard !isRunning, entries.count > completedCount else { return }
        isRunning = true
        loadTask?.cancel()
        loadTask = Task {
            // 进入并发 TaskGroup 前，先在主线程解析出 (entryId, provider, itemId, context)，
            // 避免在 @Sendable 闭包内访问被推断为 @MainActor 的 registry。
            let tasks = entries.map { entry in
                (entry.id, registry.find(id: entry.toolId), entry.itemId, entry.context)
            }
            // 先标记全部 loading，随后逐项完成即增量刷新（P1-7：非整体转圈）
            for entry in entries {
                statuses[entry.id] = .loading
            }
            await withTaskGroup(of: (String, DetailModel?, String?).self) { group in
                for (entryId, provider, itemId, context) in tasks {
                    group.addTask {
                        guard let provider else { return (entryId, nil, L10n.t(.toolNotFound)) }
                        do {
                            let m = try await provider.detail(id: itemId, context: context)
                            return (entryId, m, nil)
                        } catch {
                            return (entryId, nil, error.localizedDescription)
                        }
                    }
                }
                for await (id, model, err) in group {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        if let model {
                            details[id] = model
                            statuses[id] = .success
                        } else {
                            errors[id] = err
                            statuses[id] = .failed
                        }
                    }
                }
            }
            await MainActor.run {
                isRunning = false
                if completedCount == entries.count, failedCount == 0 {
                    Clipboard.showToast(L10n.t(.batchVerifyComplete))
                }
            }
        }
    }

    /// 单条重试（失败行）。
    private func loadOne(_ entry: CollectionEntry) async {
        guard let provider = registry.find(id: entry.toolId) else { return }
        statuses[entry.id] = .loading
        do {
            let m = try await provider.detail(id: entry.itemId, context: entry.context)
            await MainActor.run {
                details[entry.id] = m
                statuses[entry.id] = .success
                errors[entry.id] = nil
            }
        } catch {
            await MainActor.run {
                errors[entry.id] = error.localizedDescription
                statuses[entry.id] = .failed
            }
        }
    }

    private func exportTable() {
        var rows: [[String]] = []
        for entry in entries {
            let model = details[entry.id]
            rows.append([
                entry.toolName,
                entry.itemId,
                model?.headerTitle ?? entry.title,
                (model?.headerSubtitle) ?? entry.subtitle ?? ""
            ])
        }
        let csv = ExportUtil.buildCSV(header: [L10n.t(.source), L10n.t(.copyAccessions), L10n.t(.name), L10n.t(.subtitleField)], rows: rows)
        let name = store.collections.first { $0.id == collectionId }?.name ?? L10n.t(.collectionsTitle)
        let ok = ExportUtil.saveTextFile(csv, defaultName: "SciToolbox_\(name)", ext: "csv")
        if ok { Clipboard.showToast(L10n.t(.exportTableDone)) }
    }
}

// MARK: - AddToCollectionSheet（把候选实体加入集合）

/// 复用于：搜索结果批量多选「加入集合」、详情页「加入集合」。
struct AddToCollectionSheet: View {
    let candidates: [CollectionCandidate]
    let onDone: () -> Void

    @StateObject private var store = CollectionStore.shared
    @State private var newName = ""
    @State private var showNewField = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.sp2) {
                Text(L10n.t(.addToCollectionTitle))
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

            Text(L10n.t(.addToCollectionHint, candidates.count))
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.sp5)

            Divider().padding(.vertical, Theme.sp2)

            if showNewField {
                HStack(spacing: Theme.sp2) {
                    TextField(L10n.t(.newCollectionName), text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.fsBody))
                        .padding(.horizontal, Theme.sp3)
                        .padding(.vertical, Theme.sp2)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.line, lineWidth: 0.5))
                    Button(action: { createAndAdd() }) {
                        Text(L10n.t(.createAndAdd))
                            .font(.system(size: Theme.fsSmall, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.sp3)
                            .padding(.vertical, Theme.sp2)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, Theme.sp5)
                .padding(.bottom, Theme.sp2)
            }

            ScrollView {
                LazyVStack(spacing: Theme.sp2) {
                    if !showNewField {
                        Button(action: { showNewField = true }) {
                            HStack(spacing: Theme.sp2) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(Theme.accent)
                                Text(L10n.t(.newCollectionDots))
                                    .font(.system(size: Theme.fsBody))
                                    .foregroundColor(Theme.accent)
                                Spacer()
                            }
                            .padding(.horizontal, Theme.sp3)
                            .padding(.vertical, Theme.sp2 + 2)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .padding(.horizontal, Theme.sp5)
                    }

                    if store.collections.isEmpty {
                        Text(L10n.t(.noCollectionsHint))
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.sp5)
                    }

                    ForEach(store.collections) { c in
                        Button(action: { addTo(c.id) }) {
                            HStack(spacing: Theme.sp3) {
                                Image(systemName: "folder")
                                    .foregroundColor(Theme.accent)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.name)
                                        .font(.system(size: Theme.fsBody))
                                        .foregroundColor(Theme.ink)
                                    Text(L10n.t(.entityCount, c.entries.count))
                                        .font(.system(size: Theme.fsSmall))
                                        .foregroundColor(Theme.ink2)
                                }
                                Spacer()
                                Image(systemName: "plus")
                                    .foregroundColor(Theme.ink3)
                            }
                            .padding(.horizontal, Theme.sp3)
                            .padding(.vertical, Theme.sp2 + 2)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.line, lineWidth: 0.5))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .padding(.horizontal, Theme.sp5)
                    }
                }
                .padding(.vertical, Theme.sp2)
            }
        }
        .frame(width: 440, height: 420)
    }

    private func addTo(_ collectionId: String) {
        let entries = candidates.map { $0.toEntry() }
        store.addEntries(entries, to: collectionId)
        Clipboard.showToast(L10n.t(.addedEntities, entries.count))
        dismiss()
        onDone()
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let c = store.create(name: name)
        addTo(c.id)
    }
}
