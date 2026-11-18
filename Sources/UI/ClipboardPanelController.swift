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

    var onVisibilityChange: ((Bool) -> Void)?
    var panelHeight: CGFloat = 470

    func show(anchor: NSRect) {
        let panel = ensurePanel()
        model.reload()

        let size = NSSize(width: 380, height: panelHeight)
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                origin.y = anchor.maxY + 6
            }
        }
        panel.setFrameOrigin(origin)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
        DispatchQueue.main.async { [weak self] in
            self?.model.requestFocus()
        }
        installMonitors()
        onVisibilityChange?(true)
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var panelContentView: NSView? { panel?.contentView }

    func hide() {
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
        panel?.setContentSize(NSSize(width: 380, height: height))
    }

    private func ensurePanel() -> ClipboardPanel {
        if let panel { return panel }
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: panelHeight),
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
        let hosting = NSHostingController(rootView: ClipboardPanelView(model: model))
        hosting.view.frame = NSRect(x: 0, y: 0, width: 380, height: panelHeight)
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: 380, height: panelHeight))
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
