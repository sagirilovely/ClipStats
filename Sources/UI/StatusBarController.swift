import AppKit

// MARK: - 分段

struct StatusSegment {
    enum Label {
        case symbol(String)
        case text(String)
        case none
    }

    /// 该分段对应的模块，用于点击命中判定；占位分段为 nil
    let kind: SegmentKind?
    let label: Label
    let lines: [String]
    let templates: [String]

    init(kind: SegmentKind? = nil, label: Label, lines: [String], templates: [String]) {
        self.kind = kind
        self.label = label
        self.lines = lines
        self.templates = templates
    }
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

/// 每个分段一个透明命中视图：由 AppKit 负责命中测试，避免自己算坐标。
private final class SegmentHitView: NSView {
    var kind: SegmentKind?
    var onMouseDown: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func rightMouseDown(with event: NSEvent) { onMouseDown?(event) }
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - 状态栏视图

/// 自绘状态栏：多段文字 + SF Symbols 图标或文字标签，支持固定槽位、双行排列、背景样式。
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

    /// 点击某个模块时回调；nil 表示点在空白 / 内外边距区域
    var onSegmentClick: ((SegmentKind?) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// 仅用于离屏截图自检
    var debugBackgroundColor: NSColor?
    var debugHover = false { didSet { contentView.needsDisplay = true } }

    weak var statusItem: NSStatusItem?

    private let contentView = StatusContentView()
    private var effectView: PassthroughEffectView?
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?
    private var cachedLayout: [SegmentLayout] = []
    private var hitViews: [SegmentHitView] = []

    private struct SegmentLayout {
        let kind: SegmentKind?
        let label: StatusSegment.Label
        let labelWidth: CGFloat
        let lines: [String]
        let lineWidths: [CGFloat]
        let textPart: CGFloat
        let font: NSFont
        var slot: CGFloat { labelWidth + textPart }
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

    /// 双行排列时使用的字号
    private var verticalFont: NSFont {
        let size = min(10, max(8, style.font.pointSize * 0.72))
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: style.font, .foregroundColor: style.textColor ?? NSColor.labelColor]
    }

    private func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: style.textColor ?? NSColor.labelColor]
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

