import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 悬停预览的浮层控制：独立无焦点窗口 + 忽略鼠标事件，
/// 依附在剪贴板面板左侧（空间不够时放右侧），垂直方向跟随鼠标所在行。
final class ClipboardPreviewController {
    // MARK: - 常量

    /// 窗口层级要比剪贴板面板（.popUpMenu）再高一层，否则会被面板盖住
    private static let level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    /// 面板内容区的固定开销：上下内边距 16 + 与底部说明的间距 6 + 说明行 12
    private static let chromeHeight: CGFloat = 34
    private static let textPanelWidth: CGFloat = 352
    /// 文本块实际可用宽度 = 面板宽 - 面板 padding(8×2) - 文本块 padding(6×2)
    private static let textInnerWidth: CGFloat = 324
    private static let maxImageWidth: CGFloat = 360
    private static let maxImageHeight: CGFloat = 300
    /// 预览只需要 360pt 宽，按 2x 上限降采样，避免把 6K 截图整张解进内存
    private static let thumbnailPixelSize: CGFloat = 760
    private static let hoverDelay: TimeInterval = 0.35
    private static let switchDelay: TimeInterval = 0.10
    private static let cacheLimit = 8

    private struct CachedImage {
        let image: NSImage
        let pixelWidth: Int
        let pixelHeight: Int
    }

    // MARK: - 状态

    private let store: SettingsStore
    private let model = ClipboardPreviewModel()
    private var panel: NSPanel?

    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    /// 每次切换条目自增；异步回调用它判断结果是否已经过期（后台线程也会读，所以加锁）
    private let tokenLock = NSLock()
    private var currentToken = 0
    private var requestedID: Int64?
    private var isShowing = false

    private var imageCache: [Int64: CachedImage] = [:]
    private var cacheOrder: [Int64] = []

