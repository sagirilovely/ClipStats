import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
        .frame(width: 720, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { viewModel.refreshCount() }
        .onDisappear { viewModel.stopRecording() }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    viewModel.tab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: viewModel.tab == tab ? .semibold : .regular))
                        .foregroundStyle(viewModel.tab == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(viewModel.tab == tab ? Color.primary.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.tab {
        case .statusBar: statusBarTab
        case .appearance: appearanceTab
        case .sampling: samplingTab
        case .clipboard: clipboardTab
        case .hotkey: hotkeyTab
        case .about: aboutTab
        }
    }

    // MARK: - 状态栏

    private var statusBarTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewBar
            Text("拖拽或使用上下箭头调整顺序；关闭开关即可隐藏该模块。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(store.settings.segments.enumerated()), id: \.element.kind) { index, segment in
                    segmentRow(index: index, segment: segment)
                }
                .onMove { store.moveSegment(from: $0, to: $1) }
            }

            HStack(spacing: 16) {
                Toggle("CPU 数值后附带温度", isOn: binding(\.showCPUWithTemperature))
                Toggle("开机自动启动", isOn: binding(\.launchAtLogin))
            }
            .font(.system(size: 12))

            HStack(spacing: 8) {
                Text("温度取值").font(.system(size: 12))
                Picker("", selection: binding(\.temperatureMode)) {
                    ForEach(TemperatureMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                Text("平均值更平滑，最高值反映最热传感器")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("字号").font(.system(size: 12))
                Slider(value: binding(\.barFontSize), in: 10...16, step: 1)
                    .frame(width: 160)
                Text("\(Int(store.settings.barFontSize)) pt")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func segmentRow(index: Int, segment: SegmentConfig) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: binding(\.segments[index].enabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

            Image(systemName: segment.kind.symbolName)
                .frame(width: 18)
                .foregroundStyle(segment.enabled ? Color.primary : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(segment.kind.title).font(.system(size: 12.5))
                Text(segment.kind.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("图标", isOn: binding(\.segments[index].showIcon))
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Toggle("数值", isOn: binding(\.segments[index].showText))
                .toggleStyle(.checkbox)
                .controlSize(.small)

            VStack(spacing: 2) {
                Button { move(index, by: -1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                Button { move(index, by: 1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .disabled(index >= store.settings.segments.count - 1)
            }
        }
        .padding(.vertical, 3)
    }

    private var previewBar: some View {
        HStack(spacing: 12) {
            Text("预览").font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(store.settings.segments.filter { $0.enabled }) { segment in
                    HStack(spacing: 4) {
                        if segment.showIcon {
                            Image(systemName: segment.kind.symbolName).font(.system(size: 10))
                        }
                        if segment.showText {
                            Text(sampleText(segment.kind))
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Spacer()
        }
    }

    private func sampleText(_ kind: SegmentKind) -> String {
        switch kind {
        case .cpu: return "23% 62°"
        case .gpu: return "48%"
        case .memory: return "68%"
        case .thermal: return "62°"
        case .network: return "↓1.2M ↑86K"
        case .clipboard: return "36"
        }
    }

    // MARK: - 外观

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("尺寸与间距")
                sliderRow("字号", value: binding(\.barFontSize), range: 10...16, step: 1, suffix: "pt")
                sliderRow("图标大小", value: binding(\.appearance.iconPointSize), range: 8...18, step: 1, suffix: "pt")
                sliderRow("列间距", value: binding(\.appearance.segmentSpacing), range: 0...20, step: 1, suffix: "pt")
                sliderRow("左右边距", value: binding(\.appearance.horizontalPadding), range: 0...20, step: 1, suffix: "pt")

                HStack(spacing: 10) {
                    Text("数值对齐").font(.system(size: 12)).frame(width: 72, alignment: .leading)
                    Picker("", selection: binding(\.appearance.textAlignment)) {
                        ForEach(BarTextAlignment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                    Spacer()
                }

                Toggle("固定宽度（数值变化时不抖动）", isOn: binding(\.stabilizeBarWidth))
                    .font(.system(size: 12))
                Text("开启后每个模块按最大数值预留槽位；关掉则按实际内容自适应，但温度、网速变化时栏宽会跳动。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Divider()

                sectionTitle("背景")
                HStack(spacing: 10) {
                    Text("样式").font(.system(size: 12)).frame(width: 72, alignment: .leading)
                    Picker("", selection: binding(\.appearance.backgroundStyle)) {
                        ForEach(BarBackgroundStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Spacer()
                }
                if store.settings.appearance.backgroundStyle != .none {
                    ColorPicker("背景颜色", selection: colorBinding(\.appearance.backgroundColor), supportsOpacity: false)
                        .font(.system(size: 12))
                    if store.settings.appearance.backgroundStyle == .solid {
                        sliderRow("不透明度", value: binding(\.appearance.backgroundOpacity),
                                  range: 0.05...1, step: 0.05, suffix: "", format: "%.2f")
                    }
                    sliderRow("圆角", value: binding(\.appearance.cornerRadius), range: 0...14, step: 1, suffix: "pt")
                }

                Divider()

                sectionTitle("文字")
                Toggle("自定义字体颜色", isOn: binding(\.appearance.useCustomTextColor))
                    .font(.system(size: 12))
                if store.settings.appearance.useCustomTextColor {
                    ColorPicker("字体颜色", selection: colorBinding(\.appearance.textColor), supportsOpacity: false)
                        .font(.system(size: 12))
                } else {
                    Text("关闭时跟随系统菜单栏颜色（深浅色自动适配）。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, suffix: String, format: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).frame(width: 72, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .frame(width: 220)
            Text(String(format: format ?? "%.0f", value.wrappedValue) + suffix)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Spacer()
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: ColorHex.nsColor(store.settings[keyPath: keyPath])) },
            set: { newValue in
                let color = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
                store.set { $0[keyPath: keyPath] = ColorHex.hex(color) }
            }
        )
    }

    // MARK: - 刷新频率

    private var samplingTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("采样间隔越小越实时，CPU 占用也越高。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            intervalRow(title: "系统指标", detail: "CPU / GPU / 内存 / 网速",
                        value: binding(\.metricsInterval), range: 0.5...10, step: 0.5)
            intervalRow(title: "温度传感器", detail: "通过 SMC 读取，较耗资源",
                        value: binding(\.thermalInterval), range: 1...30, step: 1)
            intervalRow(title: "剪贴板轮询", detail: "检测到复制动作的延迟",
                        value: binding(\.clipboardPollInterval), range: 0.2...2, step: 0.1)

            Spacer()

            HStack {
                Button("恢复默认设置") { store.resetToDefaults() }
                Spacer()
            }
        }
        .padding(20)
    }

    private func intervalRow(title: String, detail: String, value: Binding<Double>,
                             range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.1f 秒", value.wrappedValue))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 360, alignment: .leading)
        }
    }

    // MARK: - 剪贴板

    private var clipboardTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("记录剪贴板历史", isOn: binding(\.clipboardEnabled))
                .font(.system(size: 13, weight: .medium))

            Toggle("跳过密码管理器和临时内容", isOn: binding(\.skipSensitive))
                .font(.system(size: 12.5))
            Text("识别 org.nspasteboard.ConcealedType 标记，1Password 等应用复制的内容不会被记录。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("最多保留").font(.system(size: 12.5))
                Stepper(value: binding(\.clipboardMaxItems), in: 20...5000, step: 20) {
                    Text("\(store.settings.clipboardMaxItems) 条")
                        .font(.system(size: 12, design: .monospaced))
                }
                .frame(width: 180)
            }

            HStack(spacing: 10) {
                Text("单张图片上限").font(.system(size: 12.5))
                Stepper(value: imageSizeBinding, in: 1...50, step: 1) {
                    Text("\(store.settings.maxImageBytes / (1024 * 1024)) MB")
                        .font(.system(size: 12, design: .monospaced))
                }
                .frame(width: 180)
            }

            HStack(spacing: 10) {
                Text("当前记录：\(viewModel.clipboardCount) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("刷新") { viewModel.refreshCount() }
                    .font(.system(size: 11))
            }

            Divider()

            Button("清空全部剪贴板历史") {
                ClipboardStore.shared.clear()
                viewModel.refreshCount()
                NotificationCenter.default.post(name: .clipboardHistoryCleared, object: nil)
            }
            .foregroundStyle(.red)

            Spacer()
        }
        .padding(20)
    }

    private var imageSizeBinding: Binding<Int> {
        Binding(
            get: { store.settings.maxImageBytes / (1024 * 1024) },
            set: { newValue in
                store.set { settings in
                    settings.maxImageBytes = newValue * 1024 * 1024
                }
            }
        )
    }

    // MARK: - 快捷键

    private var hotkeyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("全局快捷键用于随时呼出剪贴板历史，无需辅助功能权限。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("当前快捷键").font(.system(size: 12.5))
                Text(store.settings.hotKey?.display ?? "未设置")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Spacer()
            }

            HStack(spacing: 10) {
                Button(viewModel.recording ? "请按下组合键…（Esc 取消）" : "录制快捷键") {
                    if viewModel.recording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording(store: store)
                    }
                }
                Button("清除") {
                    store.set { $0.hotKey = nil }
                }
                .disabled(store.settings.hotKey == nil)
            }

            Text("要求至少包含一个修饰键（⌘ / ⌥ / ⌃ / ⇧）。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
    }

    // MARK: - 关于

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ClipStats").font(.system(size: 16, weight: .semibold))
                    Text("版本 0.1.0 · arm64 原生").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("菜单栏系统监控 + 剪贴板历史工具。")
                .font(.system(size: 12))
            Text("数据来源：host_statistics / host_processor_info（CPU、内存）、IOAccelerator（GPU）、sysctl NET_RT_IFLIST2（网速）、AppleSMC（温度）。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("温度读取依赖 SMC 私有接口，不同芯片的键名不同，程序会在启动时自动枚举。若显示 -- 说明当前系统未开放该接口。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }

    // MARK: - 工具

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.set { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard store.settings.segments.indices.contains(index),
              store.settings.segments.indices.contains(target) else { return }
        store.set { settings in
            settings.segments.swapAt(index, target)
        }
    }
}

extension Notification.Name {
    static let clipboardHistoryCleared = Notification.Name("clipstats.clipboardHistoryCleared")
}
