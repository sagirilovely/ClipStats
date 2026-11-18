import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore.shared
    private let engine = MetricsEngine()
    private let monitor = ClipboardMonitor()

    private var statusBar: StatusBarController!
    private var panelController: ClipboardPanelController!
    private var settingsWindow: SettingsWindowController?

    private var lastApplied: AppSettings?
    private var latest = MetricsSnapshot()

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(settingsStore: store) { [weak self] _ in
            self?.buildMenu()
        }
        panelController = ClipboardPanelController()

        statusBar.onTogglePanel = { [weak self] anchor in
            self?.panelController.toggle(anchor: anchor)
        }
        panelController.onVisibilityChange = { [weak self] visible in
            self?.statusBar.setPanelOpen(visible)
        }

        let model = panelController.model
        model.onRestore = { [weak self] item in
            self?.monitor.restore(item)
            self?.panelController.hide()
        }
        model.onRequestSettings = { [weak self] in
            self?.panelController.hide()
            self?.openSettings()
        }
        model.onRequestQuit = {
            NSApp.terminate(nil)
        }
        model.onTogglePause = { [weak self] paused in
            self?.store.set { $0.clipboardPaused = paused }
        }
        model.onClearAll = { [weak self] in
            ClipboardStore.shared.clear()
            self?.statusBar.updateClipboardCount(0)
        }

        engine.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.latest = snapshot
            self.statusBar.update(snapshot)
            self.logDiagnostics(snapshot)
        }

        monitor.onCapture = { [weak self] _ in
            guard let self else { return }
            ClipboardStore.shared.trim(maxItems: self.store.settings.clipboardMaxItems)
            self.statusBar.updateClipboardCount(ClipboardStore.shared.count())
            self.panelController.model.reload()
        }

        NotificationCenter.default.addObserver(
            forName: .clipboardHistoryCleared, object: nil, queue: .main
        ) { [weak self] _ in
            self?.statusBar.updateClipboardCount(0)
            self?.panelController.model.reload()
        }

        if let mode = ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_APPEARANCE"] {
            store.set { settings in
                switch mode {
                case "solid":
                    settings.appearance.backgroundStyle = .solid
                    settings.appearance.backgroundOpacity = 0.9
                    settings.appearance.backgroundColor = "#2B6CF6"
                    settings.appearance.useCustomTextColor = true
                    settings.appearance.textColor = "#FFFFFF"
                    settings.appearance.cornerRadius = 6
                case "glass":
                    settings.appearance.backgroundStyle = .glass
                case "compact":
                    settings.appearance.segmentSpacing = 2
                    settings.appearance.horizontalPadding = 2
                    settings.appearance.iconPointSize = 10
                default:
                    break
                }
            }
        }

        store.onChange = { [weak self] settings in
            self?.apply(settings)
        }

        apply(store.settings)
        statusBar.updateClipboardCount(ClipboardStore.shared.count())

        NSLog("ClipStats started (pid \(ProcessInfo.processInfo.processIdentifier))")

        if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                let frame = self.statusBar.anchorFrame
                NSLog("%@", "DIAG statusItem frame=\(frame) segments=\(self.store.settings.segments.filter(\.enabled).map(\.kind.rawValue))")
                self.verifyBarWidth()
            }
            if let idText = ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_RESTORE"],
               let id = Int64(idText) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self else { return }
                    guard let item = ClipboardStore.shared.item(id: id) else {
                        NSLog("%@", "DIAG restore: item \(id) not found")
                        return
                    }
                    let ok = self.monitor.restore(item)
                    let pasteboard = NSPasteboard.general
                    let types = (pasteboard.types ?? []).map { $0.rawValue }.joined(separator: ",")
                    let text = pasteboard.string(forType: .string) ?? ""
                    NSLog("%@", "DIAG restore ok=\(ok) kind=\(item.kind.rawValue) types=[\(types)] text=\(text.prefix(40))")
                }
            }
            let show = ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_SHOW"] ?? ""
            if show == "panel" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.panelController.show(anchor: self.statusBar.anchorFrame)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let visible = self.panelController.isVisible
                        NSLog("%@", "DIAG panel visible=\(visible) windows=\(NSApp.windows.map { "\($0.className):\($0.isVisible):\($0.frame)" })")
                    }
                }
            } else if show == "snapshot" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.panelController.show(anchor: self.statusBar.anchorFrame)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if let view = self.panelController.panelContentView {
                            self.snapshot(view, to: "/tmp/shot-panel.png")
                        }
                        self.snapshot(self.statusBar.statusView, to: "/tmp/shot-bar-transparent.png")
                        let viewAppearance = self.statusBar.statusView.effectiveAppearance
                        let style = viewAppearance.bestMatch(from: [.darkAqua, .aqua])
                        NSLog("%@", "DIAG appearance app=\(NSApp.effectiveAppearance.name.rawValue) view=\(viewAppearance.name.rawValue) style=\(style == .darkAqua ? "dark" : "light")")
                        self.statusBar.setDebugBackground(style == .darkAqua ? .black : .white)
                        self.snapshot(self.statusBar.statusView, to: "/tmp/shot-bar.png")
                        self.statusBar.setDebugBackground(nil)
                        self.openSettingsWindow()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if let view = self.settingsWindow?.window?.contentView {
                                self.snapshot(view, to: "/tmp/shot-settings.png")
                            }
                            if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_TABS"] == "1" {
                                self.captureSettingsTabs()
                            }
                            NSLog("%@", "DIAG snapshot done")
                        }
                    }
                }
            } else if show == "settings" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.openSettingsWindow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSLog("%@", "DIAG settings windows=\(NSApp.windows.map { "\($0.className):\($0.isVisible):\($0.frame)" })")
                    }
                }
            }
        }
    }

    /// 自检：极端数值下状态栏宽度应保持一致（固定槽位生效）
    private func verifyBarWidth() {
        var low = MetricsSnapshot()
        low.cpu.total = 0.02
        low.memory.total = 100
        low.memory.used = 1
        low.thermal.cpuTemperature = 45
        low.thermal.cpuTemperatureAverage = 45
        low.gpu.utilization = 0.01
        low.network.download = 120
        low.network.upload = 80

        var high = MetricsSnapshot()
        high.cpu.total = 1.0
        high.memory.total = 100
        high.memory.used = 100
        high.thermal.cpuTemperature = 105
        high.thermal.cpuTemperatureAverage = 105
        high.gpu.utilization = 1.0
        high.network.download = 999 * 1024 * 1024
        high.network.upload = 999 * 1024 * 1024

        var mid = MetricsSnapshot()
        mid.cpu.total = 0.37
        mid.memory.total = 100
        mid.memory.used = 42
        mid.thermal.cpuTemperature = 70
        mid.thermal.cpuTemperatureAverage = 70
        mid.gpu.utilization = 0.48
        mid.network.download = 1_204_000
        mid.network.upload = 86_000

        let widths = [(low, 1), (mid, 42), (high, 999)].map { pair in
            self.statusBar.width(for: pair.0, count: pair.1)
        }
        let stable = Set(widths).count == 1
        NSLog("%@", "DIAG bar widths low/mid/high = \(widths) stable=\(stable)")
    }

    private func captureSettingsTabs() {
        guard let controller = settingsWindow else { return }
        let tabs: [SettingsTab] = [.statusBar, .appearance, .sampling, .clipboard, .hotkey, .about]
        for (index, tab) in tabs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(index) * 0.9) { [weak self] in
                controller.viewModel.tab = tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, let view = controller.window?.contentView else { return }
                    self.snapshot(view, to: "/tmp/shot-tab-\(tab.key).png")
                }
            }
        }
    }

    private func snapshot(_ view: NSView, to path: String) {
        guard view.bounds.width > 0, view.bounds.height > 0 else {
            NSLog("%@", "DIAG snapshot skipped (empty bounds) \(path)")
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        NSLog("%@", "DIAG snapshot \(path) size=\(view.bounds.size)")
    }

    private var lastDiagLog = Date.distantPast

    private func logDiagnostics(_ snapshot: MetricsSnapshot) {
        guard ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" else { return }
        guard Date().timeIntervalSince(lastDiagLog) > 2 else { return }
        lastDiagLog = Date()
        let cpuTemp = snapshot.thermal.cpuTemperature.map { String(format: "%.1f", $0) } ?? "nil"
        let gpuTemp = snapshot.thermal.gpuTemperature.map { String(format: "%.1f", $0) } ?? "nil"
        let gpu = snapshot.gpu.utilization.map { String(format: "%.0f%%", $0 * 100) } ?? "nil"
        NSLog("%@", String(
            format: "DIAG cpu=%.1f%% ram=%.1f%%(%llu/%llu MB) gpu=%@ temp(cpu=%@ gpu=%@ sensors=%d) net=%.0f/%.0f B/s",
            snapshot.cpu.total * 100,
            snapshot.memory.usage * 100,
            snapshot.memory.used / 1_048_576,
            snapshot.memory.total / 1_048_576,
            gpu,
            cpuTemp,
            gpuTemp,
            snapshot.thermal.readings.count,
            snapshot.network.download,
            snapshot.network.upload
        ))
        let hottest = snapshot.thermal.readings.sorted { $0.value > $1.value }.prefix(6)
            .map { "\($0.key)=\(Int($0.value))" }.joined(separator: " ")
        NSLog("%@", "DIAG hottest: \(hottest)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        monitor.stop()
        GlobalHotKeyManager.shared.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 设置应用

    private func apply(_ settings: AppSettings) {
        let previous = lastApplied
        lastApplied = settings

        statusBar.applySettings()
        panelController.applyHeight(CGFloat(settings.clipboardPanelHeight))

        let metricsChanged = previous == nil
            || previous?.metricsInterval != settings.metricsInterval
            || previous?.thermalInterval != settings.thermalInterval
            || thermalConsumersEnabled(previous) != thermalConsumersEnabled(settings)
        if metricsChanged {
            engine.start(settings: settings, thermalEnabled: thermalConsumersEnabled(settings))
        }

        if previous == nil || previous?.clipboardPollInterval != settings.clipboardPollInterval {
            monitor.start(interval: settings.clipboardPollInterval)
        }
        monitor.isPaused = settings.clipboardPaused || !settings.clipboardEnabled
        monitor.maxImageBytes = settings.maxImageBytes
        monitor.skipSensitive = settings.skipSensitive
        panelController.model.paused = settings.clipboardPaused

        if previous == nil || previous?.hotKey != settings.hotKey {
            GlobalHotKeyManager.shared.register(settings.hotKey) { [weak self] in
                guard let self else { return }
                self.panelController.toggle(anchor: self.statusBar.anchorFrame)
            }
        }

        if previous == nil || previous?.launchAtLogin != settings.launchAtLogin {
            applyLaunchAtLogin(settings.launchAtLogin)
        }

        if previous != nil, previous?.clipboardMaxItems != settings.clipboardMaxItems {
            ClipboardStore.shared.trim(maxItems: settings.clipboardMaxItems)
        }
    }

    private func thermalConsumersEnabled(_ settings: AppSettings?) -> Bool {
        guard let settings else { return true }
        let hasThermal = settings.segments.contains { $0.enabled && ($0.kind == .thermal) }
        return hasThermal || settings.showCPUWithTemperature
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("ClipStats: launch at login failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let history = NSMenuItem(title: "剪贴板历史…", action: #selector(showHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        menu.addItem(.separator())

        let pauseTitle = store.settings.clipboardPaused ? "恢复记录" : "暂停记录"
        let pause = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let clear = NSMenuItem(title: "清空剪贴板历史", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let preferences = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let quit = NSMenuItem(title: "退出 ClipStats", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func showHistory() {
        panelController.show(anchor: statusBar.anchorFrame)
    }

    @objc private func togglePause() {
        store.set { $0.clipboardPaused.toggle() }
    }

    @objc private func clearHistory() {
        ClipboardStore.shared.clear()
        statusBar.updateClipboardCount(0)
        panelController.model.reload()
    }

    @objc private func openSettings() {
        openSettingsWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func openSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: store)
        }
        settingsWindow?.show()
    }
}
