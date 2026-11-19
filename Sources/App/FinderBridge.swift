import AppKit

/// 接收访达扩展通过 clipstats:// URL 发来的请求。
///
/// 访达扩展被系统强制沙盒化，无法直接往用户目录写文件，
/// 所以由主 App（未沙盒）代执行：新建文件、打开终端 / 编辑器。
final class FinderBridge {

    static let shared = FinderBridge()

    private static let scheme = "clipstats"

    private init() {}

    /// 在启动早期调用，才能收到冷启动时的 URL 事件。
    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleEvent(_ event: NSAppleEventDescriptor,
                                   withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw) else { return }
        handle(url)
    }

    /// 命令行 / 其他 App 也走同一条路径，便于排查
    func handle(_ url: URL) {
        guard url.scheme == Self.scheme, let host = url.host else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        switch host {
        case "newfile":
            guard let directory = value("dir"), let ext = value("ext") else { return }
            createFile(in: directory, ext: ext, name: value("name"))

        case "panel":
            guard let directory = value("dir") else { return }
            NewFilePanelController.shared.show(directory: URL(fileURLWithPath: directory, isDirectory: true))

        case "openterminal":
            guard let directory = value("dir") else { return }
            FinderActions.openTerminal(at: URL(fileURLWithPath: directory, isDirectory: true))

        case "openfile":
            guard let path = value("path"), let bundleID = value("app") else { return }
            FinderActions.open(paths: [URL(fileURLWithPath: path)], bundleID: bundleID)

        default:
            break
        }
    }

    private func createFile(in directory: String, ext: String, name: String?) {
        let target = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            let created = try FinderActions.createFile(in: target, ext: ext, name: name)
            if let warning = created.permissionWarning {
                FinderHUD.showFailure(warning)
            } else {
                FinderHUD.showSuccess("已新建：\(created.url.lastPathComponent)")
            }
        } catch {
            let message = (error as? FinderActionError)?.errorDescription ?? error.localizedDescription
            FinderHUD.showFailure("未能新建：\(message)")
            NSSound.beep()
        }
    }
}
