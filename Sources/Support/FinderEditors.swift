import AppKit

/// 右键菜单里「由 X 打开」的编辑器清单。
///
/// 这份文件同时编译进主 App 和访达扩展，避免两边各写一份导致漂移。
struct FinderEditor {
    let name: String
    /// 留空表示只按 App 名字匹配（适用于 bundle id 不稳定或未知的新 IDE）
    let bundleIDs: [String]
}

enum FinderEditors {

    /// 顺序即菜单顺序：越靠前越常用
    static let known: [FinderEditor] = [
        FinderEditor(name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"]),
        FinderEditor(name: "VS Code", bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium"]),
        FinderEditor(name: "Trae", bundleIDs: ["com.trae.app", "cn.trae.app"]),
        FinderEditor(name: "CodeBuddy", bundleIDs: ["com.tencent.codebuddy", "com.tencent.codebuddycn"]),
        FinderEditor(name: "WebStorm", bundleIDs: ["com.jetbrains.WebStorm"]),
        FinderEditor(name: "CLion", bundleIDs: ["com.jetbrains.CLion"]),
        FinderEditor(name: "IntelliJ IDEA", bundleIDs: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]),
        FinderEditor(name: "Windsurf", bundleIDs: ["com.exafunction.windsurf"]),
        FinderEditor(name: "Antigravity", bundleIDs: ["com.google.antigravity"]),
        FinderEditor(name: "Kiro", bundleIDs: []),
        FinderEditor(name: "Qoder", bundleIDs: []),
        FinderEditor(name: "ZCode", bundleIDs: ["dev.zcode.app"]),
        FinderEditor(name: "PyCharm", bundleIDs: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]),
        FinderEditor(name: "GoLand", bundleIDs: ["com.jetbrains.goland"]),
        FinderEditor(name: "PhpStorm", bundleIDs: ["com.jetbrains.PhpStorm"]),
        FinderEditor(name: "RubyMine", bundleIDs: ["com.jetbrains.ruby"]),
        FinderEditor(name: "Rider", bundleIDs: ["com.jetbrains.rider"]),
        FinderEditor(name: "DataGrip", bundleIDs: ["com.jetbrains.datagrip"]),
        FinderEditor(name: "DataSpell", bundleIDs: ["com.jetbrains.dataspell"]),
        FinderEditor(name: "RustRover", bundleIDs: ["com.jetbrains.rustrover"]),
        FinderEditor(name: "Aqua", bundleIDs: ["com.jetbrains.aqua"]),
        FinderEditor(name: "Fleet", bundleIDs: ["com.jetbrains.fleet"]),
        FinderEditor(name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"]),
        FinderEditor(name: "Android Studio", bundleIDs: ["com.google.android.studio"]),
        FinderEditor(name: "Zed", bundleIDs: ["dev.zed.Zed"]),
        FinderEditor(name: "Sublime Text", bundleIDs: ["com.sublimetext.4", "com.sublimetext.3"]),
        FinderEditor(name: "Nova", bundleIDs: ["com.panic.Nova"]),
        FinderEditor(name: "BBEdit", bundleIDs: ["com.barebones.bbedit"]),
        FinderEditor(name: "TextMate", bundleIDs: ["com.macromates.TextMate"]),
        FinderEditor(name: "Emacs", bundleIDs: ["org.gnu.Emacs"]),
        FinderEditor(name: "MacVim", bundleIDs: ["org.vim.MacVim"]),
        FinderEditor(name: "Neovide", bundleIDs: ["com.neovide.neovide"]),
        FinderEditor(name: "Lapce", bundleIDs: ["dev.lapce.lapce"]),
        FinderEditor(name: "Eclipse", bundleIDs: ["org.eclipse.eclipse"]),
        FinderEditor(name: "NetBeans", bundleIDs: ["org.apache.netbeans"]),
        FinderEditor(name: "Qt Creator", bundleIDs: ["org.qt-project.qtcreator"]),
        FinderEditor(name: "HBuilderX", bundleIDs: ["com.dcloud.HBuilderX"]),
        FinderEditor(name: "RStudio", bundleIDs: ["org.rstudio.RStudio"]),
        FinderEditor(name: "Spyder", bundleIDs: ["org.spyder-ide.spyder"]),
        FinderEditor(name: "Visual Studio", bundleIDs: ["com.microsoft.visual-studio"])
    ]

    /// 名字兜底用的额外关键词（用于 bundle id 不稳定 / 国内特供版）
    private static let extraNeedles: [String: [String]] = [
        "VS Code": ["visual studio code", "vscodium"],
        "Trae": ["trae"],
        "CodeBuddy": ["codebuddy"],
        "Kiro": ["kiro"],
        "Qoder": ["qoder"],
        "Antigravity": ["antigravity"],
        "Windsurf": ["windsurf"]
    ]

    private static var cache: [FinderEditor] = []
    private static var cacheDate = Date.distantPast
    private static let cacheTTL: TimeInterval = 300
    /// 菜单最多列这么多项，避免装了一堆 IDE 时菜单失控
    static let maxCount = 16

    /// 同步返回已安装的编辑器（带 5 分钟缓存）
    static func installed() -> [FinderEditor] {
        if !cache.isEmpty, Date().timeIntervalSince(cacheDate) < cacheTTL {
            return cache
        }
        let result = Array(computeInstalled().prefix(maxCount))
        cache = result
        cacheDate = Date()
        return result
    }

    /// 预热缓存，避免第一次右键时现扫 /Applications
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            _ = installed()
        }
    }

    private static func computeInstalled() -> [FinderEditor] {
        // 先扫 /Applications（沙盒里也能读），拿到真实 bundle id 与显示名；
        // 扫描失败时退回 LaunchServices 查询。
        let scanned = scanApplications()
        var scannedIDs = Set(scanned.map(\.bundleID))
        var usedIDs = Set<String>()
        var result: [FinderEditor] = []

        func add(name: String, bundleID: String) {
            guard usedIDs.insert(bundleID).inserted else { return }
            result.append(FinderEditor(name: name, bundleIDs: [bundleID]))
        }

        for editor in known {
            // 1) bundle id 精确命中
            if let bundleID = editor.bundleIDs.first(where: { candidate in
                if scannedIDs.contains(candidate) { return true }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil {
                    scannedIDs.insert(candidate)
                    return true
                }
                return false
            }) {
                add(name: editor.name, bundleID: bundleID)
                continue
            }

            // 2) 名字兜底：适配 CN 版、改名版、bundle id 未知的新 IDE
            let needles = ([editor.name.lowercased()] + (extraNeedles[editor.name] ?? []))
            if let match = scanned.first(where: { item in
                let lowered = item.name.lowercased()
                return needles.contains { lowered.contains($0) }
            }) {
                add(name: match.name, bundleID: match.bundleID)
            }
        }

        NSLog("FinderEditors: scanned=%d installed=%d", scanned.count, result.count)
        return result
    }

    private struct ScannedApp {
        let name: String
        let bundleID: String
    }

    private static func scanApplications() -> [ScannedApp] {
        let manager = FileManager.default
        var result: [ScannedApp] = []
        var roots: [URL] = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        if let home = try? manager.url(for: .applicationDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: false) {
            roots.append(home)
        }

        for root in roots {
            guard let children = try? manager.contentsOfDirectory(at: root,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) else { continue }
            for child in children where child.pathExtension == "app" {
                guard let bundle = Bundle(url: child),
                      let bundleID = bundle.bundleIdentifier else { continue }
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? child.deletingPathExtension().lastPathComponent
                result.append(ScannedApp(name: displayName, bundleID: bundleID))
            }
        }
        return result
    }
}
