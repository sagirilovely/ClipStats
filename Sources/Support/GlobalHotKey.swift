import AppKit
import Carbon.HIToolbox

/// 基于 Carbon RegisterEventHotKey 的全局快捷键，无需辅助功能授权。
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    func register(_ config: HotKeyConfig?, action: @escaping () -> Void) {
        unregister()
        self.action = action
        guard let config, config.modifiers != 0 else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.action?() }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        var hotKeyID = EventHotKeyID(signature: OSType(0x43534B59), id: 1) // 'CSKY'
        let status = RegisterEventHotKey(config.keyCode, config.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("ClipStats: register hotkey failed: \(status)")
        }
        _ = hotKeyID
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

// MARK: - 按键显示

enum KeyCodeText {
    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13",
        115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func display(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        text += key(for: keyCode)
        return text
    }

    static func key(for keyCode: UInt16) -> String {
        if let name = special[keyCode] { return name }
        // 用当前键盘布局把虚拟键码翻译成字符
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
