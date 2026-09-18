import SwiftUI
import AppKit

// MARK: - Theme (Minimal Design System)

/// 极简设计系统：纯色背景、细线分割、大留白、零阴影、单色强调。
/// 灵感来自 Notion / Linear / Things 的克制美学。
enum Theme {
    // MARK: - Spacing (generous whitespace)
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 20
    static let sp6: CGFloat = 24
    static let sp8: CGFloat = 32

    // MARK: - Font sizes (compact, refined)
    // P3-2：fsMicro 与 fsCaption 同为 11，合并为 fsCaption
    static let fsCaption: CGFloat = 11
    static let fsSmall: CGFloat = 12
    static let fsBody: CGFloat = 13
    static let fsHeadline: CGFloat = 16
    static let fsLargeTitle: CGFloat = 22
    static let fsDisplay: CGFloat = 28

    // MARK: - 外观自适应色（P0-5 / P1-2 / P1-3 / P1-4）

    /// 外观自适应的动态色（P0-5 / P1-3 / P1-4：浅色与深色分别取值，杜绝「只调深色」）。
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            let rgb = isDark ? dark : light
            return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    // MARK: - Tracking (size-specific, per Apple Design typography)
    /// Large display text wants negative tracking; small text stays near 0.
    static let trackLarge: CGFloat = -0.5
    static let trackTitle: CGFloat = -0.3
    static let trackSection: CGFloat = 0.8

    // MARK: - Corner radius (soft, minimal)
    static let radiusSm: CGFloat = 4
    static let radiusMd: CGFloat = 6
    static let radiusLg: CGFloat = 8

    // MARK: - Colors (monochrome, adaptive)
    // Text —— 注意 Color.primary 在 macOS 上 = labelColor（alpha 0.847），
    // 有效透明度 = 0.847 × 系数（P1-3：ink3 从 0.55 提到 0.70，浅色下才达 4.5:1）
    static let ink = Color.primary
    static let ink2 = Color.primary.opacity(0.75)
    static let ink3 = Color.primary.opacity(0.70)
    static let ink4 = Color.primary.opacity(0.25)  // decorative only (icons, chevrons, dividers) — never for information text
    static let inkSource = Color.primary.opacity(0.70)  // data source / compliance notes

    // Surfaces（与窗口底色形成可辨识层级，P0-5）
    static let cardBackground = adaptive(light: (0.937, 0.937, 0.937), dark: (0.165, 0.165, 0.165))
    static let sidebarBackground = adaptive(light: (0.965, 0.965, 0.965), dark: (0.11, 0.11, 0.11))

    // Lines（slightly stronger for column/section separation by luminance difference）
    static let line = Color.primary.opacity(0.12)
    static let lineStrong = Color.primary.opacity(0.18)
    static let divider = Color.primary.opacity(0.15)       // main dividers (list/column separators)
    static let dividerSoft = Color.primary.opacity(0.10)   // soft row-internal dividers

    // Accent — 压暗到白字 ≥ 4.5:1（P1-2：#2194D9 白字仅 3.33:1，改 #1773B8）
    static let accent = Color(red: 0.09, green: 0.45, blue: 0.72)

    // 焦点环（P1-1）：用实色 accent + 2pt，不再用半透明 0.5
    static let focusRing = accent
    static let focusRingWidth: CGFloat = 2

