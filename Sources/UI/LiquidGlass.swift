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
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                GlassBackdrop(material: colorScheme == .dark ? .hudWindow : .popover)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LiquidGlassStyle.rimStrokeGradient(for: colorScheme), lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.82))
            .frame(width: 27, height: 27)
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