    private func width(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func labelWidth(_ label: StatusSegment.Label) -> CGFloat {
        switch label {
        case .symbol:
            return iconSide + 3
        case .text(let text):
            return width(text, font: style.font) + 4
        case .none:
            return 0
        }
    }

    private func layout(_ segments: [StatusSegment]) -> [SegmentLayout] {
        segments.map { segment in
            let font = segment.lines.count > 1 ? verticalFont : style.font
            let lineWidths = segment.lines.map { width($0, font: font) }
            let templateWidths = segment.templates.map { width($0, font: font) }
            let textPart = max(lineWidths.max() ?? 0, templateWidths.max() ?? 0)
            return SegmentLayout(
                kind: segment.kind,
                label: segment.label,
                labelWidth: labelWidth(segment.label),
                lines: segment.lines,
                lineWidths: lineWidths,
                textPart: textPart,
                font: font
            )
        }
    }

    private func totalWidth(of items: [SegmentLayout]) -> CGFloat {
        var total = style.padding * 2
        for (index, item) in items.enumerated() {
            if index > 0 { total += style.spacing }
            total += item.slot
        }
        return ceil(max(22, total))
    }

    /// 自检：直接用 AppKit 做命中测试，验证点击会落到哪个分段
    func debugHitKinds() -> String {
        stride(from: 2.0, to: bounds.width, by: 24.0).map { x in
            let hit = hitTest(NSPoint(x: x, y: bounds.midY))
            let kind: String
            if let hitView = hit as? SegmentHitView {
                kind = hitView.kind?.rawValue ?? "nil"
            } else if hit === self {
                kind = "self(空白)"
            } else {
                kind = "none"
            }
            return "\(Int(x)):\(kind)"
        }.joined(separator: " ")
    }

    var debugHitViewCount: Int { hitViews.count }

    /// 自检：返回每个分段对应的点击区间
    func debugSegmentRects() -> [(String, NSRect)] {
        var x = style.padding
        var result: [(String, NSRect)] = []
        for (index, item) in cachedLayout.enumerated() {
            if index > 0 { x += style.spacing }
            result.append((item.kind?.rawValue ?? "nil",
                           NSRect(x: x, y: 0, width: item.slot, height: bounds.height)))
            x += item.slot
        }
        return result
    }

    /// 自检：给定分段时的总宽度
    func measuredWidth(for segments: [StatusSegment]) -> CGFloat {
        totalWidth(of: layout(segments))
    }

    func rebuildLayout() {
        cachedLayout = layout(segments)
        let width = totalWidth(of: cachedLayout)
        let height = NSStatusBar.system.thickness
        if let statusItem {
            statusItem.length = width
        }
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        contentView.frame = bounds
        effectView?.frame = backgroundRect()
        rebuildHitAreas()
        contentView.needsDisplay = true
        needsDisplay = true
    }

    /// 为每个分段铺设透明命中视图（AppKit 命中测试，不依赖事件坐标）
    private func rebuildHitAreas() {
        hitViews.forEach { $0.removeFromSuperview() }
        hitViews.removeAll()

        var x = style.padding
        for (index, item) in cachedLayout.enumerated() {
            if index > 0 { x += style.spacing }
            let frame = NSRect(x: x, y: 0, width: max(1, item.slot), height: bounds.height)
            let hitView = SegmentHitView(frame: frame)
            hitView.kind = item.kind
            hitView.onMouseDown = { [weak self] event in
                self?.handleSegmentMouseDown(kind: item.kind, event: event)
            }
            addSubview(hitView)
            hitViews.append(hitView)
            x += item.slot
        }
    }

    private func handleSegmentMouseDown(kind: SegmentKind?, event: NSEvent) {
        if event.modifierFlags.contains(.control) || event.type == .rightMouseDown {
            onRightClick?(event)
            return
        }
        // 状态栏窗口里事件自带坐标并不可靠（实测恒为视图中心），
        // 这里以真实光标位置为准重新判定一次。
        let resolved = kindFromCursor() ?? kind
        recordClick(event: event, kind: resolved)
        onSegmentClick?(resolved)
    }

    /// 用真实光标位置（屏幕坐标）换算成状态栏内的横向位置
    private func kindFromCursor() -> SegmentKind? {
        guard let window = self.window else { return nil }
        let screenX = NSEvent.mouseLocation.x
        let viewInScreen = window.convertToScreen(convert(bounds, to: nil))
        return segmentKind(atX: screenX - viewInScreen.minX)
    }

    override func layout() {
        super.layout()
        contentView.frame = bounds
        effectView?.frame = backgroundRect()
    }

    private func backgroundRect() -> NSRect {
        bounds.insetBy(dx: 1, dy: 2)
    }

    /// 悬停高亮区域：水平内缩不超过内容留白，避免把两端文字切到高亮之外
    private func hoverRect() -> NSRect {
        let horizontalInset = min(2, style.padding)
        return bounds.insetBy(dx: horizontalInset, dy: 3)
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
            if let gradient = NSGradient(starting: NSColor.white.withAlphaComponent(0.16),
                                         ending: NSColor.white.withAlphaComponent(0.04)) {
                gradient.draw(in: path, angle: -90)
            } else {
                NSColor.white.withAlphaComponent(0.08).setFill()
                path.fill()
            }
            NSColor.white.withAlphaComponent(0.28).setStroke()
            path.lineWidth = 0.8
            path.stroke()
        }
    }

    private func drawContent() {
        if isHovered || isPanelOpen || debugHover {
            // 悬停高亮用固定的圆角矩形：不复用背景的 cornerRadius，
            // 否则半径接近高度一半时会退化成椭圆，把两端文字裁掉
            let rect = hoverRect()
            let radius = min(6, rect.height / 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.labelColor.withAlphaComponent(isPanelOpen ? 0.20 : 0.11).setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(isPanelOpen ? 0.26 : 0.15).setStroke()
            path.lineWidth = 0.8
            path.stroke()
        }

        if cachedLayout.count != segments.count {
            cachedLayout = layout(segments)
        }

        var x = style.padding

        for (index, item) in cachedLayout.enumerated() {
            if index > 0 { x += style.spacing }

            switch item.label {
            case .symbol(let name):
                drawSymbol(name, at: NSPoint(x: x, y: (bounds.height - iconSide) / 2))
                x += iconSide + 3
            case .text(let text):
                let attrs = attributes(style.font)
                let size = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2),
                                        withAttributes: attrs)
                x += size.width + 4
            case .none:
                break
            }

            if !item.lines.isEmpty {
                drawLines(item, at: x)
                x += item.textPart
            }
        }
    }

