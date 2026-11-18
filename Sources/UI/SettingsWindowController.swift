import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    let viewModel = SettingsViewModel()

    init(store: SettingsStore) {
        let root = SettingsView(store: store, viewModel: viewModel)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "ClipStats 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 720, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
