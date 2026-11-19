import SwiftUI
import AppKit
import Combine

struct RunningAppsPanelView: View {
    /// 面板尺寸的唯一来源，控制器也引用它，避免窗口与内容尺寸不一致导致溢出屏幕
    static let panelSize = CGSize(width: 390, height: 560)

    @ObservedObject var model: RunningAppsModel
    @ObservedObject var store: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            detailSection
            liquidDivider
            processHeader
            listArea
            liquidDivider
            footerSection
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .liquidGlassPanel(cornerRadius: 20)
        .preferredColorScheme(store.settings.interfaceAppearance.colorScheme)
        .onAppear { model.reload() }
    }

    // MARK: - 顶部

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: model.mode.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("系统监控")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            AppearanceModeButton(store: store)

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(LiquidGlassIconButtonStyle())
            .help("刷新列表")
            .accessibilityLabel("刷新列表")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var liquidDivider: some View {
        Rectangle()
            .fill(LiquidGlassStyle.divider(for: colorScheme))
            .frame(height: 1)
    }

    // MARK: - 详情

    /// 模式切换包一层 withAnimation：卡片淡入淡出 + 列表重排都用同一条缓动，避免「硬切」的闪一下
    private var modeSelection: Binding<MetricMode> {
        Binding(
            get: { model.mode },
            set: { newValue in
                guard newValue != model.mode else { return }
                withAnimation(.easeInOut(duration: 0.2)) { model.mode = newValue }
            }
        )
    }

    private var detailSection: some View {
        VStack(spacing: 10) {
            Picker("", selection: modeSelection) {
                ForEach(MetricMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            detailCard
                .id(model.mode)
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.mode {
            case .cpu:
                cpuDetail
            case .gpu:
                gpuDetail
            case .network:
                networkDetail
            case .memory:
                memoryDetail
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidGlassMetrics.concentric(inset: 14))
    }

    // CPU 详情：总占用 + 每核 + 温度
    private var cpuDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.percent(model.metrics?.cpu.total ?? 0))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("CPU 总占用")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let temperature = model.metrics?.thermal.cpuTemperatureAverage {
                    Label(Fmt.temperature(temperature), systemImage: "thermometer.medium")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let cores = model.metrics?.cpu.perCore, !cores.isEmpty {
                coreChart(cores)
            }

            HStack(spacing: 12) {
                detailPair("平均温度", model.metrics?.thermal.cpuTemperatureAverage.map { Fmt.temperature($0) } ?? "—")
                detailPair("最高温度", model.metrics?.thermal.cpuTemperature.map { Fmt.temperature($0) } ?? "—")
                detailPair("核心数", model.metrics.map { "\($0.cpu.perCore.count)" } ?? "—")
            }
        }
    }

    // GPU 详情
    private var gpuDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.metrics?.gpu.utilization.map { Fmt.percent($0) } ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("GPU 占用")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                detailPair("渲染器", model.metrics?.gpu.rendererUtilization.map { Fmt.percent($0) } ?? "—")
                detailPair("GPU 内存 已用 / 总", gpuMemoryText)
            }

            if let breakdown = gpuMemoryBreakdown {
                // 双色堆叠：蓝色 = GPU 占用的显存，灰色 = 已被系统其它部分使用的内存，空槽 = 剩余
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.09))
                        if breakdown.otherRatio > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.28))
                                .frame(width: width * CGFloat(breakdown.otherRatio))
                                .offset(x: width * CGFloat(breakdown.gpuRatio))
                        }
                        if breakdown.gpuRatio > 0 {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.85))
                                .frame(width: max(2, width * CGFloat(breakdown.gpuRatio)))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
                .accessibilityElement()
                .accessibilityLabel(
                    "GPU 占用 \(Fmt.compactBytes(breakdown.gpu))，其他已用 \(Fmt.compactBytes(breakdown.other))，剩余 \(Fmt.compactBytes(breakdown.free))"
                )

                HStack(spacing: 10) {
                    legendDot(color: Color.accentColor.opacity(0.85), text: "GPU \(Fmt.compactBytes(breakdown.gpu))")
                    legendDot(color: Color.primary.opacity(0.32), text: "其他已用 \(Fmt.compactBytes(breakdown.other))")
                    Spacer(minLength: 2)
                    Text("剩余 \(Fmt.compactBytes(breakdown.free))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Text(gpuMemoryNote)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // 网速详情
    private var networkDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("↓\(Fmt.speed(model.metrics?.network.download ?? 0))")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("下载")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↑\(Fmt.speed(model.metrics?.network.upload ?? 0))")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text("上传")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text("每进程用量来自系统 nettop，2 秒采样一次；辅助进程已归并到所属应用")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }

    // 内存详情
    private var memoryDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.percent(model.metrics?.memory.usage ?? 0))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("内存占用")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let memory = model.metrics?.memory {
                    Text("\(Fmt.compactBytes(Double(memory.used))) / \(Fmt.compactBytes(Double(memory.total)))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                detailPair("已压缩", model.metrics.map { Fmt.bytes(Double($0.memory.compressed)) } ?? "—")
                detailPair("交换区", swapText)
                detailPair("压力", pressureText)
            }
        }
    }

    private var gpuMemoryText: String {
        guard let used = model.metrics?.gpu.memoryUsed else { return "—" }
        guard let total = model.metrics?.gpu.memoryTotal, total > 0 else {
            return "\(Fmt.compactBytes(used)) / —"
        }
        return "\(Fmt.compactBytes(used)) / \(Fmt.compactBytes(total))"
    }

    private var gpuMemoryNote: String {
        if model.metrics?.gpu.memoryTotal != nil {
            return "GPU 与 CPU 共享同一块统一内存，内存紧张时显存也会被压缩；每进程仅统计提交了 GPU 工作的任务"
        }
        return "此处为 GPU 已用显存；每进程仅统计提交了 GPU 工作的任务"
    }

    /// GPU 显存 + 系统内存的占用构成（用于双色堆叠条）
    private struct MemoryBreakdown {
        let total: Double
        let gpu: Double
        let other: Double
        let free: Double

        var gpuRatio: Double { total > 0 ? min(1, gpu / total) : 0 }
        var otherRatio: Double {
            guard total > 0 else { return 0 }
            return min(1 - gpuRatio, max(0, other) / total)
        }
    }

    private var gpuMemoryBreakdown: MemoryBreakdown? {
        guard let gpuUsed = model.metrics?.gpu.memoryUsed, let memory = model.metrics?.memory, memory.total > 0 else {
            return nil
        }
        let total = Double(memory.total)
        let used = min(total, Double(memory.used))
        // GPU 的「In use system memory」本来就包含在系统已用内存里，不能重复计
        let gpu = min(gpuUsed, used > 0 ? used : gpuUsed)
        return MemoryBreakdown(
            total: total,
            gpu: gpu,
            other: max(0, used - gpu),
            free: max(0, total - used)
        )
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var gpuMemoryRatio: Double? {
        guard let used = model.metrics?.gpu.memoryUsed,
              let total = model.metrics?.gpu.memoryTotal, total > 0 else { return nil }
        return used / total
    }

    private var swapText: String {
        guard let memory = model.metrics?.memory, memory.swapUsed > 0 else { return "0" }
        return Fmt.bytes(Double(memory.swapUsed))
    }

    private var pressureText: String {
        guard let level = model.metrics?.memory.pressure else { return "—" }
        switch level {
        case 4: return "严重"
        case 2: return "偏高"
        default: return "正常"
        }
    }

    private func detailPair(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    /// 每核占用柱状图，左侧带 100% / 50% / 0% 纵坐标和三条网格线，方便读出具体数值
    private func coreChart(_ cores: [Double]) -> some View {
        let chartHeight: CGFloat = 34
        let axisFont = Font.system(size: 8.5, weight: .medium, design: .monospaced)
        let barSpacing: CGFloat = cores.count > 12 ? 1 : 2
        return HStack(alignment: .top, spacing: 4) {
            // 三个标签用 offset 精确居中到三条网格线上（offset 不参与布局，卡片内边距可容纳少量外溢）
            ZStack(alignment: .topTrailing) {
                Text("100%").offset(y: -5)
                Text("50%").offset(y: chartHeight / 2 - 5)
                Text("0%").offset(y: chartHeight - 5)
            }
            .font(axisFont)
            .foregroundStyle(.tertiary)
            .frame(width: 26, height: chartHeight, alignment: .topTrailing)

            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(cores.indices, id: \.self) { index in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(coreColor(cores[index]))
                                .frame(height: barHeight(cores[index], chartHeight: chartHeight))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: chartHeight, alignment: .bottom)

                // 网格线压在柱子之上，高核数时也不会被柱子切成一段一段
                VStack(spacing: 0) {
                    gridLine
                    Spacer(minLength: 0)
                    gridLine
                    Spacer(minLength: 0)
                    gridLine
                }
            }
            .frame(height: chartHeight)
        }
        .help(coreHelp(cores))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coreHelp(cores))
    }

    private func barHeight(_ value: Double, chartHeight: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, value))
        // 空闲核心留 1pt 的点，而不是 2pt 的柱子压住 0% 基线
        if clamped < 0.02 { return 1 }
        return max(2, (chartHeight * CGFloat(clamped)).rounded())
    }

    private var gridLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(height: 0.5)
    }

    /// tooltip 是单行，核心多了要自己换行
    private func coreHelp(_ cores: [Double]) -> String {
        guard !cores.isEmpty else { return "每个核心的占用" }
        var lines: [String] = []
        var current: [String] = []
        for (index, value) in cores.enumerated() {
            current.append("#\(index + 1) \(Fmt.percent(value))")
            if current.count == 4 {
                lines.append(current.joined(separator: " · "))
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty { lines.append(current.joined(separator: " · ")) }
        return lines.joined(separator: "\n")
    }

    private func coreColor(_ value: Double) -> Color {
        if value > 0.8 { return .red.opacity(0.85) }
        if value > 0.5 { return .orange.opacity(0.85) }
        return Color.accentColor.opacity(0.75)
    }

    // MARK: - 进程列表

    private var processHeader: some View {
        HStack(spacing: 6) {
            Text("进程")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("按 \(model.mode.rawValue) 从高到低")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(model.apps.count) 个")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var listArea: some View {
        Group {
            if model.apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("没有检测到正在运行的应用程序")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.apps) { app in
                            RunningAppRow(
                                item: app,
                                metric: model.valueText(for: app),
                                metricWidth: model.mode == .network ? 86 : 58,
                                hovered: model.hoveredPID == app.pid,
                                onHover: { hovering in
                                    if hovering {
                                        model.hoveredPID = app.pid
                                    } else if model.hoveredPID == app.pid {
                                        model.hoveredPID = nil
                                    }
                                },
                                onQuit: { model.quit(app) },
                                onForceQuit: { model.forceQuit(app) }
                            )
                            Divider()
                                .opacity(0.3)
                                .padding(.leading, 46)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didLiveScrollNotification)) { _ in
                    model.hoveredPID = nil
                }
                .animation(.easeInOut(duration: 0.2), value: model.mode)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 底部

    private var footerSection: some View {
        HStack(spacing: 8) {
            Text("「释放」= 正常退出该应用")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                model.onOpenTranslation?()
            } label: {
                Image(systemName: "translate")
            }
            .buttonStyle(LiquidGlassIconButtonStyle())
            .help("英汉小翻译")
            .accessibilityLabel("英汉小翻译")

            Button {
                model.onSwitchToClipboard?()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(LiquidGlassIconButtonStyle())
            .help("切换到剪贴板历史")
            .accessibilityLabel("切换到剪贴板历史")

            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(LiquidGlassIconButtonStyle())
            .help("打开设置")
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - 行

private struct RunningAppRow: View {
    let item: RunningAppItem
    let metric: String
    let metricWidth: CGFloat
    let hovered: Bool
    let onHover: (Bool) -> Void
    let onQuit: () -> Void
    let onForceQuit: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            iconView
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(metric)
                .font(.system(size: metricWidth > 60 ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: metricWidth, alignment: .trailing)

            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovered ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.quitState {
        case .idle:
            Button(action: onQuit) {
                Text("释放")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(LiquidGlassButtonStyle())
            .opacity(hovered ? 1.0 : 0.75)
            .help("释放 \(item.name)（正常退出）")
            .accessibilityLabel("释放 \(item.name)")

        case .quitting:
            Text("退出中")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 46)

        case .needsForce:
            Button(action: confirmForceQuit) {
                Text("强制退出")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .buttonStyle(LiquidGlassButtonStyle())
            .help("应用没有响应正常退出，点击强制终止")
            .accessibilityLabel("强制退出 \(item.name)")
        }
    }

    /// 强制退出会丢数据，必须二次确认
    private func confirmForceQuit() {
        let alert = NSAlert()
        alert.messageText = "强制退出「\(item.name)」？"
        alert.informativeText = "强制退出会立即终止应用，未保存的内容将丢失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "强制退出")
        alert.addButton(withTitle: "取消")
        // 面板在 .popUpMenu 层级，普通层级的弹窗会被压在下面
        alert.window.level = .popUpMenu

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            onForceQuit()
        }
    }

    private var subtitle: String {
        var parts = ["PID \(item.pid)"]
        if let launchDate = item.launchDate {
            let seconds = Date().timeIntervalSince(launchDate)
            if seconds < 60 {
                parts.append("刚刚启动")
            } else if seconds < 3600 {
                parts.append("运行 \(Int(seconds / 60)) 分钟")
            } else if seconds < 86400 {
                parts.append("运行 \(Int(seconds / 3600)) 小时")
            } else {
                parts.append("运行 \(Int(seconds / 86400)) 天")
            }
        }
        return parts.joined(separator: " · ")
    }
}
