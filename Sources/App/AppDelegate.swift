import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore.shared
    private let engine = MetricsEngine()
    private let monitor = ClipboardMonitor()

    private var statusBar: StatusBarController!
    private var panelController: ClipboardPanelController!
    private var appsController: RunningAppsPanelController!
    private var translationController: TranslationPanelController!
    private let updateChecker = UpdateChecker.shared
    private var updatePanelController: UpdatePanelController!
    private var updateTimer: DispatchSourceTimer?
    private var settingsWindow: SettingsWindowController?

    private var lastApplied: AppSettings?
    private var latest = MetricsSnapshot()

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(settingsStore: store) { [weak self] _ in
            self?.buildMenu()
        }
        panelController = ClipboardPanelController()
        appsController = RunningAppsPanelController()
        translationController = TranslationPanelController()
        updatePanelController = UpdatePanelController(checker: updateChecker, store: store)
        updateChecker.cleanUpOldDownloads()
        setUpUpdateChecking()

        // 点剪贴板分段 → 剪贴板历史；点其它任意模块 → 正在运行的应用程序（自动定位并高亮对应分类）
        statusBar.onSegmentClick = { [weak self] kind, anchor in
            guard let self else { return }
            self.translationController.hide()
            if kind == .clipboard {
                self.appsController.hide()
                self.panelController.toggle(anchor: anchor)
            } else {
                self.panelController.hide()
                let targetMode = Self.metricMode(for: kind)
                if self.appsController.isVisible && self.appsController.model.mode == targetMode {
                    self.appsController.hide()
                } else {
                    self.appsController.model.mode = targetMode
                    self.appsController.model.metrics = self.latest
                    self.appsController.show(anchor: anchor)
                }
            }
        }
        appsController.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            let kind = visible ? Self.segmentKind(for: self.appsController.model.mode) : nil
            self.statusBar.setPanelOpen(visible, for: kind)
        }
        appsController.model.onModeChange = { [weak self] newMode in
            guard let self, self.appsController.isVisible else { return }
            self.statusBar.setActiveSegment(Self.segmentKind(for: newMode))
        }
        appsController.model.onOpenSettings = { [weak self] in
            self?.appsController.hide()
            self?.openSettingsWindow()
        }
        appsController.model.onSwitchToClipboard = { [weak self] in
            guard let self else { return }
            self.appsController.hide()
            self.translationController.hide()
            self.panelController.show(anchor: self.statusBar.anchorFrame)
        }
        appsController.model.onOpenTranslation = { [weak self] in
            guard let self else { return }
            self.appsController.hide()
            self.panelController.hide()
            self.translationController.show(anchor: self.statusBar.anchorFrame)
        }
        panelController.model.onSwitchToRunningApps = { [weak self] in
            guard let self else { return }
            self.panelController.hide()
            self.appsController.show(anchor: self.statusBar.anchorFrame)
        }
        panelController.model.onRequestTranslation = { [weak self] in
            guard let self else { return }
            self.panelController.hide()
            self.translationController.show(anchor: self.statusBar.anchorFrame)
        }
        panelController.onVisibilityChange = { [weak self] visible in
            self?.statusBar.setPanelOpen(visible, for: visible ? .clipboard : nil)
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
        model.onHistoryCleared = { [weak self] in
            self?.statusBar.updateClipboardCount(ClipboardStore.shared.count())
        }

        engine.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.latest = snapshot
            self.statusBar.update(snapshot)
            if self.appsController?.isVisible == true {
                self.appsController.model.metrics = snapshot
            }
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
                case "dark":
                    settings.interfaceAppearance = .dark
                case "light":
                    settings.interfaceAppearance = .light
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
                case "gap0":
                    settings.appearance.segmentSpacing = 0
                    settings.appearance.horizontalPadding = 0
                    settings.stabilizeBarWidth = true
                    settings.networkVertical = true
                case "text":
                    settings.segments = settings.segments.map { config in
                        var copy = config
                        copy.labelMode = .text
                        return copy
                    }
                case "vertical":
                    settings.networkVertical = true
                case "labels":
                    settings.segments = settings.segments.map { config in
                        var copy = config
                        copy.labelMode = .text
                        return copy
                    }
                case "perf-default":
                    settings.metricsInterval = 1
                    settings.thermalInterval = 3
                    settings.clipboardPollInterval = 0.3
                case "perf-fast":
                    settings.metricsInterval = 0.5
                    settings.thermalInterval = 1
                    settings.clipboardPollInterval = 0.2
                case "textvertical":
                    settings.networkVertical = true
                    settings.appearance.segmentSpacing = 4
                    settings.segments = settings.segments.map { config in
                        var copy = config
                        copy.labelMode = .text
                        return copy
                    }
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
                if let view = self.statusBar.statusView as? StatusItemView {
                    let rects = view.debugSegmentRects()
                        .map { "\($0.0)[\(Int($0.1.minX))-\(Int($0.1.maxX))]" }
                        .joined(separator: " ")
                    NSLog("%@", "DIAG segments: \(rects) bounds=\(view.bounds.width)")
                    NSLog("%@", "DIAG hitTest: \(view.debugHitKinds())")
                    NSLog("%@", "DIAG hitViews=\(view.debugHitViewCount)")
                }
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
            } else if show == "preview" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.panelController.show(anchor: self.statusBar.anchorFrame)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let kind = ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_PREVIEW_KIND"] ?? "image"
                        let item = self.panelController.model.items.first { $0.kind.rawValue == kind }
                            ?? self.panelController.model.items.first
                        guard let item else {
                            NSLog("%@", "DIAG preview: no items in list")
                            return
                        }
                        NSLog("%@", "DIAG preview kind=\(item.kind.rawValue) id=\(item.id) source=\(item.sourceApp ?? "-")")
                        // 走真实的 hover 链路（延迟、token、加载都覆盖），而不是直接弹窗
                        self.panelController.model.setHovered(item.id, true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            if let view = self.panelController.previewContentView {
                                self.snapshot(view, to: "/tmp/shot-preview-\(kind).png")
                            } else {
                                NSLog("%@", "DIAG preview: content view missing")
                            }
                            NSLog("%@", "DIAG preview windows=\(NSApp.windows.map { "\($0.className):\($0.isVisible):\($0.frame)" })")
                        }
                    }
                }
            } else if show == "apps" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    if let modeText = ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_APPS_MODE"],
                       let mode = MetricMode(rawValue: modeText) {
                        self.appsController.model.mode = mode
                    }
                    self.appsController.model.metrics = self.latest
                    self.appsController.show(anchor: self.statusBar.anchorFrame)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        if let view = self.appsController.panelContentView {
                            self.snapshot(view, to: "/tmp/shot-apps-\(self.appsController.model.mode.rawValue).png")
                        }
                        NSLog("%@", "DIAG apps windows=\(NSApp.windows.map { "\($0.className):\($0.isVisible):\($0.frame)" })")
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
                        let appearance = self.statusBar.statusView.effectiveAppearance
                        let style = appearance.bestMatch(from: [.darkAqua, .aqua])
                        let bg: NSColor = (style == .darkAqua ? .black : .white)

                        // 1. 无悬停时的状态栏（剪贴板激活高亮）
                        self.snapshot(self.statusBar.statusView, to: "/tmp/shot-bar-transparent.png")
                        self.statusBar.setDebugBackground(bg)
                        self.snapshot(self.statusBar.statusView, to: "/tmp/shot-bar.png")
                        self.statusBar.setDebugBackground(nil)

                        // 2. 鼠标悬停在 CPU 分段时的状态栏（仅 CPU 高亮，剪贴板保持激活）
                        self.statusBar.setDebugHover(true, index: 0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.statusBar.setDebugBackground(bg)
                            self.snapshot(self.statusBar.statusView, to: "/tmp/shot-bar-hover.png")
                            self.statusBar.setDebugBackground(nil)
                            self.statusBar.setDebugHover(false)
                        }

                        NSLog("%@", "DIAG appearance app=\(NSApp.effectiveAppearance.name.rawValue) view=\(appearance.name.rawValue) style=\(style == .darkAqua ? "dark" : "light")")
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
            } else if show == "translate" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.translationController.show(anchor: self.statusBar.anchorFrame)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NSLog("%@", "DIAG translate shown visible=\(self.translationController.isVisible)")
                    }
                    let text = ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_TRANSLATE_TEXT"] ?? "variableName"
                    NSLog("%@", "DIAG translate start text=\(text)")
                    self.translationController.model.english = text
                    self.translationController.model.edited(.english, text)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        let model = self.translationController.model
                        NSLog("%@", "DIAG translate result en=[\(model.english)] zh=[\(model.chinese)] status=[\(model.statusText)] direction=[\(model.directionTitle)]")
                        if let view = self.translationController.panelContentView {
                            self.snapshot(view, to: "/tmp/shot-translate.png")
                        }

                    }
                }
            } else if show == "update" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.updatePanelController.show(anchor: self.statusBar.anchorFrame)
                    self.updateChecker.check(automatic: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        NSLog("%@", "DIAG update state=\(self.updateChecker.state)")
                        if let view = self.updatePanelController.panelContentView {
                            self.snapshot(view, to: "/tmp/shot-update.png")
                        }
                        if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_UPDATE_DOWNLOAD"] == "1",
                           case .available(let release) = self.updateChecker.state {
                            NSLog("%@", "DIAG update start download \(release.version)")
                            self.updateChecker.download(release)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                                NSLog("%@", "DIAG update after download state=\(self.updateChecker.state)")
                                if let view = self.updatePanelController.panelContentView {
                                    self.snapshot(view, to: "/tmp/shot-update-done.png")
                                }
                            }
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

    /// 自检：数值在常见区间内跳动时，状态栏总宽应当保持不变（固定槽位生效）。
    private func verifyBarWidth() {
        func snapshot(cpu: Double, gpu: Double, memoryUsed: UInt64, temperature: Double,
                      down: Double, up: Double) -> MetricsSnapshot {
            var s = MetricsSnapshot()
            s.cpu.total = cpu
            s.gpu.utilization = gpu
            s.memory.total = 100
            s.memory.used = memoryUsed
            s.thermal.cpuTemperature = temperature
            s.thermal.cpuTemperatureAverage = temperature
            s.network.download = down
            s.network.upload = up
            return s
        }

        // 覆盖用户实际会遇到的范围：个位数 / 两位小数网速 / 空闲 / 高速
        let samples: [(String, MetricsSnapshot, Int)] = [
            ("idle", snapshot(cpu: 0.02, gpu: 0.01, memoryUsed: 1, temperature: 45,
                              down: 0, up: 0), 9),
            ("low", snapshot(cpu: 0.08, gpu: 0.09, memoryUsed: 42, temperature: 51,
                             down: 120, up: 80), 42),
            ("mid", snapshot(cpu: 0.26, gpu: 0.48, memoryUsed: 78, temperature: 63,
                             down: 1_204_000, up: 86_000), 42),
            ("busy", snapshot(cpu: 0.99, gpu: 0.99, memoryUsed: 99, temperature: 99,
                              down: 9_999_999, up: 9_999_999), 99),
            ("extreme", snapshot(cpu: 1.0, gpu: 1.0, memoryUsed: 100, temperature: 105,
                                 down: 999 * 1024 * 1024, up: 852 * 1024 * 1024), 99),
        ]
        let widths = samples.map { self.statusBar.width(for: $0.1, count: $0.2) }
        let normal = Array(widths.prefix(4))
        let stable = Set(normal).count == 1
        let detail = zip(samples.map(\.0), widths).map { "\($0)=\(Int($1))" }.joined(separator: " ")
        NSLog("%@", "DIAG bar widths \(detail) stable(idle..busy)=\(stable)")
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
        appsController?.hide()
        appsController?.model.cancelPendingVerifications()
        GlobalHotKeyManager.shared.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 设置应用

    // MARK: - 更新检查

    private func setUpUpdateChecking() {
        // 自动检查发现新版本时弹面板（同一版本用户点过「跳过此版本」就不会再弹）
        updateChecker.onAvailable = { [weak self] _ in
            guard let self, !self.updatePanelController.isVisible else { return }
            self.translationController.hide()
            self.panelController.hide()
            self.appsController.hide()
            self.updatePanelController.show(anchor: self.statusBar.anchorFrame)
        }

        NotificationCenter.default.addObserver(
            forName: .requestUpdateCheck, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkForUpdates(manual: true)
        }

        // 启动后稍等再查，避免和首屏渲染、指标采样抢资源
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.store.settings.autoCheckUpdates else { return }
            self.updateChecker.checkIfNeeded()
        }

        // 每 24 小时一次；checkIfNeeded 内部还会再看一次冷却期
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 24 * 60 * 60, repeating: 24 * 60 * 60, leeway: .seconds(300))
        timer.setEventHandler { [weak self] in
            guard let self, self.store.settings.autoCheckUpdates else { return }
            self.updateChecker.checkIfNeeded()
        }
        timer.resume()
        updateTimer = timer
    }

    private func checkForUpdates(manual: Bool) {
        updatePanelController.show(anchor: statusBar.anchorFrame)
        updateChecker.check(automatic: !manual)
    }

    private func apply(_ settings: AppSettings) {
        let previous = lastApplied
        lastApplied = settings

        statusBar.applySettings()
        panelController.applyHeight(CGFloat(settings.clipboardPanelHeight))

        if previous == nil || previous?.interfaceAppearance != settings.interfaceAppearance {
            panelController.applyAppearance(settings.interfaceAppearance)
            appsController.applyAppearance(settings.interfaceAppearance)
            translationController.applyAppearance(settings.interfaceAppearance)
            updatePanelController.applyAppearance(settings.interfaceAppearance)
            settingsWindow?.applyAppearance(settings.interfaceAppearance)
        }

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
                self.appsController?.hide()
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

    /// 从哪个模块点进来，就默认按该指标排序并显示对应详情
    private static func metricMode(for kind: SegmentKind?) -> MetricMode {
        switch kind {
        case .gpu: return .gpu
        case .memory: return .memory
        case .network: return .network
        default: return .cpu        // CPU / 温度 / 空白区域
        }
    }

    private static func segmentKind(for mode: MetricMode) -> SegmentKind {
        switch mode {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .network: return .network
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

        let runningApps = NSMenuItem(title: "正在运行的应用…", action: #selector(showRunningApps), keyEquivalent: "")
        runningApps.target = self
        menu.addItem(runningApps)

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

        let checkUpdate = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        checkUpdate.target = self
        menu.addItem(checkUpdate)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ClipStats", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func showHistory() {
        appsController.hide()
        panelController.show(anchor: statusBar.anchorFrame)
    }

    @objc private func showRunningApps() {
        panelController.hide()
        appsController.model.metrics = latest
        appsController.show(anchor: statusBar.anchorFrame)
    }

    @objc private func togglePause() {
        store.set { $0.clipboardPaused.toggle() }
    }

    @objc private func clearHistory() {
        ClipboardStore.shared.clear()
        statusBar.updateClipboardCount(0)
        panelController.model.reload()
    }

    @objc private func checkForUpdatesFromMenu() {
        panelController.hide()
        appsController?.hide()
        checkForUpdates(manual: true)
    }

    @objc private func openSettings() {
        panelController.hide()
        appsController?.hide()
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
