import AppKit
import Combine
import FinderSync

/// 访达扩展的启用状态检测与启用操作。
final class FinderExtensionManager: ObservableObject {

    static let shared = FinderExtensionManager()

    enum Status: Equatable {
        case enabled
        case disabled
        case unregistered
        case unknown
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var lastChecked: Date?
    @Published private(set) var isWorking = false
    @Published private(set) var pluginUUID: String?

    let extensionBundleID = "local.sagiri.clipstats.finder"

    private var pollingToken = 0

    private init() {}

    var isSequoia: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 15
    }

    var extensionURL: URL? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("PlugIns")
            .appendingPathComponent("ClipStatsFinder.appex")
    }

    var statusText: String {
        switch status {
        case .enabled: return "已启用"
        case .disabled: return "未启用"
        case .unregistered: return "扩展未注册"
        case .unknown: return "正在检测…"
        }
    }

    var pluginkitCommand: String {
        if let uuid = pluginUUID {
            return "pluginkit -e use -u \(uuid)"
        }
        return "pluginkit -e use -i \(extensionBundleID)"
    }

    // MARK: - 检测

    func refresh() {
        guard let url = extensionURL, FileManager.default.fileExists(atPath: url.path) else {
            status = .unregistered
            lastChecked = Date()
            return
        }
        status = FIFinderSyncController.isExtensionEnabled ? .enabled : .disabled
        lastChecked = Date()

        if pluginUUID == nil {
            loadPluginUUIDInBackground()
        }
    }

    /// 用户在系统设置里勾选后，状态不会立刻同步，轮询几次更友好
    func refreshWithPolling(attempts: Int = 6, interval: TimeInterval = 1.0) {
        pollingToken += 1
        let token = pollingToken
        refresh()
        poll(token: token, remaining: attempts, interval: interval)
    }

    private func poll(token: Int, remaining: Int, interval: TimeInterval) {
        guard remaining > 1, token == pollingToken, status != .enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self, token == self.pollingToken else { return }
            if self.status == .enabled { return }
            self.status = FIFinderSyncController.isExtensionEnabled ? .enabled : .disabled
            self.lastChecked = Date()
            self.poll(token: token, remaining: remaining - 1, interval: interval)
        }
    }

    // MARK: - 启用

    func enableWithPluginkit() {
        guard !isWorking else { return }
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let uuid = self.pluginUUID ?? self.fetchPluginUUID()
            if let uuid {
                _ = Self.runPluginkit(["-e", "use", "-u", uuid])
            }
            DispatchQueue.main.async {
                self.pluginUUID = uuid
                self.isWorking = false
                self.refreshWithPolling(attempts: 4)
            }
        }
    }

    private func loadPluginUUIDInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let uuid = self.fetchPluginUUID()
            DispatchQueue.main.async {
                if self.pluginUUID == nil {
                    self.pluginUUID = uuid
                }
            }
        }
    }

    private func fetchPluginUUID() -> String? {
        guard let output = Self.runPluginkit(["-mAD", "-p", "com.apple.FinderSync", "-vvv"],
                                             capture: true) else {
            return nil
        }
        // 按条目切块：先出现 Path，再出现 UUID
        var inOurBlock = false
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.contains(extensionBundleID) || line.contains("ClipStatsFinder.appex") {
                inOurBlock = true
                continue
            }
            guard inOurBlock else { continue }
            if let range = line.range(of: "UUID = ") {
                let uuid = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return uuid.isEmpty ? nil : uuid
            }
            // 出现下一条 Path 说明已经跨条目了
            if line.contains("Path = ") {
                inOurBlock = false
            }
        }
        return nil
    }

    @discardableResult
    private static func runPluginkit(_ arguments: [String], capture: Bool = false) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = capture ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("FinderExtensionManager: pluginkit 启动失败 %@", error.localizedDescription)
            return nil
        }
        // 必须先读管道再等退出，否则输出超过缓冲区会死锁
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard capture else { return "" }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 系统设置 / 访达

    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func reloadFinder() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Finder"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var ok = false
            do {
                try process.run()
                process.waitUntilExit()
                ok = process.terminationStatus == 0
            } catch {
                ok = false
            }
            DispatchQueue.main.async {
                if ok {
                    FinderHUD.showInfo("已重新加载访达")
                } else {
                    FinderHUD.showFailure("未能重新加载访达")
                }
                self?.refresh()
            }
        }
    }

    // MARK: - 权限

    /// 提前触发桌面 / 文稿 / 下载的 TCC 授权，避免第一次右键时被拦
    func requestProtectedFolderAccess() {
        let manager = FileManager.default
        let folders: [FileManager.SearchPathDirectory] = [.desktopDirectory,
                                                          .documentDirectory,
                                                          .downloadsDirectory]
        var granted = 0
        for folder in folders {
            guard let url = try? manager.url(for: folder, in: .userDomainMask,
                                             appropriateFor: nil, create: false) else { continue }
            let probe = url.appendingPathComponent(".clipstats-tcc-\(UUID().uuidString)")
            do {
                try Data().write(to: probe, options: .withoutOverwriting)
                try? manager.removeItem(at: probe)
                granted += 1
            } catch {
                // 用户拒绝授权或目录不可写，保持沉默即可
            }
        }
        if granted > 0 {
            FinderHUD.showSuccess("已完成 \(granted) 个文件夹的授权检查")
        } else {
            FinderHUD.showFailure("未能获得文件夹授权，可在系统设置中手动允许")
        }
    }
}
