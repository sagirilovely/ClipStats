import AppKit

// MARK: - 分段

struct StatusSegment {
    let symbol: String?
    let text: String
    /// 预留宽度的参考串（数值变化时不改变栏宽）
    let template: String
}

// MARK: - 外观配置

struct BarStyle {
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    var iconPointSize: CGFloat = 11
    var spacing: CGFloat = 6
    var padding: CGFloat = 6
    var alignment: BarTextAlignment = .center
    var backgroundStyle: BarBackgroundStyle = .none
    var backgroundColor: NSColor = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 0.35)
    var cornerRadius: CGFloat = 6
    /// nil 表示跟随系统菜单栏颜色
    var textColor: NSColor?
}

// MARK: - 子视图

private final class PassthroughEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class StatusContentView: NSView {
    var onDraw: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) { onDraw?() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 状态栏视图

/// 自绘状态栏：多段文字 + SF Symbols，固定槽位宽度，可选纯色 / 毛玻璃背景。
final class StatusItemView: NSView {
    var style = BarStyle() {
        didSet { applyStyle() }
    }

    var segments: [StatusSegment] = [] {
        didSet { rebuildLayout() }
    }

    var isPanelOpen = false {
        didSet {
            contentView.needsDisplay = true
            needsDisplay = true
        }
    }

    var onLeftClick: ((NSEvent) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// 仅用于离屏截图自检
    var debugBackgroundColor: NSColor?

    weak var statusItem: NSStatusItem?

    private let contentView = StatusContentView()
    private var effectView: PassthroughEffectView?
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?
    private var cachedLayout: [SegmentLayout] = []

    private struct SegmentLayout {
        let symbol: String?
        let text: String
        let symbolPart: CGFloat
        let textPart: CGFloat
        let actualTextWidth: CGFloat
        var slot: CGFloat { symbolPart + textPart }
    }

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        contentView.onDraw = { [weak self] in self?.drawContent() }
        addSubview(contentView)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    private var iconSide: CGFloat { max(10, style.iconPointSize + 3) }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: style.font, .foregroundColor: style.textColor ?? NSColor.labelColor]
    }

    private func applyStyle() {
        if let effectView {
            effectView.removeFromSuperview()
            self.effectView = nil
        }
        if style.backgroundStyle == .glass {
            let effect = PassthroughEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = style.cornerRadius
            effect.layer?.masksToBounds = true
            addSubview(effect, positioned: .below, relativeTo: contentView)
            effectView = effect
        }
        rebuildLayout()
    }

    // MARK: - 布局

    private func textWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: textAttributes).width)
    }

    private func layout(_ segments: [StatusSegment]) -> [SegmentLayout] {
        segments.map { segment in
            let actual = textWidth(segment.text)
            let template = textWidth(segment.template)
            let symbolPart: CGFloat = segment.symbol == nil ? 0 : iconSide + 3
            return SegmentLayout(
                symbol: segment.symbol,
                text: segment.text,
                symbolPart: symbolPart,
                textPart: max(actual, template),
                actualTextWidth: actual
            )
        }
    }

    private func width(of items: [SegmentLayout]) -> CGFloat {
        var total = style.padding * 2
        for (index, item) in items.enumerated() {
            if index > 0 { total += style.spacing }
            total += item.slot
        }
        return ceil(max(22, total))
    }

    /// 自检：给定分段时的总宽度
    func measuredWidth(for segments: [StatusSegment]) -> CGFloat {
        width(of: layout(segments))
    }

    func rebuildLayout() {
        cachedLayout = layout(segments)
        let width = width(of: cachedLayout)
        let height = NSStatusBar.system.thickness
        if let statusItem {
            statusItem.length = width
        }
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        contentView.frame = bounds
        effectView?.frame = backgroundRect()
        contentView.needsDisplay = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        contentView.frame = bounds
        effectView?.frame = backgroundRect()
    }

    private func backgroundRect() -> NSRect {
        bounds.insetBy(dx: 1, dy: 2)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        if let debugBackgroundColor {
            debugBackgroundColor.setFill()
            bounds.fill()
        }
        drawBackground()
    }

    private func drawBackground() {
        guard style.backgroundStyle != .none else { return }
        let rect = backgroundRect()
        let path = NSBezierPath(roundedRect: rect, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        switch style.backgroundStyle {
        case .none:
            break
        case .solid:
            style.backgroundColor.setFill()
            path.fill()
        case .glass:
            NSColor.black.withAlphaComponent(0.06).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.14).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawContent() {
        if isHovered || isPanelOpen {
            NSColor.labelColor.withAlphaComponent(isPanelOpen ? 0.22 : 0.12).setFill()
            NSBezierPath(roundedRect: backgroundRect(), xRadius: style.cornerRadius,
                         yRadius: style.cornerRadius).fill()
        }

        if cachedLayout.count != segments.count {
            cachedLayout = layout(segments)
        }

        let attributes = textAttributes
        var x = style.padding

        for (index, item) in cachedLayout.enumerated() {
            if index > 0 { x += style.spacing }

            if let symbol = item.symbol {
                drawSymbol(symbol, at: NSPoint(x: x, y: (bounds.height - iconSide) / 2))
                x += iconSide + 3
            }

            if !item.text.isEmpty {
                let size = (item.text as NSString).size(withAttributes: attributes)
                let leftover = max(0, item.textPart - item.actualTextWidth)
                let offset: CGFloat
                switch style.alignment {
                case .center: offset = leftover / 2
                case .trailing: offset = leftover
                }
                let origin = NSPoint(x: x + offset, y: (bounds.height - size.height) / 2)
                (item.text as NSString).draw(at: origin, withAttributes: attributes)
                x += item.textPart
            }
        }
    }

    private func drawSymbol(_ name: String, at point: NSPoint) {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: style.iconPointSize, weight: .regular)
        let image = base.withSymbolConfiguration(configuration) ?? base
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }

        // 必须在独立画布里着色：直接在当前上下文中 sourceAtop 会把整块矩形涂满
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        (style.textColor ?? NSColor.labelColor).set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let rect = NSRect(x: point.x + (iconSide - size.width) / 2,
                          y: point.y + (iconSide - size.height) / 2,
                          width: size.width, height: size.height)
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: false, hints: nil)
    }

    // MARK: - 交互

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                 options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        contentView.needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        contentView.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?(event)
        } else {
            onLeftClick?(event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

// MARK: - 控制器

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let view: StatusItemView
    private let settingsStore: SettingsStore

    private var snapshot = MetricsSnapshot()
    private var clipboardCount = 0

    var onTogglePanel: ((NSRect) -> Void)?

    init(settingsStore: SettingsStore, menuProvider: @escaping (NSEvent) -> NSMenu?) {
        self.settingsStore = settingsStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        view = StatusItemView()
        statusItem.view = view
        view.statusItem = statusItem
        view.style = Self.makeStyle(settingsStore.settings)

        view.onLeftClick = { [weak self] _ in
            guard let self else { return }
            let anchor = self.view.window?.frame ?? .zero
            self.onTogglePanel?(anchor)
        }
        let localView = view
        view.onRightClick = { event in
            if let menu = menuProvider(event) {
                NSMenu.popUpContextMenu(menu, with: event, for: localView)
            }
        }

        render()
    }

    var statusView: NSView { view }

    func setDebugBackground(_ color: NSColor?) {
        view.debugBackgroundColor = color
        view.needsDisplay = true
    }

    var anchorFrame: NSRect {
        view.window?.frame ?? NSRect(x: 0, y: NSScreen.main?.frame.maxY ?? 900, width: 200, height: 24)
    }

    func setPanelOpen(_ open: Bool) {
        view.isPanelOpen = open
    }

    func update(_ snapshot: MetricsSnapshot) {
        self.snapshot = snapshot
        render()
    }

    func updateClipboardCount(_ count: Int) {
        clipboardCount = count
        render()
    }

    func applySettings() {
        view.style = Self.makeStyle(settingsStore.settings)
        render()
    }

    static func makeStyle(_ settings: AppSettings) -> BarStyle {
        let appearance = settings.appearance
        var style = BarStyle()
        style.font = .monospacedDigitSystemFont(ofSize: settings.barFontSize, weight: .regular)
        style.iconPointSize = CGFloat(appearance.iconPointSize)
        style.spacing = CGFloat(appearance.segmentSpacing)
        style.padding = CGFloat(appearance.horizontalPadding)
        style.alignment = appearance.textAlignment
        style.backgroundStyle = appearance.backgroundStyle
        style.backgroundColor = ColorHex.nsColor(appearance.backgroundColor)
            .withAlphaComponent(CGFloat(appearance.backgroundOpacity))
        style.cornerRadius = CGFloat(appearance.cornerRadius)
        style.textColor = appearance.useCustomTextColor ? ColorHex.nsColor(appearance.textColor) : nil
        return style
    }

    // MARK: - 渲染

    private func render() {
        let settings = settingsStore.settings
        view.segments = buildSegments(snapshot: snapshot, count: clipboardCount, settings: settings)
    }

    func buildSegments(snapshot: MetricsSnapshot, count: Int, settings: AppSettings) -> [StatusSegment] {
        var segments: [StatusSegment] = []
        for config in settings.segments where config.enabled {
            let text = valueText(for: config.kind, snapshot: snapshot, count: count, settings: settings)
            let template = (config.showText && settings.stabilizeBarWidth)
                ? templateText(for: config.kind, settings: settings)
                : ""
            segments.append(StatusSegment(
                symbol: config.showIcon ? config.kind.symbolName : nil,
                text: config.showText ? text : "",
                template: template
            ))
        }
        if segments.isEmpty {
            segments = [StatusSegment(symbol: "chart.bar", text: "", template: "")]
        }
        return segments
    }

    /// 自检：给定快照时状态栏应有的宽度
    func width(for snapshot: MetricsSnapshot, count: Int) -> CGFloat {
        let segments = buildSegments(snapshot: snapshot, count: count, settings: settingsStore.settings)
        return view.measuredWidth(for: segments)
    }

    private func templateText(for kind: SegmentKind, settings: AppSettings) -> String {
        switch kind {
        case .cpu:
            return settings.showCPUWithTemperature ? "100% 100°" : "100%"
        case .gpu:
            return "100%"
        case .memory:
            return "100%"
        case .thermal:
            return "100°"
        case .network:
            // Fmt.speed 最长输出形如 "84.0K" / "1.15M"（5 个字符），预留同宽
            return "↓9.99M ↑9.99M"
        case .clipboard:
            return "999"
        }
    }

    private func valueText(for kind: SegmentKind, snapshot: MetricsSnapshot,
                           count: Int, settings: AppSettings) -> String {
        switch kind {
        case .cpu:
            var text = Fmt.percent(snapshot.cpu.total)
            if settings.showCPUWithTemperature, let temperature = temperatureValue(settings, snapshot: snapshot) {
                text += " " + Fmt.temperature(temperature)
            }
            return text
        case .gpu:
            guard let utilization = snapshot.gpu.utilization else { return "--" }
            return Fmt.percent(utilization)
        case .memory:
            return Fmt.percent(snapshot.memory.usage)
        case .thermal:
            guard let temperature = temperatureValue(settings, snapshot: snapshot) else { return "--" }
            return Fmt.temperature(temperature)
        case .network:
            return "↓\(Fmt.speed(snapshot.network.download)) ↑\(Fmt.speed(snapshot.network.upload))"
        case .clipboard:
            return "\(count)"
        }
    }

    private func temperatureValue(_ settings: AppSettings, snapshot: MetricsSnapshot) -> Double? {
        settings.temperatureMode == .maximum
            ? snapshot.thermal.cpuTemperature
            : snapshot.thermal.cpuTemperatureAverage
    }
}
