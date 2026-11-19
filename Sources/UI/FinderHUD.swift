import SwiftUI
import AppKit

/// 轻量结果提示：不抢焦点、不激活 App，停留在屏幕右上角数秒。
final class FinderHUDModel: ObservableObject {
    @Published var text: String = ""
    @Published var symbol: String = "checkmark.circle.fill"
    @Published var tint: Color = .green
}

final class FinderHUDPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FinderHUDController {
    static let shared = FinderHUDController()

    private let model = FinderHUDModel()
    private var panel: FinderHUDPanel?
    private var hostingView: NSHostingView<FinderHUDView>?
    private var hideWork: DispatchWorkItem?

    private init() {}

    func showSuccess(_ text: String) {
        show(text: text, symbol: "checkmark.circle.fill", tint: .green, duration: 2.2)
    }

    func showFailure(_ text: String) {
        show(text: text, symbol: "exclamationmark.triangle.fill", tint: .orange, duration: 3.4)
    }

    func showInfo(_ text: String) {
        show(text: text, symbol: "info.circle.fill", tint: .accentColor, duration: 2.0)
    }

    private func show(text: String, symbol: String, tint: Color, duration: TimeInterval) {
        model.text = text
        model.symbol = symbol
        model.tint = tint

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.appearance = SettingsStore.shared.settings.interfaceAppearance.nsAppearance

        resize(panel)
        position(panel)
        panel.orderFrontRegardless()

        announce(text)

        hideWork?.cancel()
        let effective: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? min(duration, 1.6)
            : duration
        let work = DispatchWorkItem { [weak panel] in
            panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + effective, execute: work)
    }

    private func makePanel() -> FinderHUDPanel {
        let panel = FinderHUDPanel()
        let hosting = NSHostingView(rootView: FinderHUDView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container
        hostingView = hosting
        return panel
    }

    /// 按文本长度自适应宽度，避免长文件名被截断
    private func resize(_ panel: NSPanel) {
        guard let hosting = hostingView else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let width = max(220, min(560, fitting.width + 8))
        let height = max(36, fitting.height)
        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func position(_ panel: NSPanel) {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let screen = screens.first { $0.frame.contains(mouse) } ?? screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 16,
                                     y: visible.maxY - size.height - 10))
    }

    private func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: panel?.contentView as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSNumber(value: NSAccessibilityPriorityLevel.medium.rawValue)])
    }
}

struct FinderHUDView: View {
    @ObservedObject var model: FinderHUDModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.tint)

            Text(model.text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            Capsule().fill(.regularMaterial)
        }
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

/// 方便调用方少写 shared
enum FinderHUD {
    static func showSuccess(_ text: String) { FinderHUDController.shared.showSuccess(text) }
    static func showFailure(_ text: String) { FinderHUDController.shared.showFailure(text) }
    static func showInfo(_ text: String) { FinderHUDController.shared.showInfo(text) }
}
