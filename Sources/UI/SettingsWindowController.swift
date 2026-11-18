import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let viewModel = SettingsViewModel()
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        let root = SettingsView(store: store, viewModel: viewModel)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "ClipStats 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 760, height: 600))
        window.titlebarAppearsTransparent = true
        window.appearance = store.settings.interfaceAppearance.nsAppearance
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.appearance = store.settings.interfaceAppearance.nsAppearance
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func applyAppearance(_ mode: InterfaceAppearance) {
        window?.appearance = mode.nsAppearance
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(nil)
        return false
    }
}
