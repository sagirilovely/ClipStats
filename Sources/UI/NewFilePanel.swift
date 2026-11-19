import SwiftUI
import AppKit

/// 「新建文件…」的输入模型（避免使用 @State —— 它依赖仅 Xcode 分发的宏插件）
final class NewFilePanelModel: ObservableObject {
    struct FileType {
        let title: String
        let ext: String
    }

    let types: [FileType] = [
        FileType(title: "Markdown", ext: "md"),
        FileType(title: "文本", ext: "txt"),
        FileType(title: "JSON", ext: "json"),
        FileType(title: "Python", ext: "py"),
        FileType(title: "Shell", ext: "sh"),
        FileType(title: "自定义", ext: "")
    ]

    @Published var directory: URL
    @Published var fileName: String = "未命名"
    @Published var typeIndex: Int = 0
    @Published var customExtension: String = "conf"
    @Published var errorText: String?
    @Published var isSubmitting = false
    @Published var focusRequest = 0

    /// 返回 nil 表示成功，返回字符串表示失败原因
    var onCreate: ((URL, String, String) -> String?)?
    var onCancel: (() -> Void)?

    private static let typeDefaultsKey = "clipstats.finder.lastFileType"

    init(directory: URL) {
        self.directory = directory
        let saved = UserDefaults.standard.integer(forKey: Self.typeDefaultsKey)
        if saved >= 0 && saved < types.count {
            typeIndex = saved
        }
    }

    var isCustomType: Bool { typeIndex == types.count - 1 }

    var resolvedExtension: String {
        isCustomType ? FinderActions.sanitizedExtension(customExtension)
                     : types[typeIndex].ext
    }

    /// 预览最终文件名，减少「建出来不是想要的」的情况
    var previewName: String {
        let base = FinderActions.sanitizedFileName(fileName) ?? "未命名"
        var stem = base
        let ext = resolvedExtension
        if stem.lowercased().hasSuffix("." + ext.lowercased()), stem.count > ext.count + 1 {
            stem = String(stem.dropLast(ext.count + 1))
        }
        return "\(stem).\(ext)"
    }

    func chooseDirectory() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.canCreateDirectories = true
        picker.directoryURL = directory
        picker.prompt = "选择"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        directory = url
        errorText = nil
    }

    func submit() {
        guard !isSubmitting, let onCreate else { return }
        isSubmitting = true
        errorText = nil

        let name = FinderActions.sanitizedFileName(fileName) ?? "未命名"
        let ext = resolvedExtension

        if let message = onCreate(directory, ext, name) {
            errorText = message
            isSubmitting = false
        } else {
            UserDefaults.standard.set(typeIndex, forKey: Self.typeDefaultsKey)
        }
    }

    func requestFocus() {
        focusRequest += 1
    }
}

struct NewFilePanelView: View {
    @ObservedObject var model: NewFilePanelModel
    @FocusState private var nameFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            pathRow
            nameRow
            typeSection

            HStack(spacing: 10) {
                if let error = model.errorText {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Text("将创建 " + model.previewName)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Button("取消") { model.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isSubmitting)

                Button {
                    model.submit()
                } label: {
                    Text(model.isSubmitting ? "创建中…" : "创建")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(minWidth: 52)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSubmitting)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 484, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.requestFocus() }
        .onChange(of: model.focusRequest) { _ in
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private var pathRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(model.directory.path)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("选择…") { model.chooseDirectory() }
                .controlSize(.small)
                .disabled(model.isSubmitting)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7))
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            Text("文件名")
                .font(.system(size: 12))
                .frame(width: 52, alignment: .leading)
            TextField("未命名", text: $model.fileName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .focused($nameFocused)
                .disabled(model.isSubmitting)
                .onSubmit { model.submit() }
                .onChange(of: model.fileName) { _ in model.errorText = nil }
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("类型")
                    .font(.system(size: 12))

                if model.isCustomType {
                    Text("后缀")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    TextField("conf", text: $model.customExtension)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .disabled(model.isSubmitting)
                        .onChange(of: model.customExtension) { _ in model.errorText = nil }
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(model.types.enumerated()), id: \.offset) { index, type in
                    let selected = model.typeIndex == index
                    Button {
                        model.typeIndex = index
                        model.errorText = nil
                    } label: {
                        Text(type.title)
                            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selected
                                          ? Color.accentColor.opacity(0.16)
                                          : Color(nsColor: .controlBackgroundColor).opacity(0.42))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(selected
                                                  ? Color.accentColor.opacity(0.55)
                                                  : Color.primary.opacity(0.07),
                                                  lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting)
                }
            }
        }
    }
}

final class NewFilePanelController {
    static let shared = NewFilePanelController()

    private var panel: NSPanel?
    private var model: NewFilePanelModel?

    private init() {}

    func show(directory: URL) {
        close()

        let model = NewFilePanelModel(directory: directory)
        model.onCancel = { [weak self] in self?.close() }
        model.onCreate = { [weak self] directory, ext, name in
            do {
                let created = try FinderActions.createFile(in: directory, ext: ext, name: name)
                self?.close()
                if let warning = created.permissionWarning {
                    FinderHUD.showFailure(warning)
                } else {
                    FinderHUD.showSuccess("已新建：\(created.url.lastPathComponent)")
                }
                return nil
            } catch {
                let message = (error as? FinderActionError)?.errorDescription ?? error.localizedDescription
                return "未能新建：\(message)"
            }
        }

        let hosting = NSHostingView(rootView: NewFilePanelView(model: model))
        let fitting = hosting.fittingSize
        let contentSize = NSSize(width: 484, height: max(240, fitting.height))

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: contentSize),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "新建文件"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .windowBackgroundColor
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.appearance = SettingsStore.shared.settings.interfaceAppearance.nsAppearance

        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        panel.setContentSize(contentSize)
        panel.center()

        self.model = model
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
    }

    func close() {
        let panel = self.panel
        self.panel = nil
        self.model = nil
        DispatchQueue.main.async {
            panel?.orderOut(nil)
        }
    }
}
