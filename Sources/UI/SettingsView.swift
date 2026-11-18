import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            topNavBar
            liquidDivider
            contentArea
        }
        .frame(width: 760, height: 620)
        .background(GlassBackdrop(material: .underWindowBackground))
        .preferredColorScheme(store.settings.interfaceAppearance.colorScheme)
        .onAppear { viewModel.refreshCount() }
        .onDisappear { viewModel.stopRecording() }
    }

    // MARK: - 顶部液态导航栏

    private var topNavBar: some View {
        HStack(spacing: 12) {
            // 应用徽标与标题
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LiquidGlassStyle.accentGradient)
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.7)
                        )
                        .shadow(color: Color.blue.opacity(0.20), radius: 5, y: 2)
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("ClipStats")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            // 居中/右侧液态玻璃分段选项卡
            HStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.25 : 0.42))
            )
            .overlay(
                Capsule().strokeBorder(LiquidGlassStyle.cardRimStroke(for: colorScheme), lineWidth: 0.7)
            )

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = viewModel.tab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                viewModel.tab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10.5))
                Text(tab.rawValue)
                    .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.16))
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
                        LiquidGlassStyle.surfaceGloss(for: colorScheme)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.48) : Color.clear,
                        lineWidth: 0.8
                    )
            )
            // 未选中时背景透明，补一个与视觉一致的命中区域
            .contentShape(Capsule())
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var liquidDivider: some View {
        Rectangle()
            .fill(LiquidGlassStyle.divider(for: colorScheme))
            .frame(height: 1)
    }

    // MARK: - 主内容区

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.tab {
        case .statusBar: statusBarTab
        case .appearance: appearanceTab
        case .sampling: samplingTab
        case .clipboard: clipboardTab
        case .hotkey: hotkeyTab
        case .about: aboutTab
        }
    }

    // MARK: - 状态栏页签

    private var statusBarTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 实时预览卡片
                GlassCard(title: "状态栏实时预览", icon: "sparkles", tint: .blue) {
                    VStack(alignment: .leading, spacing: 10) {
                        previewBar
                        Text("预览反映当前选中的模块、标签模式及排序；关闭开关即可在状态栏中隐藏。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // 模块排序与开关
                GlassCard(title: "监控模块与排序", icon: "list.bullet.indent", tint: .indigo) {
                    VStack(spacing: 6) {
                        ForEach(Array(store.settings.segments.enumerated()), id: \.element.kind) { index, segment in
                            segmentRow(index: index, segment: segment)
                            if index < store.settings.segments.count - 1 {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }

                // 显示偏好
                GlassCard(title: "显示配置", icon: "slider.horizontal.3", tint: .teal) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 24) {
                            Toggle("CPU 数值附带温度", isOn: binding(\.showCPUWithTemperature))
                            Toggle("开机自动启动", isOn: binding(\.launchAtLogin))
                        }
                        .font(.system(size: 12))

                        Divider().opacity(0.3)

                        HStack(spacing: 12) {
                            Text("温度取值")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: binding(\.temperatureMode)) {
                                ForEach(TemperatureMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 170)

                            Text("平均值更平滑，最高值反映最热核心")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Text("字号大小")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            Slider(value: binding(\.barFontSize), in: 10...16, step: 1)
                                .frame(width: 170)
                            Text("\(Int(store.settings.barFontSize)) pt")
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                            Spacer()
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func segmentRow(index: Int, segment: SegmentConfig) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: binding(\.segments[index].enabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(segment.enabled ? Color.blue.opacity(0.15) : Color.primary.opacity(0.05))
                    .frame(width: 26, height: 26)
                Image(systemName: segment.kind.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(segment.enabled ? Color.blue : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.kind.title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(segment.kind.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: binding(\.segments[index].labelMode)) {
                ForEach(SegmentLabelMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 82)

            Toggle("数值", isOn: binding(\.segments[index].showText))
                .toggleStyle(.checkbox)
                .controlSize(.small)

            HStack(spacing: 4) {
                Button { move(index, by: -1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .padding(5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Button { move(index, by: 1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .padding(5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(index >= store.settings.segments.count - 1)
            }
        }
        .padding(.vertical, 3)
    }

    private var previewBar: some View {
        HStack(spacing: 12) {
            Text("菜单栏效果")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: CGFloat(max(5, store.settings.appearance.segmentSpacing))) {
                ForEach(store.settings.segments.filter { $0.enabled }) { segment in
                    HStack(spacing: 2.5) {
                        switch segment.labelMode {
                        case .symbol:
                            Image(systemName: segment.kind.symbolName).font(.system(size: 10))
                        case .text:
                            Text(segment.kind.textLabel).font(.system(size: 10.5))
                        case .none:
                            EmptyView()
                        }
                        if segment.showText {
                            Text(sampleText(segment.kind))
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.2))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                }
            )

            Spacer()
        }
    }

    private func sampleText(_ kind: SegmentKind) -> String {
        switch kind {
        case .cpu: return "23% 62°"
        case .gpu: return "48%"
        case .memory: return "68%"
        case .thermal: return "62°"
        case .network: return store.settings.networkVertical ? "↑86K\n↓1.2M" : "↓1.2M ↑86K"
        case .clipboard: return "36"
        }
    }

    // MARK: - 外观页签

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassCard(title: "界面主题", icon: "circle.lefthalf.filled", tint: .indigo) {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 10) {
                            ForEach(InterfaceAppearance.allCases) { mode in
                                interfaceThemeButton(mode)
                            }
                            Spacer()
                        }
                        Text("夜览模式使用深色玻璃材质；进程面板右上角的主题按钮可快速切换。状态栏自定义颜色保持不变。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard(title: "尺寸与布局", icon: "ruler.fill", tint: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        sliderRow("字号大小", value: binding(\.barFontSize), range: 10...16, step: 1, suffix: "pt")
                        sliderRow("图标大小", value: binding(\.appearance.iconPointSize), range: 8...18, step: 1, suffix: "pt")
                        sliderRow("模块间距", value: binding(\.appearance.segmentSpacing), range: 5...20, step: 1, suffix: "pt")
                        Text("模块间距就是 CSS 的 gap：相邻模块真实文字之间的距离，每个模块后面都留同样宽。最小 5pt，再小会粘字。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                        sliderRow("左右内边距", value: binding(\.appearance.horizontalPadding), range: 0...20, step: 1, suffix: "pt")
                        if store.settings.appearance.backgroundStyle != .none {
                            Text("开背景时左右会额外保留至少 3pt，避免圆角啃到首尾文字。")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }

                        Divider().opacity(0.3)

                        HStack(spacing: 12) {
                            Text("数值对齐")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: binding(\.appearance.textAlignment)) {
                                ForEach(BarTextAlignment.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 170)
                            Text("双行数值（如上下排列的网速）在各自列内的对齐方式；不影响模块间距")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Text("网速布局")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: binding(\.networkVertical)) {
                                Text("左右").tag(false)
                                Text("上下").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 170)
                            Text("上下排列（上传在上、下载在下）更省横向空间")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Toggle("稳定状态栏总宽度（数值变化不挤动菜单栏）", isOn: binding(\.stabilizeBarWidth))
                                .font(.system(size: 12))
                            Text("数值变小时不会立刻收窄：持续变小几秒后才收缩，跳动的数字不会牵着菜单栏一起抖。")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                GlassCard(title: "状态栏背景", icon: "paintpalette.fill", tint: .pink) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("背景样式")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: binding(\.appearance.backgroundStyle)) {
                                ForEach(BarBackgroundStyle.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 220)
                            Spacer()
                        }

                        if store.settings.appearance.backgroundStyle != .none {
                            ColorPicker("背景颜色", selection: colorBinding(\.appearance.backgroundColor), supportsOpacity: false)
                                .font(.system(size: 12))

                            if store.settings.appearance.backgroundStyle == .solid {
                                sliderRow("不透明度", value: binding(\.appearance.backgroundOpacity),
                                          range: 0.05...1, step: 0.05, suffix: "", format: "%.2f")
                            }
                            sliderRow("背景圆角", value: binding(\.appearance.cornerRadius), range: 0...14, step: 1, suffix: "pt")
                        }
                    }
                }

                GlassCard(title: "文字色彩", icon: "character.textbox", tint: .cyan) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("自定义字体颜色", isOn: binding(\.appearance.useCustomTextColor))
                            .font(.system(size: 12))

                        if store.settings.appearance.useCustomTextColor {
                            ColorPicker("字体颜色", selection: colorBinding(\.appearance.textColor), supportsOpacity: false)
                                .font(.system(size: 12))
                        } else {
                            Text("关闭时自适应系统菜单栏（深浅色模式自动适配）。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func interfaceThemeButton(_ mode: InterfaceAppearance) -> some View {
        let isSelected = store.settings.interfaceAppearance == mode
        return Button {
            store.set { $0.interfaceAppearance = mode }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(mode.rawValue)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 112, height: 32)
            .liquidGlassControl(cornerRadius: 10, isActive: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, suffix: String, format: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .frame(width: 220)
            Text(String(format: format ?? "%.0f", value.wrappedValue) + suffix)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .frame(width: 60, alignment: .leading)
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

    // MARK: - 刷新频率页签

    private var samplingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassCard(title: "采集刷新频率", icon: "gauge.with.needle.fill", tint: .orange) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("采样间隔越短越平滑灵敏，CPU 占用也相应稍高。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        intervalRow(title: "系统核心指标", detail: "CPU / GPU / 内存 / 网速",
                                    value: binding(\.metricsInterval), range: 0.5...10, step: 0.5)
                        Divider().opacity(0.3)
                        intervalRow(title: "温度传感器", detail: "通过 SMC 私有接口读取",
                                    value: binding(\.thermalInterval), range: 1...30, step: 1)
                        Divider().opacity(0.3)
                        intervalRow(title: "剪贴板轮询", detail: "监测剪贴板复制事件的延迟",
                                    value: binding(\.clipboardPollInterval), range: 0.2...2, step: 0.1)
                    }
                }

                Button {
                    store.resetToDefaults()
                } label: {
                    Text("恢复默认频率设置")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
    }

    private func intervalRow(title: String, detail: String, value: Binding<Double>,
                             range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text(String(format: "%.1f 秒", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.blue)
            }
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 380)
        }
    }

    // MARK: - 剪贴板页签

    private var clipboardTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassCard(title: "记录规则与安全", icon: "lock.shield.fill", tint: .green) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("记录剪贴板历史", isOn: binding(\.clipboardEnabled))
                            .font(.system(size: 13, weight: .medium))

                        Toggle("跳过密码管理器和敏感临时内容", isOn: binding(\.skipSensitive))
                            .font(.system(size: 12.5))
                        Text("自动识别 org.nspasteboard.ConcealedType 标记，1Password、Bitwarden 等密码管理器复制的内容不会记录入库。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Divider().opacity(0.4)

                        Toggle("悬停预览时读取文本文件内容", isOn: binding(\.previewFileContents))
                            .font(.system(size: 12.5))
                        Text("悬停剪贴板里的文件条目时，读取文本文件的前几行做预览。读取桌面、文稿、下载等受系统保护的目录时，macOS 会弹一次文件访问授权；关闭此项后只显示文件名与大小。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard(title: "存储配额", icon: "internaldrive.fill", tint: .blue) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("历史保留上限").font(.system(size: 12.5)).frame(width: 90, alignment: .leading)
                            Stepper(value: binding(\.clipboardMaxItems), in: 20...5000, step: 20) {
                                Text("\(store.settings.clipboardMaxItems) 条")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .frame(width: 180)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Text("单张图片上限").font(.system(size: 12.5)).frame(width: 90, alignment: .leading)
                            Stepper(value: imageSizeBinding, in: 1...50, step: 1) {
                                Text("\(store.settings.maxImageBytes / (1024 * 1024)) MB")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .frame(width: 180)
                            Spacer()
                        }
                    }
                }

                GlassCard(title: "历史数据管理", icon: "trash.fill", tint: .red) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("数据库当前包含")
                                .font(.system(size: 12))
                            Text("\(viewModel.clipboardCount) 条记录")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())

                            Button("刷新") { viewModel.refreshCount() }
                                .font(.system(size: 11))
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                        }

                        Button {
                            ClipboardStore.shared.clear()
                            viewModel.refreshCount()
                            NotificationCenter.default.post(name: .clipboardHistoryCleared, object: nil)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text("清空全部剪贴板历史")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
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

    // MARK: - 快捷键页签

    private var hotkeyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassCard(title: "呼出全局面板快捷键", icon: "command", tint: .blue) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("基于 Carbon 全局事件注册，随时随地一键呼出剪贴板历史，无需辅助功能（Accessibility）权限。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 14) {
                            Text("当前快捷键")
                                .font(.system(size: 12.5))

                            Text(store.settings.hotKey?.display ?? "未设置")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
                                )

                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button {
                                if viewModel.recording {
                                    viewModel.stopRecording()
                                } else {
                                    viewModel.startRecording(store: store)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if viewModel.recording {
                                        Circle().fill(Color.red).frame(width: 8, height: 8)
                                    }
                                    Text(viewModel.recording ? "请按下组合键…（Esc 取消）" : "录制新快捷键")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.recording ? Color.red.opacity(0.12) : Color.blue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(viewModel.recording ? Color.red.opacity(0.4) : Color.blue.opacity(0.3), lineWidth: 0.8)
                                )
                                .foregroundStyle(viewModel.recording ? Color.red : Color.blue)
                            }
                            .buttonStyle(.plain)

                            Button("清除") {
                                store.set { $0.hotKey = nil }
                            }
                            .font(.system(size: 12))
                            .disabled(store.settings.hotKey == nil)
                        }

                        Text("要求至少包含一个修饰键（⌘ Command / ⌥ Option / ⌃ Control / ⇧ Shift）。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - 关于页签

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassCard(title: "ClipStats", icon: "info.circle.fill", tint: .indigo) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.0)
                                    )
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("ClipStats")
                                    .font(.system(size: 18, weight: .bold))
                                HStack(spacing: 6) {
                                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Text("arm64 原生")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Color.green.opacity(0.12))
                                        .clipShape(Capsule())
                                        .foregroundStyle(Color.green)
                                }
                            }
                        }

                        Divider().opacity(0.3)

                        Text("优雅精巧的 macOS 菜单栏系统指标监控与剪贴板历史管理器。")
                            .font(.system(size: 12.5))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("底层数据源架构：")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text("• host_statistics / host_processor_info：CPU 核心与物理内存")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("• IOAccelerator：GPU 图形处理器占用")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("• sysctl NET_RT_IFLIST2：实时网络上行与下行吞吐")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("• AppleSMC：芯片硅片热敏传感器温度矩阵")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - 工具方法

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

// MARK: - 液态玻璃卡片容器

private struct GlassCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            content()
        }
        .padding(15)
        .liquidGlassCard(cornerRadius: 14)
    }
}

extension Notification.Name {
    static let clipboardHistoryCleared = Notification.Name("clipstats.clipboardHistoryCleared")
}
