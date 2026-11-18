import AppKit
import SwiftUI

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClipboardPanelController: NSObject, NSWindowDelegate {
    let model = ClipboardPanelModel()
    private var panel: ClipboardPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let store: SettingsStore

    var onVisibilityChange: ((Bool) -> Void)?
    var panelHeight: CGFloat = 470

    private let panelWidth: CGFloat = 390

    /// 悬停预览浮层（图片大图 / 文本内容 / 文件清单）
    private lazy var preview: ClipboardPreviewController = {
        let controller = ClipboardPreviewController(store: store)
        controller.anchorProvider = { [weak self] in self?.panel?.frame }
        return controller
    }()

    init(store: SettingsStore = .shared) {
        self.store = store
        super.init()
        model.onHoverPreview = { [weak self] item in
            guard let self else { return }
            self.preview.hover(item)
        }
    }

    func applyAppearance(_ mode: InterfaceAppearance) {
        panel?.appearance = mode.nsAppearance
        preview.applyAppearance(mode)
    }

    /// 调试 / 截图用
    var previewContentView: NSView? { preview.contentView }

    func show(anchor: NSRect) {
        let panel = ensurePanel()
        panel.appearance = store.settings.interfaceAppearance.nsAppearance
        if model.searchText.isEmpty {
            model.reload()
        } else {
            model.searchText = ""   // didSet 会触发去抖后的 reload
        }

        let size = NSSize(width: panelWidth, height: panelHeight)
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 8)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                origin.y = anchor.maxY + 8
            }
        }
        panel.setFrameOrigin(origin)
        panel.invalidateShadow()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // 面板刚显示时窗口还没真正成为 key window，稍后再移一次焦点即可
        DispatchQueue.main.async { [weak self] in
            self?.model.requestFocus()
            self?.panel?.invalidateShadow()
        }
        installMonitors()
        onVisibilityChange?(true)
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var panelContentView: NSView? { panel?.contentView }

    func hide() {
        preview.hide()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        removeMonitors()
        onVisibilityChange?(false)
    }

    func toggle(anchor: NSRect) {
        if let panel, panel.isVisible {
            hide()
        } else {
            show(anchor: anchor)
        }
    }

    func applyHeight(_ height: CGFloat) {
        panelHeight = height
        model.panelHeight = height
        panel?.setContentSize(NSSize(width: panelWidth, height: height))
        panel?.invalidateShadow()
    }

    private func ensurePanel() -> ClipboardPanel {
        if let panel { return panel }
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        model.panelHeight = panelHeight
        let hosting = NSHostingController(rootView: ClipboardPanelView(model: model, store: store))
        hosting.view.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.invalidateShadow()
        self.panel = panel
        return panel
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
