import SwiftUI
import AppKit

// MARK: - 原生毛玻璃背景 (NSVisualEffectView 桥接)

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // 避免重复赋值引发整块模糊背景重新合成。
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.state != state { nsView.state = state }
    }
}

// MARK: - 浮窗出现 / 收起动画（液态玻璃「展开」手感）

/// 浮窗从锚点方向轻轻「胀开」并淡入，收起时反向。
/// 真正的 matchedGeometry 玻璃形变要求两个状态在同一个窗口里，独立 NSPanel 做不到，
/// 所以这里用同样的弹簧参数模拟「玻璃材料化」的手感：缩放幅度克制，只做 0.96 → 1。
enum PanelPresentation {
    /// 每个窗口一个递增 token：收起动画延迟执行期间如果又被打开，旧的 orderOut 会被丢弃
    private static var tokens: [ObjectIdentifier: Int] = [:]

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @discardableResult
    private static func bumpToken(_ window: NSWindow) -> Int {
        let key = ObjectIdentifier(window)
        let next = (tokens[key] ?? 0) + 1
        tokens[key] = next
        return next
    }

    static func present(_ window: NSWindow) {
        bumpToken(window)
        // 面板已经在屏幕上（例如切换状态栏模块时重新调用 show）：只保证置前，不重播展开动画，
        // 否则每次切换都会缩放淡入一次，看起来像整块面板闪了一下。
        guard !window.isVisible else {
            window.orderFront(nil)
            return
        }
        window.orderFront(nil)
        guard !reduceMotion, let layer = window.contentView?.layer else { return }
        layer.transform = CATransform3DIdentity
        layer.opacity = 1

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(0.96, 0.96, 1))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.mass = 1
        spring.stiffness = 260
        spring.damping = 20
        spring.initialVelocity = 1.2
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "clipstats.present.scale")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "clipstats.present.fade")
    }

    static func dismiss(_ window: NSWindow, completion: (() -> Void)? = nil) {
        let token = bumpToken(window)
        guard !reduceMotion, let layer = window.contentView?.layer else {
            window.orderOut(nil)
            completion?()
            return
        }
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        shrink.toValue = NSValue(caTransform3D: CATransform3DMakeScale(0.97, 0.97, 1))
        shrink.duration = 0.12
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(shrink, forKey: "clipstats.dismiss.scale")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(fade, forKey: "clipstats.dismiss.fade")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard tokens[ObjectIdentifier(window)] == token else { return }
            window.orderOut(nil)
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
            completion?()
        }
    }
}

// MARK: - 界面主题

extension InterfaceAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - 玻璃几何（同心圆角）

/// HIG：嵌套圆角要「同心」——内圆角 = 外圆角 − 内边距，
/// 否则内层会显得过尖（pinched）或外张（flared）。
enum LiquidGlassMetrics {
    /// 浮窗面板圆角
    static let panelRadius: CGFloat = 20

    /// 与面板同心：内边距 inset 处的圆角
    static func concentric(inset: CGFloat, outer: CGFloat = panelRadius, minimum: CGFloat = 8) -> CGFloat {
        max(minimum, outer - inset)
    }
}

// MARK: - 液态玻璃色彩系统

enum LiquidGlassStyle {
    /// 玻璃外缘使用非对称高光，模拟弧面倒角而不是普通白色边框。
    static func rimStrokeGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.48), location: 0.0),
                    .init(color: .white.opacity(0.16), location: 0.30),
                    .init(color: .white.opacity(0.035), location: 0.72),
                    .init(color: .white.opacity(0.18), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(0.95), location: 0.0),
                .init(color: .white.opacity(0.52), location: 0.28),
                .init(color: .black.opacity(0.055), location: 0.74),
                .init(color: .white.opacity(0.64), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardRimStroke(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [.white.opacity(0.20), .white.opacity(0.045), .white.opacity(0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [.white.opacity(0.90), .black.opacity(0.035), .white.opacity(0.48)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surfaceGloss(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(scheme == .dark ? 0.13 : 0.38), location: 0.0),
                .init(color: .white.opacity(scheme == .dark ? 0.035 : 0.10), location: 0.38),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func divider(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                .clear,
                scheme == .dark ? .white.opacity(0.13) : .black.opacity(0.075),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x64D2FF), Color(hex: 0x0A84FF), Color(hex: 0x7D7AFF)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 带环境光泽的玻璃背景

struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var material: NSVisualEffectView.Material = .popover

    var body: some View {
        ZStack {
            VisualEffectView(material: material, blendingMode: .behindWindow, state: .active)

            // 保留桌面内容的可见度，同时为文字提供稳定的对比度。
            Color(nsColor: .windowBackgroundColor)
                .opacity(colorScheme == .dark ? 0.40 : 0.13)

            // 极轻的环境色让模糊层有纵深，不使用大面积浓色渐变。
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0x64D2FF).opacity(colorScheme == .dark ? 0.20 : 0.14),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 28)
                .offset(x: -125, y: -175)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xBF5AF2).opacity(colorScheme == .dark ? 0.14 : 0.085),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 34)
                .offset(x: 155, y: 185)

            LiquidGlassStyle.surfaceGloss(for: colorScheme)
        }
    }
}

