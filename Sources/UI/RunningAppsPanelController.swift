import AppKit
import SwiftUI

final class RunningAppsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 运行中应用面板：与剪贴板面板同样以状态栏项为锚点弹出。
final class RunningAppsPanelController: NSObject, NSWindowDelegate {
    let model = RunningAppsModel()

    private var panel: RunningAppsPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var refreshTimer: Timer?
    private let store: SettingsStore

    var onVisibilityChange: ((Bool) -> Void)?

    init(store: SettingsStore = .shared) {
        self.store = store
        super.init()
    }

    func applyAppearance(_ mode: InterfaceAppearance) {
        panel?.appearance = mode.nsAppearance
    }

    private var panelWidth: CGFloat { RunningAppsPanelView.panelSize.width }
    private var panelHeight: CGFloat { RunningAppsPanelView.panelSize.height }
    /// 面板弹出前的前台应用，关闭时恢复焦点
    private weak var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }
    var panelContentView: NSView? { panel?.contentView }

    func toggle(anchor: NSRect) {
        if isVisible {
            hide()
        } else {
            show(anchor: anchor)
        }
    }

    func show(anchor: NSRect) {
        let panel = ensurePanel()
        panel.appearance = store.settings.interfaceAppearance.nsAppearance
        if !isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        model.reload()

        let size = NSSize(width: panelWidth, height: panelHeight)
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                // 下方放不下时放到屏幕内底部，而不是挪到菜单栏之上（屏幕外）
                origin.y = max(visible.minY + 8, visible.maxY - size.height - 8)
            }
        }
        panel.setFrameOrigin(origin)
        panel.invalidateShadow()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        PanelPresentation.present(panel)

        model.resumeBackgroundSampling()
        installMonitors()
        startRefreshTimer()
        onVisibilityChange?(true)
    }

    func hide() {
        let shouldRestoreFocus = NSApp.isActive

        // 注意：即使窗口已被系统收起（锁屏/切换空间），也要把监听与定时器清理干净
        if let panel, panel.isVisible {
            PanelPresentation.dismiss(panel)
        }
        removeMonitors()
        stopRefreshTimer()
        model.suspendBackgroundSampling()
        model.hoveredPID = nil
        onVisibilityChange?(false)

        // 面板是主动激活 App 弹出的，关闭后把焦点还给原来的前台应用（点外部关闭时不会触发）
        if shouldRestoreFocus,
           let app = previousApp,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           !app.isTerminated {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [])
            }
        }
        previousApp = nil
    }

    // MARK: - 面板

    private func ensurePanel() -> RunningAppsPanel {
        if let panel { return panel }

        let panel = RunningAppsPanel(
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

        let hosting = NSHostingController(rootView: RunningAppsPanelView(model: model, store: store))
        hosting.view.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        if panel.contentView?.layer == nil {
            panel.contentView?.wantsLayer = true
        }
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        self.panel = panel
        return panel
    }

    // MARK: - NSWindowDelegate

    /// 切到别的应用（Cmd+Tab、点其它窗口）时收起，避免面板以 .popUpMenu 层级压住别的窗口
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - 事件监听

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

    // MARK: - 定时刷新

    private func startRefreshTimer() {
        stopRefreshTimer()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.model.reload()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit {
        stopRefreshTimer()
        removeMonitors()
    }
}
