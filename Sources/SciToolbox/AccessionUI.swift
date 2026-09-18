import SwiftUI

// MARK: - AccessionSmartField（首页智能识别框）

/// 粘贴任意 accession / DOI / 基因符号，提交后发布 `.smartRoute` 通知，
/// 由 ContentView 负责识别并路由（或直接跳转，或弹窗选择）。
struct AccessionSmartField: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            HStack(spacing: Theme.sp2) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                Text(L10n.t(.smartIdentify))
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.ink3)
                    .textCase(.uppercase)
                    .tracking(Theme.trackSection)
            }

            HStack(spacing: Theme.sp2) {
                Image(systemName: "paintbrush.pointed")
                    .foregroundColor(Theme.ink3)
                    .font(.system(size: 13))

                TextField(L10n.t(.smartFieldPlaceholder), text: $text)
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
                    Text(L10n.t(.identifyAndOpen))
                        .font(.system(size: Theme.fsBody, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.sp4)
                        .padding(.vertical, Theme.sp1 + 2)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(L10n.t(.identifyAndOpen))
            }
            .padding(.horizontal, Theme.sp4)
            .padding(.vertical, Theme.sp3)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLg)
                    .strokeBorder(isFocused ? Theme.accent.opacity(0.4) : Theme.line, lineWidth: 0.5)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)

            Text(L10n.t(.smartFieldHint))
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.ink3)
        }
        .padding(.horizontal, Theme.sp6)
        // P1-6：首页 ⌘F 聚焦智能识别框
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NotificationCenter.default.post(
            name: .smartRoute,
            object: nil,
            userInfo: ["input": trimmed]
        )
        isFocused = false
    }
}

// MARK: - AccessionCandidateSheet（歧义选择弹窗）

/// 当识别结果存在歧义时，列出所有候选工具供用户选择。
struct AccessionCandidateSheet: View {
    let matches: [AccessionRouter.Match]
    let onPick: (AccessionRouter.Match) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var registry: ToolRegistry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.sp2) {
                Text(L10n.t(.selectDatabase))
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
                    ForEach(matches) { match in
                        candidateRow(match)
                    }
                }
                .padding(Theme.sp4)
            }
        }
        .frame(width: 460, height: 320)
    }

    private func candidateRow(_ match: AccessionRouter.Match) -> some View {
        let provider = registry.find(id: match.toolId)
        let category = provider?.category
        let color = category.map { Theme.categoryColor($0) } ?? Theme.ink3
        return Button(action: { onPick(match) }) {
            HStack(spacing: Theme.sp3) {
                Image(systemName: provider?.iconName ?? "questionmark")
                    .font(.system(size: 15))
                    .foregroundColor(color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.sp2) {
                        Text(provider?.name ?? match.toolId)
                            .font(.system(size: Theme.fsBody))
                            .foregroundColor(Theme.ink)
                        Spacer()
                        Text(L10n.t(.matchConfidence, Int(match.confidence * 100)))
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.ink3)
                    }
                    Text(match.reason)
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.ink2)
                        .lineLimit(1)
                    Text(L10n.t(.queryLabel2, match.query))
                        .font(.system(size: Theme.fsCaption, design: .monospaced))
                        .foregroundColor(Theme.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.sp3)
            .padding(.vertical, Theme.sp2 + 2)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(L10n.t(.routeTo, provider?.name ?? match.toolId))
    }
}