// MARK: - 液态玻璃容器修饰器

struct LiquidGlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    /// 系统「降低透明度」开启时自动退回不透明底，保证可读性（HIG 要求）
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = 20

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // .glassEffect 需要 Xcode 26（Swift 6.2）及以上的 SDK；用旧 SDK 构建（例如 CI 的
        // macos-15 runner）时必须在编译期整体降级，否则连编译都过不去。
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            // macOS 26+：真正的液态玻璃，折射 / 边缘高光 / 焦点感知都交给系统，
            // 我们只补一条 hairline 保证边界清晰（不再叠第二层玻璃或自定义渐变）。
            content
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.34),
                        lineWidth: 0.5
                    )
                )
        } else {
            legacyBody(content: content, shape: shape)
        }
        #else
        legacyBody(content: content, shape: shape)
        #endif
    }

    /// macOS 25 及更早 / 旧 SDK：NSVisualEffectView + 自定义描边
    private func legacyBody(content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(
                GlassBackdrop(material: colorScheme == .dark ? .hudWindow : .popover)
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(LiquidGlassStyle.rimStrokeGradient(for: colorScheme), lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(0, cornerRadius - 1), style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.045 : 0.22), lineWidth: 0.5)
                    .padding(1)
            )
        // 浮层阴影由 NSPanel 统一绘制，避免列表滚动时反复离屏合成。
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 14
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                ZStack {
                    shape.fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(colorScheme == .dark ? (isHovered ? 0.48 : 0.32) : (isHovered ? 0.66 : 0.44))
                    )
                    if isHovered {
                        shape.fill(Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.065))
                    }
                    LiquidGlassStyle.surfaceGloss(for: colorScheme)
                        .opacity(isHovered ? 0.9 : 0.58)
                }
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isHovered ? LiquidGlassStyle.rimStrokeGradient(for: colorScheme) : LiquidGlassStyle.cardRimStroke(for: colorScheme),
                    lineWidth: isHovered ? 0.9 : 0.65
                )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.14 : 0.045),
                radius: isHovered ? 7 : 3,
                x: 0,
                y: isHovered ? 3 : 1
            )
            .animation(.easeOut(duration: 0.18), value: isHovered)
    }
}

struct LiquidGlassControlModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 11
    var isActive: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                ZStack {
                    shape.fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.44 : 0.48)
                    )
                    LiquidGlassStyle.surfaceGloss(for: colorScheme).opacity(0.55)
                }
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isActive ? Color.accentColor.opacity(0.58) : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055),
                    lineWidth: isActive ? 1.2 : 0.65
                )
            )
            .overlay(
                shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.09 : 0.48), lineWidth: 0.55)
                    .padding(0.7)
            )
    }
}

// MARK: - 按钮与主题快捷切换

struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    if prominent {
                        LiquidGlassStyle.accentGradient
                    } else {
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.30 : 0.50)
                        Color.primary.opacity(configuration.isPressed ? 0.09 : 0.015)
                        LiquidGlassStyle.surfaceGloss(for: colorScheme).opacity(0.7)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        prominent ? AnyShapeStyle(Color.white.opacity(0.34)) : AnyShapeStyle(LiquidGlassStyle.cardRimStroke(for: colorScheme)),
                        lineWidth: 0.7
                    )
            )
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LiquidGlassIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            // macOS 26 起让按钮自己变成一块可交互的系统玻璃（等价于 .buttonStyle(.glass)，
            // 但保留我们固定的 29×29 圆形尺寸与按下缩放）
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.82))
                .frame(width: 29, height: 29)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            legacyBody(configuration: configuration)
        }
        #else
        legacyBody(configuration: configuration)
        #endif
    }

    private func legacyBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.82))
            .frame(width: 29, height: 29)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.48 : 0.48))
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        configuration.isPressed
                            ? AnyShapeStyle(Color.accentColor.opacity(0.55))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [.white.opacity(0.24), .white.opacity(0.07)]
                                        : [.white.opacity(0.90), .black.opacity(0.045)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ),
                        lineWidth: 0.75
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppearanceModeButton: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            let next: InterfaceAppearance = colorScheme == .dark ? .light : .dark
            store.set { $0.interfaceAppearance = next }
        } label: {
            Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.stars.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(LiquidGlassIconButtonStyle())
        .help(colorScheme == .dark ? "切换浅色模式" : "切换夜览模式")
        .accessibilityLabel(colorScheme == .dark ? "切换浅色模式" : "切换夜览模式")
    }
}

// MARK: - View 扩展

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassCard(cornerRadius: CGFloat = 14, isHovered: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, isHovered: isHovered))
    }

    func liquidGlassControl(cornerRadius: CGFloat = 11, isActive: Bool = false) -> some View {
        modifier(LiquidGlassControlModifier(cornerRadius: cornerRadius, isActive: isActive))
    }
}
