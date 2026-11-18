import AppKit
import Combine

// MARK: - 数据模型

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
    var quitState: QuitState = .idle

    var id: pid_t { pid }
}

/// 管理「当前用户打开的应用程序」列表与释放（退出）操作。
///
/// 只取 `activationPolicy == .regular` 的应用（即 Dock 里有图标、由用户打开的应用），
/// 系统守护进程、后台服务天然不在 `NSWorkspace.runningApplications` 的这个范围内。
final class RunningAppsModel: ObservableObject {
    @Published private(set) var apps: [RunningAppItem] = []
    @Published var hoveredPID: pid_t?
    /// 由 AppDelegate 注入：打开设置窗口
    var onOpenSettings: (() -> Void)?

    private var verificationWork: [pid_t: DispatchWorkItem] = [:]

    deinit {
        verificationWork.values.forEach { $0.cancel() }
    }

    // MARK: - 列表

    func reload() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var previous: [pid_t: RunningAppItem.QuitState] = [:]
        for item in apps {
            previous[item.pid] = item.quitState
        }

        var items: [RunningAppItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  !app.isTerminated,
                  app.processIdentifier > 0,
                  app.processIdentifier != ownPID,
                  !Self.isSystemApp(app)
            else { continue }

            var item = RunningAppItem(
                pid: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "未知应用",
                bundleID: app.bundleIdentifier,
                icon: app.icon,
                bundlePath: app.bundleURL?.path,
                launchDate: app.launchDate,
                isActive: app.isActive
            )
            if let state = previous[item.pid] {
                item.quitState = state
            }
            items.append(item)
        }

        // 仅按名称排序：面板成为 key 后前台应用的 isActive 会变化，
        // 若作为排序键会导致列表在鼠标下方重排。
        items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let changed = items.count != apps.count
            || zip(items, apps).contains { $0.pid != $1.pid || $0.name != $1.name || $0.quitState != $1.quitState }
        if changed {
            apps = items
        }

        if let hovered = hoveredPID, !items.contains(where: { $0.pid == hovered }) {
            hoveredPID = nil
        }
    }

    /// Finder、Dock 这类系统常驻应用不展示，避免误操作
    private static func isSystemApp(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier == "com.apple.finder" { return true }
        if let path = app.bundleURL?.path, path.hasPrefix("/System/Library/CoreServices/") {
            return true
        }
        return false
    }

    // MARK: - 释放（退出）

    /// 正常退出：先发 quit Apple Event，失败则退化为 SIGTERM
    func quit(_ item: RunningAppItem) {
        guard let app = runningApp(matching: item) else {
            reload()
            return
        }
        setState(item.pid, .quitting)
        // terminate() 只表示「退出请求是否成功发出」，false 常见原因是进程已经不在了，
        // 也可能是没有 Automation 权限被系统拒绝。绝不降级为发信号，否则会绕过保存流程。
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

    /// 强制退出：NSRunningApplication 强制终止，失败则 SIGKILL
    func forceQuit(_ item: RunningAppItem) {
        guard let app = runningApp(matching: item) else {
            reload()
            return
        }
        setState(item.pid, .quitting)
        // forceTerminate 内部即 SIGKILL，且作用于该应用实例而不是裸 pid
        if !app.forceTerminate() {
            reload()
            return
        }
        verifyExit(pid: item.pid, bundleID: item.bundleID, bundlePath: item.bundlePath, attempt: 0)
    }

    /// 按 pid 找回应用实例，并校验 bundleID，避免 pid 复用后误杀别的进程
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
        // 两样都拿不到就无法确认身份，宁可不操作
        return false
    }

    /// 退出请求发出后轮询确认；3 秒仍未退出则提示可强制退出
    private func verifyExit(pid: pid_t, bundleID: String?, bundlePath: String?, attempt: Int) {
        verificationWork[pid]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let live = NSRunningApplication(processIdentifier: pid)
            let stillRunning = live.map { !$0.isTerminated } ?? false

            if !stillRunning {
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

    func cancelPendingVerifications() {
        verificationWork.values.forEach { $0.cancel() }
        verificationWork.removeAll()
    }
}
