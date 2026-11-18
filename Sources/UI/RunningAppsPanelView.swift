import SwiftUI
import AppKit
import Combine

struct RunningAppsPanelView: View {
    @ObservedObject var model: RunningAppsModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            liquidDivider
            listArea
            liquidDivider
            footerSection
        }
        .frame(width: 390, height: 460)
        .liquidGlassPanel(cornerRadius: 18)
        .onAppear { model.reload() }
    }

    // MARK: - 顶部

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("正在运行的应用程序")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Text("\(model.apps.count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))

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
        .padding(.bottom, 10)
    }

    private var liquidDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 0.6)
    }

    // MARK: - 列表

    private var listArea: some View {
        Group {
            if model.apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 26))
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
                                .padding(.leading, 50)
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
            Text("共 \(model.apps.count) 个应用")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Spacer()

            Text("「释放」= 正常退出该应用")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

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
    let hovered: Bool
    let onHover: (Bool) -> Void
    let onQuit: () -> Void
    let onForceQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.quitState {
        case .idle:
            Button(action: onQuit) {
                Text("释放")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(LiquidGlassButtonStyle())
            .opacity(hovered ? 1.0 : 0.75)
            .help("释放 \(item.name)（正常退出）")

        case .quitting:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("退出中…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

        case .needsForce:
            Button(action: confirmForceQuit) {
                Text("强制退出")
                    .font(.system(size: 10.5, weight: .medium))
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
        if item.isActive {
            parts.append("当前活跃")
        }
        return parts.joined(separator: " · ")
    }
}
