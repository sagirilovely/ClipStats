import Foundation
import Combine
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case statusBar = "状态栏"
    case appearance = "外观"
    case sampling = "刷新频率"
    case clipboard = "剪贴板"
    case hotkey = "快捷键"
    case about = "关于"
    var id: String { rawValue }

    var key: String {
        switch self {
        case .statusBar: return "statusbar"
        case .appearance: return "appearance"
        case .sampling: return "sampling"
        case .clipboard: return "clipboard"
        case .hotkey: return "hotkey"
        case .about: return "about"
        }
    }
}

/// 设置界面的临时状态（避免使用 @State —— 它依赖仅 Xcode 分发的宏插件）
final class SettingsViewModel: ObservableObject {
    @Published var tab: SettingsTab = .statusBar
    @Published var recording = false
    @Published var clipboardCount = 0

    private var keyMonitor: Any?

    func refreshCount() {
        clipboardCount = ClipboardStore.shared.count()
    }

    func startRecording(store: SettingsStore) {
        stopRecording()
        recording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else { return nil }
            let config = HotKeyConfig(
                keyCode: UInt32(event.keyCode),
                modifiers: KeyCodeText.carbonModifiers(flags),
                display: KeyCodeText.display(keyCode: event.keyCode, modifiers: flags)
            )
            store.set { $0.hotKey = config }
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        recording = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