    // MARK: - Brand gradient (for logo / header)
    static let brandGradient = LinearGradient(
        colors: [accent, Color(red: 0.15, green: 0.65, blue: 0.65)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic feedback colors（P1-3：浅色加深、深色提亮，两种模式作文本都 ≥ 4.5:1）
    static let semanticError   = adaptive(light: (0.72, 0.16, 0.14), dark: (0.85, 0.30, 0.28))
    static let semanticWarning = adaptive(light: (0.62, 0.35, 0.05), dark: (0.85, 0.55, 0.20))
    static let semanticSuccess = adaptive(light: (0.13, 0.45, 0.25), dark: (0.22, 0.68, 0.40))
    /// Darker warning for backgrounds with white text (WCAG AA ≥ 4.5:1)
    static let warningBanner = Color(red: 0.60, green: 0.35, blue: 0.10)

    // MARK: - Category accent (themed, low-saturation brand colors)
    // 分类与物种=蓝, 基因与序列=绿, 蛋白与结构=橙, 功能与通路=青, 文献=紫
    // Colors are adaptive: dark-mode variants are brightened for WCAG AA contrast.
    static func categoryColor(_ cat: ToolCategory) -> Color {
        let (l, d) = categoryRGB(cat)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            let rgb = isDark ? d : l
            return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    private static func categoryRGB(_ cat: ToolCategory) -> (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) {
        // P1-4：浅色变体压暗至作文本 ≥ 4.5:1；深色保持已提亮的值
        switch cat {
        case .taxonomy:         return ((0.10, 0.38, 0.68), (0.35, 0.62, 0.95))
        case .gene:             return ((0.13, 0.45, 0.25), (0.30, 0.75, 0.50))
        case .protein:          return ((0.72, 0.38, 0.05), (0.95, 0.65, 0.30))
        case .functionCategory: return ((0.05, 0.45, 0.45), (0.25, 0.75, 0.75))
        case .literature:       return ((0.52, 0.28, 0.66), (0.70, 0.45, 0.85))
        }
    }

    // MARK: - Sidebar-specific helpers
    /// 悬浮态浅色背景
    static let hoverBackground = Color.primary.opacity(0.06)
}

// MARK: - Sidebar Density

enum SidebarDensity: String, CaseIterable {
    case compact = "compact"
    case normal = "normal"
    case spacious = "spacious"

    var name: String {
        switch self {
        case .compact: L10n.t(.densityCompact)
        case .normal: L10n.t(.densityNormal)
        case .spacious: L10n.t(.densitySpacious)
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .compact: 12
        case .normal: 13
        case .spacious: 14
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .compact: 11
        case .normal: 12
        case .spacious: 14
        }
    }

    var iconFrame: CGFloat {
        switch self {
        case .compact: 16
        case .normal: 18
        case .spacious: 20
        }
    }

    var hSpacing: CGFloat {
        switch self {
        case .compact: 6
        case .normal: 8
        case .spacious: 10
        }
    }

    /// 最小行高（作为下限，承接系统辅助功能字号缩放）
    var minRowHeight: CGFloat {
        switch self {
        case .compact: 26
        case .normal: 30
        case .spacious: 36
        }
    }

    /// 子项缩进量
    var indent: CGFloat {
        switch self {
        case .compact: 10
        case .normal: 12
        case .spacious: 14
        }
    }

    /// 侧边栏整体左内边距
    var sidebarPadding: CGFloat {
        switch self {
        case .compact: 8
        case .normal: 10
        case .spacious: 12
        }
    }
}

// MARK: - App Logo View (loads AppIcon from bundle resources)

/// 从 bundle 资源加载实际 App 图标，用于界面内部品牌展示。
/// 在 .app 打包后从 Resources/AppIcon_1024.png 加载；
/// 在 SwiftPM 直接运行时回退到品牌渐变 + flask 图标。
struct AppLogoView: View {
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let img = loadAppIcon() {
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // 回退：品牌渐变 + flask 图标
                RoundedRectangle(cornerRadius: Theme.radiusSm)
                    .fill(Theme.brandGradient)
                    .overlay(
                        Image(systemName: "flask")
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private func loadAppIcon() -> Image? {
        // 1. 尝试从 .app 主 bundle 的 Resources 目录加载（打包后）
        if let bundleURL = Bundle.main.url(forResource: "AppIcon_1024", withExtension: "png"),
           let nsImage = NSImage(contentsOf: bundleURL) {
            return Image(nsImage: nsImage)
        }
        // 2. 尝试从 SwiftPM 资源 module bundle 加载（开发时直接运行）
        let moduleBundle = Bundle(for: BundleToken.self)
        if let bundleURL = moduleBundle.url(forResource: "AppIcon_1024", withExtension: "png"),
           let nsImage = NSImage(contentsOf: bundleURL) {
            return Image(nsImage: nsImage)
        }
        // 3. 尝试从 SciToolbox_SciToolbox.bundle 子目录加载
        if let subBundleURL = moduleBundle.url(forResource: "SciToolbox_SciToolbox", withExtension: "bundle"),
           let subBundle = Bundle(url: subBundleURL),
           let resourceURL = subBundle.url(forResource: "AppIcon_1024", withExtension: "png"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        return nil
    }
}

// MARK: - Thin Scrollbar Configuration

/// 全局自定义 NSScroller 外观：使用 overlay 样式 + light knob + small control size，
/// 使滚动条更细、更浅，匹配极简设计系统。
/// 在 App 启动时调用 `ThinScrollbar.apply()` 即可生效。
enum ThinScrollbar {
    static func apply() {
        // overlay 样式：滚动条浮在内容之上，不占空间，仅在滚动/悬停时可见
        // 遍历所有窗口，递归查找 NSScrollView 并设置细滚动条
        for window in NSApp.windows {
            ThinScrollbar.configureScrollViews(in: window.contentView)
        }
    }

    private static func configureScrollViews(in view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.scrollerKnobStyle = .light
            scrollView.verticalScroller?.controlSize = .small
            scrollView.horizontalScroller?.controlSize = .small
        }
        for subview in view.subviews {
            configureScrollViews(in: subview)
        }
    }
}

// MARK: - View Modifiers (minimal: no shadow, thin border)

struct CardBackground: ViewModifier {
    var bordered: Bool = true

    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLg)
                    .strokeBorder(Theme.line, lineWidth: 0.5)
                    .opacity(bordered ? 1 : 0)
            )
    }
}

extension View {
    func cardStyle(bordered: Bool = true) -> some View {
        modifier(CardBackground(bordered: bordered))
    }

    /// Thin divider — main separator (columns, sections)
    func thinDivider() -> some View {
        Divider().opacity(0.5)
    }

    /// Soft divider — row-internal separator (result rows, KV rows)
    func softDivider() -> some View {
        Divider().opacity(0.3)
    }
}

// MARK: - Pressable Button Style (press feedback: scale 0.97 on press)

/// Drop-in replacement for `.buttonStyle(.plain)` that adds subtle press feedback.
/// Applies `scaleEffect(0.97)` with `easeOut(160ms)` — per Apple Design #1 and
/// emil-design-eng's "Buttons must feel responsive" principle.
/// Also provides the missing disabled visual state: custom-styled buttons don't
/// dim automatically on macOS, so disabled actions here render at 35% opacity.
/// Respects `accessibilityReduceMotion`.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

private struct PressableLabel: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.35)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isEnabled)
    }
}

// MARK: - Bundle Token (for SwiftPM resource loading)

/// 用于获取 SwiftPM module bundle 的辅助类。
/// 在 SwiftPM 中，`Bundle(for:)` 需要一个编译时已知的类来定位正确的 bundle。
private final class BundleToken {}
