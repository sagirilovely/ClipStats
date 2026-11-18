import AppKit

// MARK: - 分段

struct StatusSegment {
    enum Label: Equatable {
        case symbol(String)
        case text(String)
        case none
    }

    /// 该分段对应的模块，用于点击命中判定；占位分段为 nil
    let kind: SegmentKind?
    let label: Label
    let lines: [String]
    /// 每行前 N 个字符是固定前缀（网速的 ↑ / ↓）：前缀贴左，数值在槽位内右对齐
    let prefixCount: Int
    /// 固定槽位宽度用的「最宽数值」样本；为空表示不预留（纯 flex 排布）
    let templates: [String]
    /// 给数值加一个圆角徽章底（剪贴板只显示数字且没有单位时用）
    let badge: Bool

    init(kind: SegmentKind? = nil, label: Label, lines: [String],
         prefixCount: Int = 0, templates: [String] = [], badge: Bool = false) {
        self.kind = kind
        self.label = label
        self.lines = lines
        self.prefixCount = prefixCount
        self.templates = templates
        self.badge = badge
    }
}

// MARK: - 外观配置

struct BarStyle {
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    var iconPointSize: CGFloat = 11
    var spacing: CGFloat = 6
    var padding: CGFloat = 6
    var backgroundStyle: BarBackgroundStyle = .none
    var backgroundColor: NSColor = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 0.35)
    var cornerRadius: CGFloat = 6
    /// nil 表示跟随系统菜单栏颜色
    var textColor: NSColor?
    /// 数值跳动时是否保持状态栏宽度稳定（只增不减，收缩延迟执行）
    var stabilizeWidth: Bool = true
}

// MARK: - 子视图

// 状态栏的玻璃胶囊完全自绘：菜单栏本身就是一个玻璃层，
// 再往里塞 NSVisualEffectView / NSGlassEffectView 只会采样到菜单栏自己（≈ 实心），
// 而且系统玻璃的 Auto Layout 还会和 statusItem.length 打架。

