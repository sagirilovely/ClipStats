import SwiftUI
import AppKit
import Combine

struct RunningAppsPanelView: View {
    /// 面板尺寸的唯一来源，控制器也引用它，避免窗口与内容尺寸不一致导致溢出屏幕
    static let panelSize = CGSize(width: 390, height: 560)

    @ObservedObject var model: RunningAppsModel

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
        .liquidGlassPanel(cornerRadius: 18)
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

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("刷新列表")
            .accessibilityLabel("刷新列表")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var liquidDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 0.6)
    }

    // MARK: - 详情

    private var detailSection: some View {
        VStack(spacing: 10) {
            Picker("", selection: $model.mode) {
                ForEach(MetricMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            detailCard
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
        .liquidGlassCard(cornerRadius: 10)
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
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(cores.indices, id: \.self) { index in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(coreColor(cores[index]))
                                .frame(height: max(2, 18 * CGFloat(min(1, cores[index]))))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 18, alignment: .bottom)
                .help("每个核心的占用")
            }

            HStack(spacing: 12) {
                detailPair("平均温度", model.metrics?.thermal.cpuTemperatureAverage.map { Fmt.temperature($0) } ?? "—")
                detailPair("最高温度", model.metrics?.thermal.cpuTemperature.map { Fmt.temperature($0) } ?? "—")
                detailPair("核心数", "\(model.metrics?.cpu.perCore.count ?? 0)")
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
                detailPair("显存", model.metrics?.gpu.memoryUsed.map { Fmt.bytes($0) } ?? "—")
            }
            Text("GPU 每进程数据来自 IOAccelerator，仅统计提交了 GPU 工作的进程")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
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
                    Text("\(Fmt.bytes(Double(memory.used))) / \(Fmt.bytes(Double(memory.total)))")
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
                model.onSwitchToClipboard?()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .padding(5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("切换到剪贴板历史")
            .accessibilityLabel("切换到剪贴板历史")

            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
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
