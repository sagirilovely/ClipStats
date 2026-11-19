import AppKit
import SwiftUI

// MARK: - 视图

struct UpdatePanelView: View {
    static let panelSize = CGSize(width: 384, height: 252)

    @ObservedObject var checker: UpdateChecker
    @ObservedObject var store: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    let onClose: () -> Void
    let onDownload: (UpdateRelease) -> Void
    let onOpenPage: (UpdateRelease) -> Void
    let onSkip: (UpdateRelease) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            body(for: checker.state)
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .liquidGlassPanel(cornerRadius: 18)
        .preferredColorScheme(store.settings.interfaceAppearance.colorScheme)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LiquidGlassStyle.accentGradient)
            Text("软件更新")
                .font(.system(size: 13, weight: .medium))
            Text("当前 v" + checker.currentVersion)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())

            Spacer(minLength: 6)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(LiquidGlassIconButtonStyle())
            .help("关闭")
            .accessibilityLabel("关闭更新窗口")
        }
    }

    // MARK: 主体

    @ViewBuilder
    private func body(for state: UpdateChecker.State) -> some View {
        switch state {
        case .idle, .checking:
            centered {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                    Text("正在检查更新…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

        case .upToDate(let version):
            centered {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.green.opacity(0.85))
                    Text("当前已是最新版本")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("v" + version)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let last = checker.lastCheckDate {
                        Text("上次检查：" + Fmt.relativeTime(last))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

        case .available(let release):
            available(release)

        case .downloading(let progress):
            centered {
                VStack(spacing: 10) {
                    Text("正在下载安装包…")
                        .font(.system(size: 12, weight: .medium))
                    ProgressView(value: max(0.02, progress))
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

        case .downloaded(let url):
            centered {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.green.opacity(0.85))
                    Text("安装包已下载并打开")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("把 ClipStats 拖进 Applications 覆盖旧版本即可完成更新")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(url.lastPathComponent)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

        case .failed(let message):
            centered {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(message.isEmpty ? "检查更新失败" : message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func available(_ release: UpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("发现新版本")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("v" + checker.currentVersion + " → v" + release.version)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if let date = release.publishedAt {
                    Text(Fmt.dayFormatter.string(from: date))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView {
                Text(release.notes.isEmpty ? "这个版本没有抓到更新说明，可以点「查看 Release」到 GitHub 上看。" : Self.plainNotes(release.notes))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 118)
        }
        .padding(.top, 10)
    }

    /// GitHub release 正文是 markdown；这里只去掉粗体标记，保留列表符号
    private static func plainNotes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .split(separator: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix(">") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) : String(line)
            }
            .joined(separator: "\n")
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 10)
    }

    // MARK: 底部按钮

    @ViewBuilder
    private var footer: some View {
        switch checker.state {
        case .available(let release):
            HStack(spacing: 8) {
                Button {
                    onDownload(release)
                } label: {
                    Text("下载并安装")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true))
                .disabled(release.dmgURL == nil)

                Button("查看 Release") { onOpenPage(release) }
                    .buttonStyle(LiquidGlassButtonStyle())

                Spacer(minLength: 2)

                Button("跳过此版本") { onSkip(release) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)

                Button("稍后") { onClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

        case .downloading:
            HStack {
                Spacer()
                Button("取消") { checker.cancelDownload() }
                    .buttonStyle(LiquidGlassButtonStyle())
            }

        case .downloaded:
            HStack(spacing: 8) {
                Button { checker.openDownloaded() } label: {
                    Text("再打开一次")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true))
                Spacer()
                Button("完成") { onClose() }
                    .buttonStyle(LiquidGlassButtonStyle())
            }

        case .failed(let message):
            HStack(spacing: 8) {
                if !message.isEmpty {
                    Button("重试") { onRetry() }
                        .buttonStyle(LiquidGlassButtonStyle())
                }
                Spacer()
                Button("关闭") { onClose() }
                    .buttonStyle(LiquidGlassButtonStyle())
            }

        default:
            HStack {
                Spacer()
                Button("关闭") { onClose() }
                    .buttonStyle(LiquidGlassButtonStyle())
            }
        }
    }
}

// MARK: - 面板

private final class UpdatePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class UpdatePanelController: NSObject, NSWindowDelegate {
    private let checker: UpdateChecker
    private let store: SettingsStore
    private var panel: UpdatePanel?
    private var keyMonitor: Any?

    var onVisibilityChange: ((Bool) -> Void)?

    init(checker: UpdateChecker = .shared, store: SettingsStore = .shared) {
        self.checker = checker
        self.store = store
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var panelContentView: NSView? { panel?.contentView }

    func show(anchor: NSRect) {
        let panel = ensurePanel()
        panel.appearance = store.settings.interfaceAppearance.nsAppearance
        let size = UpdatePanelView.panelSize
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 8)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 { origin.y = anchor.maxY + 8 }
        }
        panel.setFrameOrigin(origin)
        panel.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        onVisibilityChange?(true)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        removeKeyMonitor()
        onVisibilityChange?(false)
    }

    func applyAppearance(_ mode: InterfaceAppearance) {
        panel?.appearance = mode.nsAppearance
    }

    private func ensurePanel() -> UpdatePanel {
        if let panel { return panel }
        let size = UpdatePanelView.panelSize
        let panel = UpdatePanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hide() }

        let root = UpdatePanelView(
            checker: checker,
            store: store,
            onClose: { [weak self] in self?.hide() },
            onDownload: { [weak self] release in self?.checker.download(release) },
            onOpenPage: { release in NSWorkspace.shared.open(release.pageURL) },
            onSkip: { [weak self] release in
                self?.checker.skip(release)
                self?.hide()
            },
            onRetry: { [weak self] in self?.checker.check(automatic: false) }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.frame = NSRect(origin: .zero, size: size)
        panel.contentViewController = hosting
        panel.setContentSize(size)
        panel.invalidateShadow()
        self.panel = panel
        return panel
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