    /// 文件元数据与内容读取走并发队列：即使某次读取被系统授权框挂住，也不会拖住其它预览
    private static let readQueue = DispatchQueue(
        label: "clipstats.clipboard.preview.read",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// 剪贴板面板在屏幕上的位置；用来决定预览放在左边还是右边
    var anchorProvider: (() -> NSRect?)?

    init(store: SettingsStore = .shared) {
        self.store = store
    }

    deinit {
        showWork?.cancel()
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    // MARK: - 对外接口

    /// 鼠标进入某一行 / 离开列表时调用（nil 表示离开）
    func hover(_ item: ClipboardStore.Item?) {
        showWork?.cancel()
        showWork = nil
        hideWork?.cancel()
        hideWork = nil

        guard let item else {
            // 离开列表：让在途结果立刻失效，避免迟到的图片把浮层又顶出来
            _ = bumpToken()
            requestedID = nil
            scheduleHide()
            return
        }
        if requestedID == item.id, isShowing { return }

        // 切到新条目时先废掉上一条的在途结果，否则会闪出上一条的内容
        _ = bumpToken()
        requestedID = item.id

        // 已经开着预览时快速切换，否则要停留一会儿才弹，避免划过列表时到处弹窗
        let delay = isShowing ? Self.switchDelay : Self.hoverDelay
        let work = DispatchWorkItem { [weak self] in self?.load(item) }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        showWork?.cancel()
        showWork = nil
        hideWork?.cancel()
        hideWork = nil
        _ = bumpToken()
        requestedID = nil
        isShowing = false
        panel?.orderOut(nil)
    }

    func applyAppearance(_ mode: InterfaceAppearance) {
        panel?.appearance = mode.nsAppearance
    }

    var contentView: NSView? { panel?.contentView }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    // MARK: - token

    @discardableResult
    private func bumpToken() -> Int {
        tokenLock.lock()
        currentToken &+= 1
        let value = currentToken
        tokenLock.unlock()
        return value
    }

    private func isTokenCurrent(_ value: Int) -> Bool {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return value == currentToken
    }

    // MARK: - 加载内容

    private func load(_ item: ClipboardStore.Item) {
        let token = bumpToken()
        requestedID = item.id
        model.source = item.sourceApp ?? ""

        switch item.kind {
        case .text:
            let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                present(.unavailable("这条记录没有文本内容"), item: item)
                return
            }
            let limit = 1400
            present(.text(String(text.prefix(limit)), truncated: text.count > limit), item: item)

        case .image:
            if let cached = imageCache[item.id] {
                touchCache(item.id)
                present(.image(cached.image, pixelWidth: cached.pixelWidth, pixelHeight: cached.pixelHeight), item: item)
                return
            }
            // 先占位：否则浮层会继续显示上一条的内容，位置也对不上
            present(.loading, item: item)
            Self.readQueue.async { [weak self] in
                guard let self, self.isTokenCurrent(token) else { return }
                let loaded = Self.loadImage(id: item.id)
                DispatchQueue.main.async {
                    guard self.isTokenCurrent(token) else { return }
                    guard let loaded else {
                        self.present(.unavailable("无法读取这张图片"), item: item)
                        return
                    }
                    self.store(image: loaded, for: item.id)
                    self.present(
                        .image(loaded.image, pixelWidth: loaded.pixelWidth, pixelHeight: loaded.pixelHeight),
                        item: item
                    )
                }
            }

        case .files:
            let paths = (item.text ?? "")
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !paths.isEmpty else {
                present(.unavailable("这条记录没有文件路径"), item: item)
                return
            }
            let previewPaths = Array(paths.prefix(4))
            let reserve = previewPaths.contains { Self.mayBeText(URL(fileURLWithPath: $0)) }

            // 先只列文件名和路径，避免在网络卷 / 断开的外接盘上同步 stat 卡住主线程
            let placeholders = previewPaths.map { path in
                PreviewFileEntry(path: path, name: Self.displayName(path), detail: "", kind: .other)
            }
            present(.files(placeholders, total: paths.count, reservePreview: reserve), item: item)

            Self.readQueue.async { [weak self] in
                guard let self, self.isTokenCurrent(token) else { return }
                let entries = Self.makeEntries(paths: previewPaths)
                DispatchQueue.main.async {
                    guard self.isTokenCurrent(token) else { return }
                    self.model.content = .files(entries, total: paths.count, reservePreview: reserve)
                    self.loadFileText(entries: entries, token: token, total: paths.count, reserve: reserve)
                }
            }
        }
    }

    /// 文本文件内容预览（只读第一个文本文件），受设置项控制
    private func loadFileText(entries: [PreviewFileEntry], token: Int, total: Int, reserve: Bool) {
        guard let index = entries.firstIndex(where: { $0.isTextLike }) else { return }

        guard store.settings.previewFileContents else {
            var updated = entries
            updated[index].failure = "文件内容预览已在「设置 › 剪贴板」中关闭"
            model.content = .files(updated, total: total, reservePreview: reserve)
            return
        }

        let path = entries[index].path
        Self.readQueue.async { [weak self] in
            guard let self, self.isTokenCurrent(token) else { return }
            let result = Self.readText(at: path)
            DispatchQueue.main.async {
                guard self.isTokenCurrent(token) else { return }
                var updated = entries
                guard index < updated.count, updated[index].path == path else { return }
                updated[index].text = result.text
                updated[index].failure = result.failure
                self.model.content = .files(updated, total: total, reservePreview: reserve)
            }
        }
    }

    // MARK: - 文件

    private static func displayName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// 只判断扩展名，不碰文件系统（可在主线程安全调用）
    private static func mayBeText(_ url: URL) -> Bool {
        if url.pathExtension.isEmpty {
            let name = url.lastPathComponent.lowercased()
            return ["makefile", "dockerfile", "license", "readme", "gemfile", "podfile", "procfile"].contains(name)
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .text)
    }

    private static func kindOf(_ url: URL) -> PreviewFileEntry.Kind {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "raw"].contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if mayBeText(url) { return .text }
        return .other
    }

