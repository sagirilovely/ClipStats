import AppKit
import Combine

// MARK: - 排序模式

enum MetricMode: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case gpu = "GPU"
    case network = "网速"
    case memory = "内存"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .network: return "network"
        case .memory: return "memorychip"
        }
    }

    var unitTitle: String {
        switch self {
        case .cpu: return "CPU 占用"
        case .gpu: return "GPU 占用"
        case .network: return "网速"
        case .memory: return "内存占用"
        }
    }
}

// MARK: - 条目

struct RunningAppItem: Identifiable {
    enum QuitState {
        case idle
        case quitting
        case needsForce
    }

    let pid: pid_t
    let name: String
    let bundleID: String?
    let icon: NSImage?
    let bundlePath: String?
    let launchDate: Date?
    let isActive: Bool
    let cpu: Double
    let gpu: Double
    let memory: UInt64
    var download: Double = 0
    var upload: Double = 0
    var quitState: QuitState = .idle

    var id: pid_t { pid }
}

/// 管理「用户打开的应用」列表：按当前模式排序，并承载相应的监控详情。
final class RunningAppsModel: ObservableObject {
    @Published private(set) var apps: [RunningAppItem] = []
    /// 排序 / 详情模式，由点击的状态栏模块决定，用户也可在面板内切换
    @Published var mode: MetricMode = .cpu {
        didSet {
            if mode == .network {
                networkMonitor.start()
            } else {
                networkMonitor.stop()
            }
            reload()
            onModeChange?(mode)
        }
    }
    @Published var hoveredPID: pid_t?
    /// 详情卡片用的整机指标（由 AppDelegate 注入最新的快照）
    @Published var metrics: MetricsSnapshot?

    /// 由 AppDelegate 注入
    var onOpenSettings: (() -> Void)?
    var onSwitchToClipboard: (() -> Void)?
    var onModeChange: ((MetricMode) -> Void)?

    private let sampler = ProcessSampler()
    private let networkMonitor = NetworkProcessMonitor()
    private var verificationWork: [pid_t: DispatchWorkItem] = [:]

    init() {
        if mode == .network { networkMonitor.start() }
    }

    deinit {
        verificationWork.values.forEach { $0.cancel() }
    }

    // MARK: - 列表

    func reload() {
        let samples = sampler.sample(includeGPU: mode == .gpu)

        var previousState: [pid_t: RunningAppItem.QuitState] = [:]
        for item in apps {
            previousState[item.pid] = item.quitState
        }

        let networkRates = mode == .network ? networkMonitor.snapshot() : [:]

        var items: [RunningAppItem] = samples.map { sample in
            let app = NSRunningApplication(processIdentifier: sample.pid)
            var item = RunningAppItem(
                pid: sample.pid,
                name: app?.localizedName ?? sample.name,
                bundleID: app?.bundleIdentifier,
                icon: app?.icon,
                bundlePath: app?.bundleURL?.path,
                launchDate: app?.launchDate,
                isActive: app?.isActive ?? false,
                cpu: sample.cpu,
                gpu: sample.gpu,
                memory: sample.memory,
                download: networkRates[sample.pid]?.down ?? 0,
                upload: networkRates[sample.pid]?.up ?? 0
            )
            if let state = previousState[item.pid] {
                item.quitState = state
            }
            return item
        }

        items.sort { lhs, rhs in
            let left = metricValue(lhs)
            let right = metricValue(rhs)
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        apps = items

        if let hovered = hoveredPID, !items.contains(where: { $0.pid == hovered }) {
            hoveredPID = nil
        }
    }

    private func metricValue(_ item: RunningAppItem) -> Double {
        switch mode {
        case .cpu: return item.cpu
        case .gpu: return item.gpu
        case .network: return item.download + item.upload
        case .memory: return Double(item.memory)
        }
    }

    func valueText(for item: RunningAppItem) -> String {
        switch mode {
        case .cpu: return Fmt.percent(item.cpu)
        case .gpu: return item.gpu > 0 ? Fmt.percent(item.gpu) : "—"
        case .network:
            guard item.download + item.upload > 0 else { return "—" }
            return "↓\(Fmt.speed(item.download)) ↑\(Fmt.speed(item.upload))"
        case .memory: return Fmt.bytes(Double(item.memory))
        }
    }

    // MARK: - 释放（退出）

    func quit(_ item: RunningAppItem) {
        guard let app = runningApp(matching: item) else {
            reload()
            return
        }
        setState(item.pid, .quitting)
        // terminate() 只表示请求是否发出；false 通常是进程已退出或没有 Automation 权限
        guard app.terminate() else {
            if let alive = NSRunningApplication(processIdentifier: item.pid), !alive.isTerminated {
                setState(item.pid, .needsForce)
            } else {
                reload()
            }
            return
        }
        verifyExit(pid: item.pid, bundleID: item.bundleID, bundlePath: item.bundlePath, attempt: 0)
    }

    func forceQuit(_ item: RunningAppItem) {
        guard let app = runningApp(matching: item) else {
            reload()
            return
        }
        setState(item.pid, .quitting)
        if !app.forceTerminate() {
            reload()
            return
        }
        verifyExit(pid: item.pid, bundleID: item.bundleID, bundlePath: item.bundlePath, attempt: 0)
    }

    private func runningApp(matching item: RunningAppItem) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else {
            return nil
        }
        return Self.identifies(item, as: app) ? app : nil
    }

    /// 校验 pid 对应的仍然是同一个应用，避免 pid 复用后操作到别的进程
    private static func identifies(_ item: RunningAppItem, as app: NSRunningApplication) -> Bool {
        if let expected = item.bundleID, let actual = app.bundleIdentifier {
            return expected == actual
        }
        if let expectedPath = item.bundlePath, let actualPath = app.executableURL?.path {
            return expectedPath == actualPath
        }
        return false
    }

    private func verifyExit(pid: pid_t, bundleID: String?, bundlePath: String?, attempt: Int) {
        verificationWork[pid]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let alive = NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } ?? false

            if !alive {
                self.verificationWork[pid] = nil
                self.reload()
                return
            }
            if attempt >= 2 {
                self.verificationWork[pid] = nil
                self.setState(pid, .needsForce)
            } else {
                self.verifyExit(pid: pid, bundleID: bundleID, bundlePath: bundlePath, attempt: attempt + 1)
            }
        }
        verificationWork[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func setState(_ pid: pid_t, _ state: RunningAppItem.QuitState) {
        guard let index = apps.firstIndex(where: { $0.pid == pid }) else { return }
        apps[index].quitState = state
    }

    /// 面板关闭时停止 nettop 采样，避免后台常驻开销
    func suspendBackgroundSampling() {
        networkMonitor.stop()
    }

    /// 面板重新打开时，若处于网速模式则恢复采样
    func resumeBackgroundSampling() {
        if mode == .network {
            networkMonitor.start()
        }
    }

    func cancelPendingVerifications() {
        verificationWork.values.forEach { $0.cancel() }
        verificationWork.removeAll()
    }
}
