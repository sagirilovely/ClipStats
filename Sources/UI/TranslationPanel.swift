import AppKit
import Combine
import SwiftUI

// MARK: - 模型

/// 翻译小面板的模型：两个输入框互为输入/输出，编辑任意一侧都会去翻译另一侧。
final class TranslationPanelModel: ObservableObject {
    enum Side { case english, chinese }

    @Published var english = ""
    @Published var chinese = ""
    @Published var statusText = "在任意一侧输入，另一侧自动翻译"
    @Published var busy = false
    @Published var directionTitle = "自动识别方向"
    @Published var needsLanguagePack = false

    /// 关闭面板（由控制器注入）：✕ 按钮和 ESC 走同一条路径
    var onClose: (() -> Void)?

    let service = TranslationService()
    private var cancellables: Set<AnyCancellable> = []

    private var pendingWork: DispatchWorkItem?
    private var applyingRemote = false
    private var targetSide: Side = .chinese

    init() {
        service.onResult = { [weak self] text in
            self?.applyRemote(text)
        }
        service.onError = { [weak self] message in
            guard let self else { return }
            self.busy = false
            self.statusText = message
        }
        if !service.isSupported {
            statusText = "系统翻译需要 macOS 15 及以上"
        }
        service.$needsLanguagePack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.needsLanguagePack = value
            }
            .store(in: &cancellables)
        service.refreshAvailability()
    }

    /// 打开系统的「语言与地区」设置，去下载英汉语言包
    func openLanguageSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Localization-Settings",
            "x-apple.systempreferences:com.apple.preference.language",
        ]
        for text in candidates {
            if let url = URL(string: text), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func retry() {
        needsLanguagePack = false
        service.refreshAvailability()
        let text = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        schedule(text, from: .english)
    }

    func edited(_ side: Side, _ text: String) {
        guard !applyingRemote else { return }
        schedule(text, from: side)
    }

    func close() {
        onClose?()
    }

    func clear() {
        pendingWork?.cancel()
        applyingRemote = true
        english = ""
        chinese = ""
        applyingRemote = false
        busy = false
        directionTitle = "自动识别方向"
        statusText = service.isSupported ? "在任意一侧输入，另一侧自动翻译" : "系统翻译需要 macOS 15 及以上"
    }

    /// 交换两侧内容，不再重新翻译（避免覆盖用户刚得到的结果）
    func swap() {
        pendingWork?.cancel()
        applyingRemote = true
        let previousEnglish = english
        english = chinese
        chinese = previousEnglish
        applyingRemote = false
        busy = false
        statusText = "已交换两侧内容"
    }

    private func schedule(_ text: String, from side: Side) {
        pendingWork?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            busy = false
            statusText = service.isSupported ? "在任意一侧输入，另一侧自动翻译" : "系统翻译需要 macOS 15 及以上"
            return
        }
        targetSide = (side == .english) ? .chinese : .english
        busy = true
        statusText = "翻译中…"

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.service.translate(trimmed)
            if let direction = self.service.lastDirection {
                self.directionTitle = direction.title
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func applyRemote(_ text: String) {
        applyingRemote = true
        switch targetSide {
        case .english: english = text
        case .chinese: chinese = text
        }
        applyingRemote = false
        busy = false
        if let direction = service.lastDirection {
            directionTitle = direction.title
        }
        statusText = "已翻译 · 系统翻译（离线）"
    }
}

// MARK: - 视图

struct TranslationPanelView: View {
    static let panelSize = CGSize(width: 344, height: 188)

    @ObservedObject var model: TranslationPanelModel
    @ObservedObject var store: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedSide: TranslationPanelModel.Side?

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 8) {
                fieldRow(
                    title: "英文",
                    placeholder: "输入英文单词或短语…",
                    side: .english,
                    text: Binding(
                        get: { model.english },
                        set: { model.english = $0; model.edited(.english, $0) }
                    )
                )
                fieldRow(
                    title: "中文",
                    placeholder: "输入中文，自动给出英文…",
                    side: .chinese,
                    text: Binding(
                        get: { model.chinese },
                        set: { model.chinese = $0; model.edited(.chinese, $0) }
                    )
                )
            }
            .padding(.horizontal, 12)

            if model.needsLanguagePack {
                languagePackHint
            }

            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .liquidGlassPanel(cornerRadius: 18)
        .preferredColorScheme(store.settings.interfaceAppearance.colorScheme)
        .background(TranslationTaskHost(service: model.service))
        .onAppear {
            focusedSide = .english
            model.needsLanguagePack = model.service.needsLanguagePack
            model.service.refreshAvailability()
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "translate")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("翻译")
                .font(.system(size: 13, weight: .medium))
            Text(model.directionTitle)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())

            if !model.english.isEmpty || !model.chinese.isEmpty {
                Button {
                    model.clear()
                } label: {
                    Text("清空")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .help("清空两侧内容")
                .accessibilityLabel("清空两侧内容")
            }

            Spacer(minLength: 6)

            Button {
                model.swap()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(LiquidGlassIconButtonStyle())
            .help("交换两侧内容")
            .accessibilityLabel("交换两侧内容")

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(LiquidGlassIconButtonStyle())
            .help("关闭")
            .accessibilityLabel("关闭翻译面板")
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    private func fieldRow(
        title: String,
        placeholder: String,
        side: TranslationPanelModel.Side,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .focused($focusedSide, equals: side)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidGlassControl(cornerRadius: LiquidGlassMetrics.concentric(inset: 12, outer: 18), isActive: focusedSide == side)
    }

    private var languagePackHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("系统还没下载英汉语言包，翻译会失败")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Button("去设置") {
                model.openLanguageSettings()
            }
            .buttonStyle(LiquidGlassButtonStyle())
            Button("重试") {
                model.retry()
            }
            .buttonStyle(LiquidGlassButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.busy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.62)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4))
                    .foregroundStyle(.tertiary)
            }
            Text(model.statusText)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Text("⌘V 粘贴 · ⌘C 复制")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - 面板