    /// 后台队列调用：这里会 stat 文件，网络卷上可能较慢
    private static func makeEntries(paths: [String]) -> [PreviewFileEntry] {
        let fileManager = FileManager.default
        return paths.map { path in
            let url = URL(fileURLWithPath: path)
            var detail = "—"
            var kind = PreviewFileEntry.Kind.other
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)

            if !exists {
                detail = "已不存在"
                kind = .missing
            } else if isDirectory.boolValue {
                detail = "文件夹"
                kind = .folder
            } else {
                if let attributes = try? fileManager.attributesOfItem(atPath: path),
                   let size = attributes[.size] as? Int64 {
                    detail = Fmt.compactBytes(Double(size))
                }
                kind = kindOf(url)
            }

            return PreviewFileEntry(
                path: path,
                name: displayName(path),
                detail: detail,
                kind: kind,
                text: nil,
                failure: nil
            )
        }
    }

    private static func readText(at path: String) -> (text: String?, failure: String?) {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? Int64, size > 512 * 1024 {
            return (nil, "文件超过 512 KB，跳过内容预览")
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            return (nil, "读不到内容：可能位于受系统保护的目录，需要在「隐私与安全性 › 完全磁盘访问权限」里授权")
        }
        guard let string = String(data: data, encoding: .utf8) else {
            return (nil, "不是 UTF-8 文本，无法预览")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, "空文件") }
        return (String(trimmed.prefix(700)), nil)
    }

    // MARK: - 图片

    /// 后台队列调用：生成降采样缩略图，避免把整张原图解码进内存
    private static func loadImage(id: Int64) -> CachedImage? {
        guard let data = ClipboardStore.shared.payload(id: id),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(thumbnailPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? cgImage.width
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? cgImage.height

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pointSize = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return CachedImage(
            image: NSImage(cgImage: cgImage, size: pointSize),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private func store(image: CachedImage, for id: Int64) {
        if imageCache[id] == nil {
            cacheOrder.append(id)
        }
        imageCache[id] = image
        while cacheOrder.count > Self.cacheLimit {
            let evicted = cacheOrder.removeFirst()
            imageCache[evicted] = nil
        }
    }

    private func touchCache(_ id: Int64) {
        guard let index = cacheOrder.firstIndex(of: id) else { return }
        cacheOrder.remove(at: index)
        cacheOrder.append(id)
    }

    // MARK: - 展示

    private func present(_ content: PreviewContent, item: ClipboardStore.Item) {
        model.content = content
        model.caption = caption(for: content, item: item)
        showPanel(size: size(for: content))
    }

    private func caption(for content: PreviewContent, item: ClipboardStore.Item) -> String {
        switch content {
        case .image(_, let pixelWidth, let pixelHeight):
            return "\(pixelWidth)×\(pixelHeight)"
        case .text:
            return "\(item.text?.count ?? 0) 字"
        case .files(_, let total, _):
            return "\(total) 个文件"
        case .loading, .unavailable:
            return ""
        }
    }

    private func size(for content: PreviewContent) -> NSSize {
        switch content {
        case .image(let image, _, _):
            let imageSize = image.size
            guard imageSize.width > 1, imageSize.height > 1 else {
                return NSSize(width: 240, height: 120 + Self.chromeHeight)
            }
            var width = min(Self.maxImageWidth, max(120, imageSize.width))
            var height = width * imageSize.height / imageSize.width
            if height > Self.maxImageHeight {
                height = Self.maxImageHeight
                width = height * imageSize.width / imageSize.height
            }
            return NSSize(width: (width + 16).rounded(), height: (height + Self.chromeHeight).rounded())

        case .text(let text, _):
            return NSSize(width: Self.textPanelWidth, height: Self.textBlockHeight(text) + Self.chromeHeight)

        case .files(let entries, let total, let reserve):
            let rows = CGFloat(min(entries.count, 4)) + (total > entries.count ? 1 : 0)
            let preview: CGFloat = reserve ? 56 : 0
            let height = Self.chromeHeight + rows * 20 + preview
            return NSSize(width: Self.textPanelWidth, height: min(320, height).rounded())

        case .loading, .unavailable:
            return NSSize(width: 240, height: 92 + Self.chromeHeight)
        }
    }

    /// 用真实字体量一次，中文/长文本就不会因为按 46 列估算而被裁掉
    private static func textBlockHeight(_ text: String) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .paragraphStyle: style,
            ]
        )
        let rect = attributed.boundingRect(
            with: NSSize(width: textInnerWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return min(240, max(56, rect.height.rounded(.up) + 4))
    }

    private func showPanel(size: NSSize) {
        let panel = ensurePanel()
        panel.appearance = store.settings.interfaceAppearance.nsAppearance
        panel.setContentSize(size)
        position(panel, size: size)
        panel.invalidateShadow()
        panel.orderFront(nil)
        isShowing = true
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let anchor = anchorProvider?()
        // 以面板所在屏幕为准做边界裁剪，避免锚点在另一块屏时用错 visibleFrame
        let reference = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? mouse
        let screen = NSScreen.screens.first { $0.frame.contains(reference) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var originX: CGFloat
        if let anchor, anchor.width > 0 {
            let left = anchor.minX - size.width - 10
            let right = anchor.maxX + 10
            if left >= visible.minX + 8 {
                originX = left
            } else if right + size.width <= visible.maxX - 8 {
                originX = right
            } else {
                // 左右都放不下（小屏 / 分屏）：退到面板内侧
                originX = anchor.minX + 12
            }
        } else {
            originX = mouse.x + 18
        }
        originX = min(max(visible.minX + 8, originX), max(visible.minX + 8, visible.maxX - size.width - 8))

        var originY = mouse.y - size.height / 2
        originY = min(max(visible.minY + 8, originY), max(visible.minY + 8, visible.maxY - size.height - 8))

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = ClipboardPreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.textPanelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = Self.level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 关键：忽略鼠标事件，否则浮层会挡住列表行导致 hover 中断
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingController(rootView: ClipboardPreviewView(model: model, store: store))
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hosting

        self.panel = panel
        return panel
    }
}

/// 预览浮层永不成为 key window，避免抢走剪贴板面板里搜索框的焦点
private final class ClipboardPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
