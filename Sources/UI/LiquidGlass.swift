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
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - 苹果液态玻璃风格色调与渐变

enum LiquidGlassStyle {
    /// 顶部玻璃高光反光边缘（模拟物理弧面玻璃的高光倒角）
    static var rimStrokeGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.48), location: 0.0),
                .init(color: Color.white.opacity(0.22), location: 0.28),
                .init(color: Color.white.opacity(0.08), location: 0.72),
                .init(color: Color.white.opacity(0.26), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 幽微的表面液态光泽渐变
    static var surfaceGloss: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.14), location: 0.0),
                .init(color: Color.white.opacity(0.04), location: 0.35),
                .init(color: Color.clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 卡片高光边缘
    static var cardRimStroke: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.36), location: 0.0),
                .init(color: Color.white.opacity(0.12), location: 0.5),
                .init(color: Color.white.opacity(0.22), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 液态玻璃卡片修饰器

struct LiquidGlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 底层：真实桌面毛玻璃模糊穿透
                    VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)

                    // 浅色模式/深色模式适配半透明衬底
                    Color(nsColor: .windowBackgroundColor).opacity(0.40)

                    // 顶层表面高光反射层
                    LiquidGlassStyle.surfaceGloss
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // 晶莹双层玻璃反光倒角边缘
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LiquidGlassStyle.rimStrokeGradient, lineWidth: 1.0)
            )
            .overlay(
                // 内圈微弱补光线
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    .padding(1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.035))
                    if isHovered {
                        LiquidGlassStyle.surfaceGloss
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHovered ? LiquidGlassStyle.rimStrokeGradient : LiquidGlassStyle.cardRimStroke,
                        lineWidth: isHovered ? 1.0 : 0.6
                    )
            )
            .animation(.easeOut(duration: 0.18), value: isHovered)
    }
}

// MARK: - 交互按钮与小药丸样式

struct LiquidGlassButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    if prominent {
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        prominent ? Color.white.opacity(0.35) : Color.white.opacity(0.15),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    func liquidGlassPanel(cornerRadius: CGFloat = 18) -> some View {
        self.modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassCard(cornerRadius: CGFloat = 12, isHovered: Bool = false) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, isHovered: isHovered))
    }
}