private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

final class TranslationPanelController: NSObject, NSWindowDelegate {
    let model = TranslationPanelModel()

    private let store: SettingsStore
    private var panel: TranslationPanel?
    private var keyMonitor: Any?

    var onVisibilityChange: ((Bool) -> Void)?

    init(store: SettingsStore = .shared) {
        self.store = store
        super.init()
        model.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    var panelContentView: NSView? { panel?.contentView }

    func show(anchor: NSRect) {
        let panel = ensurePanel()
        panel.appearance = store.settings.interfaceAppearance.nsAppearance
        let size = TranslationPanelView.panelSize
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 8)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                origin.y = anchor.maxY + 8
            }
        }
        panel.setFrameOrigin(origin)
        panel.invalidateShadow()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        PanelPresentation.present(panel)
        installKeyMonitor()
        onVisibilityChange?(true)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.panel?.invalidateShadow()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeKeyMonitor()
        onVisibilityChange?(false)
        PanelPresentation.dismiss(panel)
    }

    func toggle(anchor: NSRect) {
        if isVisible { hide() } else { show(anchor: anchor) }
    }

    func applyAppearance(_ mode: InterfaceAppearance) {
        panel?.appearance = mode.nsAppearance
    }

    private func ensurePanel() -> TranslationPanel {
        if let panel { return panel }
        let size = TranslationPanelView.panelSize
        let panel = TranslationPanel(
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

        let hosting = NSHostingController(rootView: TranslationPanelView(model: model, store: store))
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        // 裁成和玻璃一致的圆角，否则系统玻璃的阴影会被窗口矩形切出直角黑边
        hosting.view.layer?.cornerRadius = 18
        hosting.view.layer?.masksToBounds = true
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
