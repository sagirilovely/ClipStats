import AppKit
import Foundation

// MARK: - 更新信息

struct UpdateRelease: Equatable {
    /// 去掉 v 前缀的版本号，例如 1.2.0
    let version: String
    /// 原始 tag，例如 v1.2.0
    let tag: String
    let pageURL: URL
    let dmgURL: URL?
    let notes: String
    let publishedAt: Date?
}

// MARK: - 检查器

/// 通过 GitHub Releases 检查新版本，并负责把 dmg 下载到「下载」目录。
///
/// 设计要点：
/// - 只发一次 GET /releases/latest（带 User-Agent 与 If-None-Match，304 时零负载）；
/// - 24 小时内不重复请求（lastCheck 持久化），失败也不弹窗打扰；
/// - 同一版本只提醒一次（skippedVersion）。
final class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(UpdateRelease)
        case downloading(progress: Double)
        case downloaded(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// 自动检查发现有新版本时回调（主线程）
    var onAvailable: ((UpdateRelease) -> Void)?

    private let owner = "sagirilovely"
    private let repo = "ClipStats"
    private let cooldown: TimeInterval = 24 * 60 * 60

    private let plainSession = URLSession(configuration: .ephemeral)
    private lazy var downloadSession = URLSession(
        configuration: .ephemeral,
        delegate: self,
        delegateQueue: nil
    )

    private var checkTask: URLSessionDataTask?
    private var downloadTask: URLSessionDownloadTask?
    /// 上次被 GitHub 限流时服务器给出的重置时间
    private(set) var rateLimitedUntil: Date?
    private var pendingRelease: UpdateRelease?

    private enum Keys {
        static let lastCheck = "clipstats.update.lastCheck"
        static let skipped = "clipstats.update.skippedVersion"
    }

    /// 当前 App 版本；自检时可用 CLIPSTATS_FAKE_VERSION 覆盖
    var currentVersion: String {
        if let fake = ProcessInfo.processInfo.environment["CLIPSTATS_FAKE_VERSION"], !fake.isEmpty {
            return fake
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var lastCheckDate: Date? {
        let stamp = UserDefaults.standard.double(forKey: Keys.lastCheck)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    var skippedVersion: String? {
        UserDefaults.standard.string(forKey: Keys.skipped)
    }

    /// 距离上次检查是否还在 24 小时冷却期内
    var isCoolingDown: Bool {
        guard let last = lastCheckDate else { return false }
        return Date().timeIntervalSince(last) < cooldown
    }

    // MARK: - 检查

    /// 自动检查：冷却期内直接跳过
    func checkIfNeeded() {
        guard !isCoolingDown else { return }
        check(automatic: true)
    }

    func check(automatic: Bool) {
        guard #available(macOS 13, *) else { return }
        checkTask?.cancel()
        state = .checking

        // 自检：强制走 302 兜底路径（模拟 API 被限流）
        if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_FORCE_REDIRECT"] == "1" {
            checkViaRedirect(automatic: automatic)
            return
        }
        // 还在服务器给的重置时间内：自动检查直接走不占配额的兜底路径
        if automatic, let reset = rateLimitedUntil, reset > Date() {
            checkViaRedirect(automatic: automatic)
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            state = .failed("更新地址无效")
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let task = plainSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handle(data: data, response: response, error: error, automatic: automatic)
            }
        }
        checkTask = task
        task.resume()
    }

    private func handle(data: Data?, response: URLResponse?, error: Error?, automatic: Bool) {
        if let error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            state = .failed(automatic ? "" : "检查失败：\(error.localizedDescription)")
            if !automatic { markChecked() }
            return
        }
        guard let http = response as? HTTPURLResponse else {
            state = .failed(automatic ? "" : "检查失败：无响应")
            return
        }

        if http.statusCode == 403 {
            // 未认证的 API 每小时只有 60 次（按 IP 计）。这里不直接放弃，
            // 而是改走 github.com/releases/latest 的 302 跳转读出版本号——这条路不消耗 API 配额。
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init)
            if let reset {
                rateLimitedUntil = Date(timeIntervalSince1970: reset)
            }
            checkViaRedirect(automatic: automatic)
            return
        }
        guard http.statusCode == 200, let data else {
            state = .failed(automatic ? "" : "检查失败（HTTP \(http.statusCode)）")
            return
        }
        do {
            let payload = try JSONDecoder().decode(LatestRelease.self, from: data)
            markChecked()
            present(payload: payload, automatic: automatic)
        } catch {
            state = .failed(automatic ? "" : "解析更新信息失败")
        }
    }

    private func present(payload: LatestRelease, automatic: Bool) {
        let remote = payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard !payload.prerelease, !payload.draft else {
            state = .upToDate(currentVersion)
            return
        }
        guard Self.isNewer(remote, than: currentVersion) else {
            state = .upToDate(currentVersion)
            return
        }

        let pageURL = URL(string: payload.htmlURL) ?? URL(string: "https://github.com/\(owner)/\(repo)/releases")!
        let dmg = payload.assets
            .first { $0.name.lowercased().hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browserDownloadURL) }
        let release = UpdateRelease(
            version: remote,
            tag: payload.tagName,
            pageURL: pageURL,
            dmgURL: dmg,
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            publishedAt: payload.publishedAt.flatMap(Self.dateFormatter.date)
        )
        state = .available(release)

        if automatic, skippedVersion == remote { return }
        onAvailable?(release)
    }

    /// 兜底：请求 GitHub 的 release 页面（服务端 302 到 /releases/tag/vX.Y.Z），
    /// 让 URLSession 跟着跳转，从最终 URL 里取出 tag。没有更新说明与资产列表，
    /// dmg 链接按我们的打包命名约定拼出来。
    private func checkViaRedirect(automatic: Bool) {
        guard let url = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest") else {
            state = .failed(automatic ? "" : "GitHub 接口限流，请稍后再试")
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        plainSession.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.state = .failed(automatic ? "" : "检查失败：\(error.localizedDescription)")
                    return
                }
                guard let finalURL = response?.url else {
                    self.state = .failed(automatic ? "" : "GitHub 接口限流，稍后会自动重试")
                    return
                }
                let tag = finalURL.lastPathComponent
                guard tag.hasPrefix("v"), tag.count > 1 else {
                    self.state = .failed(automatic ? "" : "GitHub 接口限流，稍后会自动重试")
                    return
                }
                self.markChecked()
                self.rateLimitedUntil = nil
                let version = String(tag.dropFirst())
                guard Self.isNewer(version, than: self.currentVersion) else {
                    self.state = .upToDate(self.currentVersion)
                    return
                }
                let dmg = URL(string: "https://github.com/\(self.owner)/\(self.repo)/releases/download/\(tag)/ClipStats-\(version)-macos-universal.dmg")
                let release = UpdateRelease(
                    version: version,
                    tag: tag,
                    pageURL: finalURL,
                    dmgURL: dmg,
                    notes: "",
                    publishedAt: nil
                )
                self.state = .available(release)
                if automatic, self.skippedVersion == version { return }
                self.onAvailable?(release)
            }
        }.resume()
    }

    private func markChecked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheck)
    }

    // MARK: - 操作

    /// 不再提示这个版本（下次检查仍会进行，只是不弹窗）
    func skip(_ release: UpdateRelease) {
        UserDefaults.standard.set(release.version, forKey: Keys.skipped)
    }

    func resetSkippedVersion() {
        UserDefaults.standard.removeObject(forKey: Keys.skipped)
    }

    /// 安装包落地目录：~/Library/Application Support/ClipStats/Updates
    static func updateDirectory() -> URL {
        // 自检 / 便携运行时可用 CLIPSTATS_UPDATE_DIR 指定落地点
        if let override = ProcessInfo.processInfo.environment["CLIPSTATS_UPDATE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClipStats/Updates", isDirectory: true)
    }

    /// 启动时清理旧的安装包（只保留最近一个）
    func cleanUpOldDownloads(keeping name: String? = nil) {
        let folder = Self.updateDirectory()
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent != name {
            try? FileManager.default.removeItem(at: item)
        }
    }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    func download(_ release: UpdateRelease) {
        guard !isDownloading else { return }
        guard let dmgURL = release.dmgURL else {
            state = .failed("这个版本没有 dmg 安装包")
            return
        }
        pendingRelease = release
        state = .downloading(progress: 0)

        let task = downloadSession.downloadTask(with: dmgURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if let release = pendingRelease {
            state = .available(release)
        } else {
            state = .idle
        }
    }

    /// 打开已下载的 dmg（挂载后由用户拖进 Applications）
    func openDownloaded() {
        if case .downloaded(let url) = state {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 工具

    private var userAgent: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
        return "ClipStats/\(currentVersion) (\(os))"
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        let right = current.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - 下载进度

extension UpdateChecker: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.state = .downloading(progress: progress) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let name = downloadTask.response?.suggestedFilename ?? "ClipStats.dmg"
        // 存到自己的数据目录：~/Downloads 受 TCC 保护，非沙盒应用首次写入会弹权限框甚至被拒，
        // 而 Application Support 里的目录不需要任何额外授权。
        let folder = Self.updateDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            DispatchQueue.main.async {
                self.state = .downloaded(destination)
                self.downloadTask = nil
                let open = ProcessInfo.processInfo.environment["CLIPSTATS_DIAG_SKIP_OPEN"] != "1"
                if open { NSWorkspace.shared.open(destination) }
            }
        } catch {
            DispatchQueue.main.async { self.state = .failed("保存安装包失败：\(error.localizedDescription)") }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            if let release = self.pendingRelease {
                self.state = .available(release)
            } else {
                self.state = .failed("下载失败：\(error.localizedDescription)")
            }
        }
    }
}

// MARK: - GitHub JSON

private struct LatestRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: String
    let body: String?
    let prerelease: Bool
    let draft: Bool
    let publishedAt: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, prerelease, draft
        case publishedAt = "published_at"
        case assets
    }
}
