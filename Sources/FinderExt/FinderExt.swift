import Cocoa
import FinderSync

/// 访达右键扩展：在右键菜单里挂一个「ClipStats」二级菜单。
///
/// 扩展运行在系统强制的沙盒里，只能读取路径；
/// 所有写操作（新建文件）通过 clipstats:// URL 交给主 App 执行。
@objc(ClipStatsFinder)
final class ClipStatsFinder: FIFinderSync {

    private enum Command: Int {
        case openTerminal = 1
        case newMarkdown = 3
        case newFilePanel = 4
        /// 编辑器项用 100 + 序号，因为 tag 只能存 Int
        static let editorBase = 100
    }

    private struct Context {
        let directory: URL?
        let target: URL?
        let allowCreate: Bool
    }

    override init() {
        super.init()
        var urls: Set<URL> = [URL(fileURLWithPath: "/")]
        if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                               options: [.skipHiddenVolumes]) {
            urls.formUnion(volumes)
        }
        FIFinderSyncController.default().directoryURLs = urls
        log("init: watching \(urls.count) directories")
        FinderEditors.prewarm()
    }

    // MARK: - 菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }

        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs() ?? []
        let targeted = controller.targetedURL()
        guard let context = resolveContext(selected: selected, targeted: targeted) else { return nil }

        let submenu = NSMenu(title: "ClipStats")

        if context.target != nil {
            let editors = FinderEditors.installed()
            log("menu: editors=\(editors.count) target=\(context.target?.path ?? "-")")
            submenu.addItem(makeItem("在终端中打开", tag: Command.openTerminal.rawValue))
            for (index, editor) in editors.enumerated() {
                let tag = Command.editorBase + index
                submenu.addItem(makeItem("由 \(editor.name) 打开", tag: tag))
            }
        }

        if context.allowCreate, context.directory != nil {
            submenu.addItem(.separator())
            submenu.addItem(makeItem("新建 Markdown 文件", tag: Command.newMarkdown.rawValue))
            submenu.addItem(makeItem("新建文件…", tag: Command.newFilePanel.rawValue))
        }

        guard !submenu.items.isEmpty else { return nil }

        let menu = NSMenu(title: "")
        let root = NSMenuItem(title: "ClipStats", action: nil, keyEquivalent: "")
        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    private func makeItem(_ title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(handleMenu(_:)), keyEquivalent: "")
        item.tag = tag
        item.target = self
        return item
    }

    // MARK: - 动作

    @objc private func handleMenu(_ sender: NSMenuItem) {
        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs() ?? []
        let targeted = controller.targetedURL()
        guard let context = resolveContext(selected: selected, targeted: targeted) else { return }

        if sender.tag >= Command.editorBase {
            let index = sender.tag - Command.editorBase
            let editors = FinderEditors.installed()
            guard index >= 0, index < editors.count,
                  let target = context.target,
                  let bundleID = editors[index].bundleIDs.first else { return }
            send(host: "openfile", items: ["path": target.path, "app": bundleID])
            return
        }

        guard let command = Command(rawValue: sender.tag) else { return }
        switch command {
        case .openTerminal:
            guard let directory = context.directory
                    ?? context.target?.deletingLastPathComponent() else { return }
            send(host: "openterminal", items: ["dir": directory.path])

        case .newMarkdown:
            guard let directory = context.directory, context.allowCreate else { return }
            send(host: "newfile", items: ["dir": directory.path, "ext": "md"])

        case .newFilePanel:
            guard let directory = context.directory, context.allowCreate else { return }
            send(host: "panel", items: ["dir": directory.path])
        }
    }

    // MARK: - 上下文

    private func resolveContext(selected: [URL], targeted: URL?) -> Context? {
        if selected.isEmpty {
            guard let targeted, isDirectory(targeted) else { return nil }
            return Context(directory: targeted, target: targeted, allowCreate: true)
        }

        let directories = selected.filter { isDirectory($0) }
        let files = selected.filter { !isDirectory($0) }

        if !directories.isEmpty && !files.isEmpty {
            return Context(directory: nil, target: selected.first, allowCreate: false)
        }

        if let firstDirectory = directories.first {
            return Context(directory: firstDirectory, target: firstDirectory, allowCreate: true)
        }

        guard let firstFile = files.first else { return nil }
        let parent = firstFile.deletingLastPathComponent()
        return Context(directory: parent, target: firstFile, allowCreate: true)
    }

    /// URL.hasDirectoryPath 只看尾部斜杠，而 FinderSync 的目录 URL 通常没有斜杠
    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return url.hasDirectoryPath
    }

    // MARK: - 发送

    private func send(host: String, items: [String: String]) {
        var components = URLComponents()
        components.scheme = "clipstats"
        components.host = host
        components.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            log("send: 无法构造 URL host=\(host)")
            return
        }
        let sent = NSWorkspace.shared.open(url)
        log("send host=\(host) sent=\(sent)")
    }

    /// 诊断日志：写入扩展自己的沙盒容器 tmp 目录，超过 64 KB 重建
    private func log(_ message: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("finder.log")
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > 64 * 1024 {
            try? FileManager.default.removeItem(at: url)
        }
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