private final class StatusContentView: NSView {
    var onDraw: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) { onDraw?() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 每个分段一个透明命中视图：由 AppKit 负责命中测试与鼠标悬停跟踪
private final class SegmentHitView: NSView {
    var index: Int = 0
    var kind: SegmentKind?
    var onMouseDown: ((NSEvent) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        if let window = self.window {
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let viewPoint = convert(windowPoint, from: nil)
            guard bounds.contains(viewPoint) else { return }
        }
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func rightMouseDown(with event: NSEvent) { onMouseDown?(event) }
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - 状态栏视图

/// 自绘状态栏：多段文字 + SF Symbols 图标或文字标签。
/// 排布方式等同 CSS 的 flex + gap：每个模块只占真实文字宽度，模块之间是严格等宽的间距。
final class StatusItemView: NSView {
    var style = BarStyle() {
        didSet {
            // 外观变化（字号、内边距、对齐……）应当立刻生效，不做收缩延迟
            resetStableWidth()
            applyStyle()
        }
    }

    var segments: [StatusSegment] = [] {
        didSet {
            // 只有数值变化时才保留旧宽度；模块增减、标签模式变化属于结构变化，直接贴合
            if !sameShape(segments, oldValue) { resetStableWidth() }
            rebuildLayout()
        }
    }

    var isPanelOpen = false {
        didSet {
            contentView.needsDisplay = true
            needsDisplay = true
        }
    }

    /// 当前处于激活弹出状态的分段（如点击 CPU 打开 CPU 详情面板时，高亮 CPU 分段）
    var activeSegmentKind: SegmentKind? {
        didSet {
            if oldValue != activeSegmentKind {
                contentView.needsDisplay = true
            }
        }
    }

    /// 点击某个模块时回调；nil 表示点在空白 / 内外边距区域
    var onSegmentClick: ((SegmentKind?) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// 仅用于离屏截图自检
    var debugBackgroundColor: NSColor?
    var debugHover = false { didSet { contentView.needsDisplay = true } }
    var debugHoverIndex: Int? { didSet { contentView.needsDisplay = true } }

    weak var statusItem: NSStatusItem?

    private let contentView = StatusContentView()
    private var hoveredIndex: Int? {
        didSet {
            if oldValue != hoveredIndex {
                contentView.needsDisplay = true
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?
    private var cachedLayout: [SegmentLayout] = []
    private var hitViews: [SegmentHitView] = []

    /// 当前真正下发给菜单栏的宽度（开启稳定宽度时会比内容宽一点点）
    private var stableWidth: CGFloat = 0
    /// 延迟收缩的任务，数值持续变小时才真正收窄
    private var pendingShrink: DispatchWorkItem?

    /// 结构是否变化：模块增减、标签模式变化时应当立刻贴合新宽度，不做收缩延迟
    private func sameShape(_ lhs: [StatusSegment], _ rhs: [StatusSegment]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { old, new in
            old.kind == new.kind && old.label == new.label
                && old.badge == new.badge && old.lines.isEmpty == new.lines.isEmpty
        }
    }

    private struct SegmentLayout {
        let kind: SegmentKind?
        let label: StatusSegment.Label
        let badge: Bool
        let rawLabelWidth: CGFloat
        let labelValueGap: CGFloat
        /// 前缀（↑ / ↓）占据的宽度，没有前缀时是 0
        let prefixWidth: CGFloat
        /// 数值槽位宽度：开启「固定总宽度」时按最宽数值预留，否则等于实际最宽行
        let valueSlotWidth: CGFloat
        /// 每行的前缀与数值（前缀贴左、数值在槽位内右对齐）
        let linePrefixes: [String]
        let values: [String]
        /// 徽章里数字的槽位宽度（让胶囊宽度保持恒定）
        let badgeTextSlot: CGFloat
        let font: NSFont

        static let labelValueGapStandard: CGFloat = 2.5

        /// 模块宽度：标签 + 标签数值间距 + 前缀 + 数值槽位。
        /// 数值在槽位里右对齐，所以模块右缘永远与槽位右缘重合——模块之间的间距因此严格等于设置值，
        /// 同时槽位余量藏在「标签 → 数值」之间，不会变成模块右侧的空白。
        var actualContentWidth: CGFloat {
            rawLabelWidth + labelValueGap + prefixWidth + valueSlotWidth
        }

        var lineCount: Int { values.count }

        /// 单行文字高度（多行排列时两行之间的步进也用它）
        var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }
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

    /// 相邻模块之间的最小可见间距。设置里的 0 表示「最紧凑」，
    /// 但仍然保留这点呼吸空间，否则相邻模块的真实文字会直接贴在一起（「48°内存」）。
    static let minimumSegmentGap: CGFloat = 5

    /// 数值变小后，等这么久再收窄状态栏，避免数值来回跳时菜单栏跟着抖。
    /// 必须比采样间隔明显长，否则宽度会在两次采样之间来回伸缩。
    private static let shrinkDelay: TimeInterval = 4

    /// 模块之间的实际间距：严格按设置排布，并兜住最小值。
    /// 这就是 CSS 里的 gap——每个模块后面都留同样的距离，不存在「某个模块右侧多一点」。
    private var gap: CGFloat { max(Self.minimumSegmentGap, style.spacing) }

    /// 背景圆角：超过半高时收敛成胶囊，避免路径退化。
    /// 背景层（vibrancy / 系统玻璃）与自绘描边必须用同一个半径，否则玻璃会从描边外侧漏出来。
    private func cornerRadius(for rect: NSRect) -> CGFloat {
        min(max(2, style.cornerRadius), rect.height / 2)
    }

    /// 左右内边距。开背景时按圆角给出最小留白——胶囊两端是弧线，
    /// 留白不够时首尾字符会压在弧线上，看起来就像「溢出」到背景之外。
    private var sideInset: CGFloat {
        let barHeight = NSStatusBar.system.thickness
        let radius = cornerRadius(for: NSRect(x: 0, y: 0, width: 40, height: barHeight - 4))
        let backgroundMinimum = max(6, ceil(radius * 0.8))
        return max(style.padding, backgroundMinimum)
    }

    /// 可见内容宽度：模块只算真实文字，模块之间严格使用 gap。
    private var contentWidth: CGFloat {
        guard !cachedLayout.isEmpty else { return 0 }
        let total = cachedLayout.reduce(CGFloat(0)) { $0 + $1.actualContentWidth }
        return ceil(total + gap * CGFloat(cachedLayout.count - 1))
    }

    /// 内容起点永远贴左：数值变化只影响自身宽度，不会把整组内容左右推。
    private var contentStartX: CGFloat { sideInset }

    /// 双行排列时使用的字号
    private var verticalFont: NSFont {
        let size = min(10, max(8, style.font.pointSize * 0.72))
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: style.textColor ?? NSColor.labelColor]
    }

    private func applyStyle() {
        if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" {
            NSLog("%@", "DIAG bar style background=\(style.backgroundStyle) color=\(style.backgroundColor) radius=\(style.cornerRadius) padding=\(style.padding) text=\(String(describing: style.textColor))")
        }
        rebuildLayout()
    }

    // MARK: - 布局

    private static let badgeIconWidth: CGFloat = 9.0
    private static let badgeIconHeight: CGFloat = 10.0
    private static let badgePadLeft: CGFloat = 5.0
    private static let badgePadRight: CGFloat = 5.5
    private static let badgeIconTextGap: CGFloat = 3.0

    private var badgeFont: NSFont {
        .monospacedDigitSystemFont(ofSize: 10.0, weight: .semibold)
    }

    /// 徽章里数字部分的宽度（不含图标与内边距）
    private func badgeTextWidth(_ text: String) -> CGFloat {
        width(text, font: badgeFont)
    }

    private func width(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func rawLabelWidth(_ label: StatusSegment.Label) -> CGFloat {
        switch label {
        case .symbol:
            return iconSide
        case .text(let text):
            return width(text, font: style.font)
        case .none:
            return 0
        }
    }

    /// 把每一行拆成「固定前缀 + 数值」两部分（网速的 ↑ / ↓ 属于前缀）。
    private func splitLine(_ line: String, prefixCount: Int) -> (prefix: String, value: String) {
        guard prefixCount > 0, line.count > prefixCount else { return ("", line) }
        let splitIndex = line.index(line.startIndex, offsetBy: prefixCount)
        return (String(line[..<splitIndex]), String(line[splitIndex...]))
    }

    private func layout(_ segments: [StatusSegment]) -> [SegmentLayout] {
        segments.map { segment in
            let font = segment.lines.count > 1 ? verticalFont : style.font
            let rawLabel = rawLabelWidth(segment.label)
            let hasLabel: Bool
            switch segment.label {
            case .none: hasLabel = false
            default: hasLabel = true
            }
            let hasValue = !segment.lines.isEmpty
            let labelGap = (hasLabel && hasValue) ? SegmentLayout.labelValueGapStandard : 0.0

            if segment.badge {
                let countText = segment.lines.first ?? "0"
                let template = segment.templates.first ?? countText
                // 徽章宽度按「最宽数字」预留，数字在徽章里右对齐：胶囊宽度恒定，模块右缘也不会漂
                let slot = max(badgeTextWidth(countText), badgeTextWidth(template))
                let totalWidth = Self.badgePadLeft + Self.badgeIconWidth
                    + Self.badgeIconTextGap + slot + Self.badgePadRight
                return SegmentLayout(
                    kind: segment.kind,
                    label: segment.label,
                    badge: true,
                    rawLabelWidth: rawLabel,
                    labelValueGap: labelGap,
                    prefixWidth: 0,
                    valueSlotWidth: totalWidth,
                    linePrefixes: [""],
                    values: [countText],
                    badgeTextSlot: slot,
                    font: badgeFont
                )
            } else {
                let split = segment.lines.map { splitLine($0, prefixCount: segment.prefixCount) }
                let prefixes = split.map(\.prefix)
                let values = split.map(\.value)
                let prefixWidth = prefixes.map { width($0, font: font) }.max() ?? 0
                let valueWidths = values.map { width($0, font: font) }
                let templateWidth = segment.templates.map { width($0, font: font) }.max() ?? 0
                let slot = max(valueWidths.max() ?? 0, templateWidth)
                return SegmentLayout(
                    kind: segment.kind,
                    label: segment.label,
                    badge: false,
                    rawLabelWidth: rawLabel,
                    labelValueGap: labelGap,
                    prefixWidth: prefixWidth,
                    valueSlotWidth: slot,
                    linePrefixes: prefixes,
                    values: values,
                    badgeTextSlot: 0,
                    font: font
                )
            }
        }
    }

    /// 内容 + 左右内边距。开启「固定总宽度」时槽位已经把宽度钉死，所以这里算出来的总宽也是稳定的。
    private func totalWidth(of items: [SegmentLayout]) -> CGFloat {
        guard !items.isEmpty else { return 20 }
        let content = items.reduce(CGFloat(0)) { $0 + $1.actualContentWidth }
            + gap * CGFloat(items.count - 1)
        return ceil(max(20, content + sideInset * 2))
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

    /// 自检：返回每个分段真实内容对应的点击区间
    func debugSegmentRects() -> [(String, NSRect)] {
        var x = contentStartX
        var result: [(String, NSRect)] = []
        for (index, item) in cachedLayout.enumerated() {
            if index > 0 { x += gap }
            result.append((item.kind?.rawValue ?? "nil",
                           NSRect(x: x, y: 0, width: item.actualContentWidth, height: bounds.height)))
            x += item.actualContentWidth
        }
        return result
    }

    /// 自检：给定分段时的总宽度
    func measuredWidth(for segments: [StatusSegment]) -> CGFloat {
        totalWidth(of: layout(segments))
    }

    func rebuildLayout() {
        cachedLayout = layout(segments)
        updateWidth()
        contentView.needsDisplay = true
        needsDisplay = true
    }

    /// 目标宽度 = 真实内容 + 左右内边距。
    /// 开启「稳定宽度」时宽度只增不减，收缩会延迟执行——菜单栏在数值来回跳时纹丝不动。
    private func updateWidth() {
        let target = totalWidth(of: cachedLayout)
        if !style.stabilizeWidth {
            resetStableWidth()
            stableWidth = target
        } else if target > stableWidth + 0.5 {
            resetStableWidth()
            stableWidth = target
        } else if target < stableWidth - 0.5 {
            scheduleShrink(to: target)
        }
        applyWidth()
    }

    private func scheduleShrink(to target: CGFloat) {
        pendingShrink?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShrink = nil
            guard self.style.stabilizeWidth, self.stableWidth > target + 0.5 else { return }
            self.stableWidth = target
            self.applyWidth()
            self.contentView.needsDisplay = true
            self.needsDisplay = true
        }
        pendingShrink = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: work)
    }

    private func resetStableWidth() {
        pendingShrink?.cancel()
        pendingShrink = nil
        stableWidth = 0
    }

    private func applyWidth() {
        let width = max(20, stableWidth)
        let height = NSStatusBar.system.thickness
        if let statusItem {
            statusItem.length = width
        }
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        contentView.frame = bounds
        rebuildHitAreas()
    }

    /// 为每个分段铺设透明命中视图（包含分段本身与中间留白，避免点击盲区）
    private func rebuildHitAreas() {
        hitViews.forEach { $0.removeFromSuperview() }
        hitViews.removeAll()

        var x = contentStartX

        for (index, item) in cachedLayout.enumerated() {
            let leftBoundary = (index == 0) ? 0 : (x - gap / 2)
            let rightBoundary = (index == cachedLayout.count - 1)
                ? bounds.width
                : (x + item.actualContentWidth + gap / 2)
            let hitFrame = NSRect(
                x: max(0, leftBoundary),
                y: 0,
                width: max(1, rightBoundary - leftBoundary),
                height: bounds.height
            )

            let hitView = SegmentHitView(frame: hitFrame)
            hitView.index = index
            hitView.kind = item.kind
            hitView.onMouseDown = { [weak self] event in
                self?.handleSegmentMouseDown(kind: item.kind, event: event)
            }
            hitView.onHoverChanged = { [weak self] hovered in
                guard let self else { return }
                if hovered {
                    self.hoveredIndex = index
                } else if self.hoveredIndex == index {
                    self.hoveredIndex = nil
                }
            }
            addSubview(hitView)
            hitViews.append(hitView)
            x += item.actualContentWidth + gap
        }
    }

    private func handleSegmentMouseDown(kind: SegmentKind?, event: NSEvent) {
        if event.modifierFlags.contains(.control) || event.type == .rightMouseDown {
            onRightClick?(event)
            return
        }
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
    }

    private func backgroundRect() -> NSRect {
        // 背景正好等于「内容 + 左右内边距」；宽度稳定保留的那点余量留在右侧且保持透明，
        // 不会再出现右边多出一截背景色的情况。
        let visibleWidth = min(bounds.width, contentWidth + sideInset * 2)
        let rect = NSRect(
            x: 0,
            y: 2,
            width: max(2, visibleWidth),
            height: max(2, bounds.height - 4)
        )
        return rect.insetBy(dx: 1, dy: 0)
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
        if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" {
            NSLog("%@", "DIAG bar background rect=\(rect) bounds=\(bounds) corner=\(style.cornerRadius)")
        }
        let radius = cornerRadius(for: rect)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        switch style.backgroundStyle {
        case .none:
            break
        case .solid:
            style.backgroundColor.setFill()
            path.fill()
            strokeRim(path, radius: radius, rect: rect, alpha: 0.10)
        case .glass:
            drawLiquidGlassCapsule(in: path, rect: rect)
        }
    }

    /// 自绘液态玻璃胶囊：半透明玻璃底 + 顶部镜面高光 + 内侧 hairline 描边。
    /// 全部在一个绘制 pass 里完成，不依赖窗口采样，因此菜单栏里也能稳定出效果。
    private func drawLiquidGlassCapsule(in path: NSBezierPath, rect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // 1. 玻璃本体：暗色菜单栏用深色玻璃，浅色菜单栏用浅色玻璃。
        //    透明度沿用设置里的「背景不透明度」，但玻璃本身保持中性色（不跟自定义背景色跑），
        //    否则选了高饱和色会让菜单栏里的胶囊变得很脏。
        let opacity = CGFloat(min(max(style.backgroundColor.alphaComponent, 0.05), 1))
        let base = isDark ? NSColor.black : NSColor.white
        base.withAlphaComponent(opacity * (isDark ? 0.55 : 0.42)).setFill()
        path.fill()

        // 2. 顶部镜面高光：从顶部柔和衰减到 60%，模拟玻璃厚度带来的折叠高光
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let gloss = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(isDark ? 0.22 : 0.62), 0.0),
            (NSColor.white.withAlphaComponent(isDark ? 0.05 : 0.18), 0.55),
            (NSColor.clear, 1.0)) {
            gloss.draw(in: rect, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        // 3. 内侧 hairline：半像素内缩，描边不会溢出到胶囊外面
        strokeRim(path, radius: cornerRadius(for: rect), rect: rect, alpha: isDark ? 0.18 : 0.55)
    }

    /// 内侧细描边：把路径向内缩半个 hairline，避免 stroke 画在边界外侧造成「边缘溢出」
    private func strokeRim(_ path: NSBezierPath, radius: CGFloat, rect: NSRect, alpha: CGFloat) {
        let hairline = 1.0 / max(1, window?.backingScaleFactor ?? 2)
        let inner = rect.insetBy(dx: hairline / 2, dy: hairline / 2)
        let innerRadius = max(0, radius - hairline / 2)
        let rim = NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius)
        NSColor.white.withAlphaComponent(alpha).setStroke()
        rim.lineWidth = hairline
        rim.stroke()
    }

    private func drawContent() {
        if cachedLayout.count != segments.count {
            cachedLayout = layout(segments)
        }

        var x = contentStartX

        for (index, item) in cachedLayout.enumerated() {
            if index > 0 { x += gap }

            let isActive = isPanelOpen && (item.kind != nil && item.kind == activeSegmentKind)
            let isHovered = (hoveredIndex == index) || (debugHover && (debugHoverIndex == nil ? index == 0 : debugHoverIndex == index))

            // 1. 高亮胶囊在真实内容左右各留同样的一点内边距，不会一边宽一边窄
            if (isActive || isHovered) && !item.badge {
                let pillPad = max(1.5, min(2.5, gap * 0.4))
                let pillRect = NSRect(
                    x: x - pillPad,
                    y: 2.5,
                    width: item.actualContentWidth + pillPad * 2,
                    height: bounds.height - 5
                )
                drawSegmentHighlight(in: pillRect, isActive: isActive, isHovered: isHovered)
            }

            var currentX = x

            // 2. 绘制标签
            switch item.label {
            case .symbol(let name):
                drawSymbol(name, at: NSPoint(x: currentX, y: (bounds.height - iconSide) / 2))
                currentX += item.rawLabelWidth + item.labelValueGap
            case .text(let text):
                let attrs = attributes(style.font)
                let size = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(
                    at: NSPoint(x: currentX, y: (bounds.height - size.height) / 2),
                    withAttributes: attrs
                )
                currentX += item.rawLabelWidth + item.labelValueGap
            case .none:
                break
            }

            // 3. 绘制数值或剪贴板徽章
            if !item.values.isEmpty {
                if item.badge {
                    let badgeRect = NSRect(
                        x: currentX,
                        y: (bounds.height - 15.0) / 2,
                        width: item.valueSlotWidth,
                        height: 15.0
                    )
                    drawBadge(
                        text: item.values[0],
                        textSlot: item.badgeTextSlot,
                        rect: badgeRect,
                        isHovered: isHovered,
                        isActive: isActive
                    )
                } else {
                    drawLines(item, at: currentX)
                }
            }

            x += item.actualContentWidth
        }
    }

    /// 独立分段高亮背景胶囊（悬停时淡亮、激活打开面板时主色强调）
    private func drawSegmentHighlight(in rect: NSRect, isActive: Bool, isHovered: Bool) {
        let radius: CGFloat = 5.0
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if isActive {
            let start = NSColor.controlAccentColor.withAlphaComponent(0.28)
            let end = NSColor.controlAccentColor.withAlphaComponent(0.16)
            if let grad = NSGradient(starting: start, ending: end) {
                grad.draw(in: path, angle: -90)
            } else {
                start.setFill()
                path.fill()
            }
            NSColor.white.withAlphaComponent(0.32).setStroke()
            path.lineWidth = 0.75
            path.stroke()
        } else if isHovered {
            let start = NSColor.labelColor.withAlphaComponent(0.14)
            let end = NSColor.labelColor.withAlphaComponent(0.08)
            if let grad = NSGradient(starting: start, ending: end) {
                grad.draw(in: path, angle: -90)
            } else {
                start.setFill()
                path.fill()
            }
            NSColor.labelColor.withAlphaComponent(0.12).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    /// 剪贴板液态玻璃微型徽章（带 doc.on.clipboard 图标语义 + 等宽紧凑数字）
    private func drawBadge(
        text: String,
        textSlot: CGFloat,
        rect: NSRect,
        isHovered: Bool,
        isActive: Bool
    ) {
        let radius = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // 1. 胶囊背景：跟随文字颜色的半透明玻璃，
        //    这样在纯色 / 毛玻璃背景下不会像一块突兀的强调色贴纸
        let base = style.textColor ?? NSColor.labelColor
        let topAlpha: CGFloat = (isActive || isHovered) ? 0.30 : 0.20
        let bottomAlpha: CGFloat = (isActive || isHovered) ? 0.16 : 0.08
        let topColor = base.withAlphaComponent(topAlpha)
        let bottomColor = base.withAlphaComponent(bottomAlpha)

        if let gradient = NSGradient(starting: topColor, ending: bottomColor) {
            gradient.draw(in: path, angle: -90)
        } else {
            topColor.setFill()
            path.fill()
        }

        // 2. 同色描边（不再用纯白，浅色背景上会发亮）
        base.withAlphaComponent((isActive || isHovered) ? 0.40 : 0.26).setStroke()
        path.lineWidth = 0.65
        path.stroke()

        // 3. 微图标：doc.on.clipboard（赋予数字明确语义）
        let iconW = Self.badgeIconWidth
        let iconH = Self.badgeIconHeight
        if let base = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "剪贴板") {
            let config = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .medium)
            let icon = base.withSymbolConfiguration(config) ?? base
            let tinted = NSImage(size: NSSize(width: iconW, height: iconH))
            tinted.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: NSSize(width: iconW, height: iconH)))
            (style.textColor ?? NSColor.labelColor).set()
            NSRect(origin: .zero, size: NSSize(width: iconW, height: iconH)).fill(using: .sourceAtop)
            tinted.unlockFocus()

            let iconY = rect.minY + (rect.height - iconH) / 2
            tinted.draw(
                in: NSRect(x: rect.minX + Self.badgePadLeft, y: iconY, width: iconW, height: iconH),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: false,
                hints: nil
            )
        }

        // 4. 数字排版
        let font = badgeFont
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.textColor ?? NSColor.labelColor
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        // 数字在固定槽位里右对齐：徽章宽度不会随位数变化，右侧也不会多出空隙
        let textX = rect.minX + Self.badgePadLeft + Self.badgeIconWidth
            + Self.badgeIconTextGap + max(0, textSlot - textSize.width)
        let textY = rect.minY + (rect.height - textSize.height) / 2
        (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }

    private func drawLines(_ item: SegmentLayout, at x: CGFloat) {
        let attrs = attributes(item.font)
        let font = item.font

        // 数值统一在槽位内右对齐；前缀（↑ / ↓）永远贴左，所以模块右缘 = 槽位右缘，
        // 模块之间的间距始终等于设置值。
        func draw(prefix: String, value: String, at baseX: CGFloat, y: CGFloat) {
            if !prefix.isEmpty {
                let prefixAttrs = attributes(font)
                let prefixSize = (prefix as NSString).size(withAttributes: prefixAttrs)
                (prefix as NSString).draw(
                    at: NSPoint(x: baseX, y: y + ((item.lineHeight) - prefixSize.height) / 2),
                    withAttributes: prefixAttrs
                )
            }
            let valueSize = (value as NSString).size(withAttributes: attrs)
            let valueX = baseX + item.prefixWidth + max(0, item.valueSlotWidth - valueSize.width)
            (value as NSString).draw(
                at: NSPoint(x: valueX, y: y + (item.lineHeight - valueSize.height) / 2),
                withAttributes: attrs
            )
        }

        if item.values.count == 1 {
            draw(prefix: item.linePrefixes.first ?? "",
                 value: item.values[0],
                 at: x,
                 y: (bounds.height - item.lineHeight) / 2)
            return
        }

        // 双行：第一行在上、第二行在下
        let lineHeight = item.lineHeight
        let total = lineHeight * CGFloat(item.values.count)
        let startY = max(0, (bounds.height - total) / 2) + 0.5

        for (lineIndex, value) in item.values.enumerated() {
            let y = startY + CGFloat(item.values.count - 1 - lineIndex) * lineHeight
            draw(prefix: item.linePrefixes[safe: lineIndex] ?? "", value: value, at: x, y: y)
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
        // 由各分段的 SegmentHitView 独立跟踪悬停
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
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

    private func segmentIndex(atX rawX: CGFloat) -> Int? {
        guard !cachedLayout.isEmpty else { return nil }
        let clamped = min(max(rawX, 0), bounds.width)
        var x = contentStartX

        for (index, item) in cachedLayout.enumerated() {
            let leftBoundary = (index == 0) ? 0 : (x - gap / 2)
            let rightBoundary = (index == cachedLayout.count - 1)
                ? bounds.width
                : (x + item.actualContentWidth + gap / 2)
            if clamped >= leftBoundary && clamped < rightBoundary {
                return index
            }
            x += item.actualContentWidth + gap
        }
        return nil
    }

    /// 命中测试：菜单栏是一维的，只比较横向位置
    private func segmentKind(atX rawX: CGFloat) -> SegmentKind? {
        guard !cachedLayout.isEmpty else { return nil }
        if let idx = segmentIndex(atX: rawX) {
            return cachedLayout[idx].kind
        }
        let clamped = min(max(rawX, 0), bounds.width)
        if clamped >= bounds.width / 2 { return cachedLayout.last?.kind }
        return cachedLayout.first?.kind
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

    func setDebugHover(_ hovering: Bool, index: Int? = nil) {
        view.debugHover = hovering
        view.debugHoverIndex = index
    }

    var anchorFrame: NSRect {
        view.window?.frame ?? NSRect(x: 0, y: NSScreen.main?.frame.maxY ?? 900, width: 200, height: 24)
    }

    func setPanelOpen(_ open: Bool, for kind: SegmentKind? = nil) {
        view.isPanelOpen = open
        view.activeSegmentKind = open ? kind : nil
    }

    func setActiveSegment(_ kind: SegmentKind?) {
        view.activeSegmentKind = kind
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
        style.backgroundStyle = appearance.backgroundStyle
        style.backgroundColor = ColorHex.nsColor(appearance.backgroundColor)
            .withAlphaComponent(CGFloat(appearance.backgroundOpacity))
        style.cornerRadius = CGFloat(appearance.cornerRadius)
        style.textColor = appearance.useCustomTextColor ? ColorHex.nsColor(appearance.textColor) : nil
        style.stabilizeWidth = settings.stabilizeBarWidth
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

            // 上下排列的网速每行都以 ↑ / ↓ 开头：把它当固定前缀，数值在槽位里右对齐，
            // 这样箭头不动、总宽也不动（否则每换一个速度总宽都会抖）。
            let prefixCount = (config.kind == .network && settings.networkVertical) ? 1 : 0

            let needsBadge = config.kind == .clipboard
                && config.labelMode == .none
                && config.showText
            segments.append(StatusSegment(kind: config.kind, label: label,
                                          lines: lines, prefixCount: prefixCount,
                                          templates: templates, badge: needsBadge))
        }

        if segments.isEmpty {
            segments = [StatusSegment(label: .symbol("chart.bar"), lines: [])]
        }
        return segments
    }

    /// 固定槽位宽度用的「最宽数值」样本。
    /// 只预留到常见最大值（两位数字 / 五位网速），99% 的情况下槽位就等于实际宽度，
    /// 因此不会出现「每个模块右侧都空一截」的老问题；只有个位数时才会在标签与数值之间多出一点空气。
    private func templateLines(for kind: SegmentKind, settings: AppSettings) -> [String] {
        switch kind {
        case .cpu:
            return [settings.showCPUWithTemperature ? "99% 99°" : "99%"]
        case .gpu:
            return ["99%"]
        case .memory:
            return ["99%"]
        case .thermal:
            return ["99°"]
        case .network:
            return settings.networkVertical ? ["9.99M"] : ["↓9.99M ↑9.99M"]
        case .clipboard:
            return ["99"]
        }
    }

    /// 自检：给定快照时状态栏内容应有的宽度
    func width(for snapshot: MetricsSnapshot, count: Int) -> CGFloat {
        let segments = buildSegments(snapshot: snapshot, count: count, settings: settingsStore.settings)
        return view.measuredWidth(for: segments)
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