    private func drawLines(_ item: SegmentLayout, at x: CGFloat) {
        let attrs = attributes(item.font)

        if item.lines.count == 1 {
            let text = item.lines[0]
            let size = (text as NSString).size(withAttributes: attrs)
            let leftover = max(0, item.textPart - item.lineWidths[0])
            let offset: CGFloat
            switch style.alignment {
            case .center: offset = leftover / 2
            case .trailing: offset = leftover
            }
            (text as NSString).draw(at: NSPoint(x: x + offset, y: (bounds.height - size.height) / 2),
                                    withAttributes: attrs)
            return
        }

        // 双行：第一行在上，第二行在下
        let font = item.font
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let total = lineHeight * CGFloat(item.lines.count)
        let startY = max(0, (bounds.height - total) / 2) + 0.5

        for (lineIndex, text) in item.lines.enumerated() {
            let size = (text as NSString).size(withAttributes: attrs)
            let leftover = max(0, item.textPart - (item.lineWidths[safe: lineIndex] ?? size.width))
            let offset: CGFloat
            switch style.alignment {
            case .center: offset = leftover / 2
            case .trailing: offset = leftover
            }
            let y = startY + CGFloat(item.lines.count - 1 - lineIndex) * lineHeight
            (text as NSString).draw(
                at: NSPoint(x: x + offset, y: y + (lineHeight - size.height) / 2),
                withAttributes: attrs
            )
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
            return
        }
        // 只有点击落在分段之间的空白/内边距时才会走到这里
        let kind = kindFromCursor() ?? segmentKind(atX: viewCoordinateX(for: event))
        recordClick(event: event, kind: kind)
        onSegmentClick?(kind)
    }

    /// 用屏幕坐标换算点击位置，避免状态栏窗口内边距带来的坐标偏移
    private func viewCoordinateX(for event: NSEvent) -> CGFloat {
        guard let window = self.window else {
            return convert(event.locationInWindow, from: nil).x
        }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        let viewInWindow = convert(bounds, to: nil)
        let viewInScreen = window.convertToScreen(viewInWindow)
        return screenPoint.x - viewInScreen.minX
    }

    /// 命中测试：菜单栏是一维的，只比较横向位置。
    /// 纵向不参与判断（状态栏窗口比视图高，点击可能落在视图上下边界之外）。
    private func segmentKind(atX rawX: CGFloat) -> SegmentKind? {
        guard !cachedLayout.isEmpty else { return nil }

        let clamped = min(max(rawX, 0), bounds.width)
        var x = style.padding

        for (index, item) in cachedLayout.enumerated() {
            if index > 0 { x += style.spacing }
            let maxX = x + item.slot
            if clamped >= x && clamped < maxX {
                return item.kind
            }
            x = maxX
        }

        // 落在左右边缘留白里，归为最近的一段
        if clamped >= x { return cachedLayout.last?.kind }
        if clamped < style.padding { return cachedLayout.first?.kind }
        return nil
    }

    /// 临时诊断：把每次点击的坐标与命中结果写入 /tmp/clipstats-clicks.log
    private func recordClick(event: NSEvent, kind: SegmentKind?) {
        guard ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" else { return }
        let frames = debugSegmentRects()
            .map { "\($0.0):[\(Int($0.1.minX))-\(Int($0.1.maxX))]" }
            .joined(separator: ",")
        let screenX = NSEvent.mouseLocation.x
        let viewInScreen = window.map { $0.convertToScreen(convert(bounds, to: nil)) }
        let localX = viewInScreen.map { screenX - $0.minX } ?? -999
        let line = "\(Date()) kind=\(kind?.rawValue ?? "nil") "
            + "localX=\(String(format: "%.1f", localX)) mouseX=\(String(format: "%.1f", screenX)) "
            + "viewScreenMinX=\(String(format: "%.1f", viewInScreen?.minX ?? -1)) "
            + "bounds=\(bounds.size)\n    frames=\(frames)\n"

        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/clipstats-clicks.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 控制器

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let view: StatusItemView
    private let settingsStore: SettingsStore

    private var snapshot = MetricsSnapshot()
    private var clipboardCount = 0

    /// 点击状态栏分段：kind 为命中的模块（nil = 空白区域），anchor 为状态栏项在屏幕上的位置
    var onSegmentClick: ((SegmentKind?, NSRect) -> Void)?

    init(settingsStore: SettingsStore, menuProvider: @escaping (NSEvent) -> NSMenu?) {
        self.settingsStore = settingsStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        view = StatusItemView()
        statusItem.view = view
        view.statusItem = statusItem
        view.style = Self.makeStyle(settingsStore.settings)

        view.onSegmentClick = { [weak self] kind in
            guard let self else { return }
            let anchor = self.view.window?.frame ?? .zero
            self.onSegmentClick?(kind, anchor)
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

    func setDebugHover(_ hovering: Bool) {
        view.debugHover = hovering
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
            let label: StatusSegment.Label
            switch config.labelMode {
            case .symbol: label = .symbol(config.kind.symbolName)
            case .text: label = .text(config.kind.textLabel)
            case .none: label = .none
            }

            var lines: [String] = []
            var templates: [String] = []
            if config.showText {
                lines = valueLines(for: config.kind, snapshot: snapshot, count: count, settings: settings)
                if settings.stabilizeBarWidth {
                    templates = templateLines(for: config.kind, settings: settings)
                }
            }

            segments.append(StatusSegment(kind: config.kind, label: label, lines: lines, templates: templates))
        }

        if segments.isEmpty {
            segments = [StatusSegment(label: .symbol("chart.bar"), lines: [], templates: [])]
        }
        return segments
    }

    /// 自检：给定快照时状态栏应有的宽度
    func width(for snapshot: MetricsSnapshot, count: Int) -> CGFloat {
        let segments = buildSegments(snapshot: snapshot, count: count, settings: settingsStore.settings)
        return view.measuredWidth(for: segments)
    }

    private func templateLines(for kind: SegmentKind, settings: AppSettings) -> [String] {
        switch kind {
        case .cpu:
            return [settings.showCPUWithTemperature ? "100% 100°" : "100%"]
        case .gpu:
            return ["100%"]
        case .memory:
            return ["100%"]
        case .thermal:
            return ["100°"]
        case .network:
            // Fmt.speed 最长输出形如 "84.0K" / "1.15M"（5 个字符），预留同宽
            // 上下排列时上传在上、下载在下
            return settings.networkVertical ? ["↑9.99M", "↓9.99M"] : ["↓9.99M ↑9.99M"]
        case .clipboard:
            return ["999"]
        }
    }

    private func valueLines(for kind: SegmentKind, snapshot: MetricsSnapshot,
                            count: Int, settings: AppSettings) -> [String] {
        switch kind {
        case .cpu:
            var text = Fmt.percent(snapshot.cpu.total)
            if settings.showCPUWithTemperature, let temperature = temperatureValue(settings, snapshot: snapshot) {
                text += " " + Fmt.temperature(temperature)
            }
            return [text]
        case .gpu:
            guard let utilization = snapshot.gpu.utilization else { return ["--"] }
            return [Fmt.percent(utilization)]
        case .memory:
            return [Fmt.percent(snapshot.memory.usage)]
        case .thermal:
            guard let temperature = temperatureValue(settings, snapshot: snapshot) else { return ["--"] }
            return [Fmt.temperature(temperature)]
        case .network:
            let down = "↓\(Fmt.speed(snapshot.network.download))"
            let up = "↑\(Fmt.speed(snapshot.network.upload))"
            return settings.networkVertical ? [up, down] : ["\(down) \(up)"]
        case .clipboard:
            return ["\(count)"]
        }
    }

    private func temperatureValue(_ settings: AppSettings, snapshot: MetricsSnapshot) -> Double? {
        settings.temperatureMode == .maximum
            ? snapshot.thermal.cpuTemperature
            : snapshot.thermal.cpuTemperatureAverage
    }
}
