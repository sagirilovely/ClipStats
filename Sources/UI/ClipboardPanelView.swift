import SwiftUI
import AppKit

struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            liquidDivider
            listArea
            liquidDivider
            footerSection
        }
        .frame(width: 390, height: CGFloat(model.panelHeight))
        .liquidGlassPanel(cornerRadius: 18)
        .onAppear {
            searchFocused = true
        }
        .onChange(of: model.focusToken) { _ in
            searchFocused = true
        }
    }

    // MARK: - 顶部搜索与筛选栏

    private var headerSection: some View {
        VStack(spacing: 8) {
            // 搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.searchText.isEmpty ? Color.secondary : Color.accentColor)

                TextField("搜索剪贴板历史...", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)

                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )

            // 快捷类型筛选药丸
            HStack {
                HStack(spacing: 2) {
                    ForEach(ClipboardPanelModel.FilterKind.allCases) { filter in
                        filterPill(filter)
                    }
                }
                .padding(2.5)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private func filterPill(_ filter: ClipboardPanelModel.FilterKind) -> some View {
        let isSelected = model.selectedFilter == filter
        return Button {
            // 不要用 withAnimation 包裹：它会把整个列表的 diff 一起做成动画，切换时明显卡顿
            model.selectedFilter = filter
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 9.5))
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                        LiquidGlassStyle.surfaceGloss
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.28) : Color.clear,
                        lineWidth: 0.8
                    )
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 液态分隔线

    private var liquidDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.04),
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - 列表区域

    private var listArea: some View {
        Group {
            if model.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.items) { item in
                            ClipRow(
                                item: item,
                                thumbnail: { model.thumbnail(for: item) },
                                hovered: model.hoveredID == item.id,
                                onSelect: { model.restore(item) },
                                onTogglePin: { model.togglePin(item) },
                                onDelete: { model.delete(item) },
                                onHoverChange: { model.setHovered(item.id, $0) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 空状态视觉

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )

                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 4) {
                Text(model.searchText.isEmpty ? "暂无剪贴板记录" : "没有匹配的记录")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Text(model.searchText.isEmpty ? "在任意应用复制的内容会自动出现在这里" : "尝试更换搜索关键字")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部液态操作栏

    private var footerSection: some View {
        HStack(spacing: 10) {
            // 运行状态与指示灯
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(model.paused ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    if !model.paused {
                        Circle()
                            .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 11, height: 11)
                    }
                }

                Text(model.paused ? "已暂停" : "\(model.totalCount) 条")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
            )

            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.paused ? "play.circle.fill" : "pause.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(model.paused ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(model.paused ? "恢复记录" : "暂停记录")

            Spacer()

            // 清空按钮
            Button {
                model.clearAll()
            } label: {
                Text("清空")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)

            // 切换到进程列表
            Button {
                model.switchToRunningApps()
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help("切换到进程列表")
            .accessibilityLabel("切换到进程列表")

            // 设置按钮
            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 剪贴板条目行 (液态玻璃卡片)

private struct ClipRow: View {
    let item: ClipboardStore.Item
    /// 延迟到渲染时再解码，配合 model 内的缓存
    let thumbnail: () -> NSImage?
    let hovered: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 图标 / 缩略图徽标
            leadingBadge
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6)
                )

            // 文本内容与元数据
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview.isEmpty ? "（空内容）" : item.preview)
                    .font(.system(size: 12.5, weight: .regular))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if let app = item.sourceApp, !app.isEmpty {
                        Text(app)
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    }

                    Text(Fmt.relativeTime(item.createdAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if item.pinned {
                        HStack(spacing: 2) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                            Text("置顶")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(Color.orange)
                    }
                }
            }

            Spacer(minLength: 4)

            // 悬停操作按钮组：常驻布局，仅切换透明度（避免插入/移除导致整行重排）
            HStack(spacing: 4) {
                    Button {
                        onTogglePin()
                    } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 10.5))
                            .foregroundStyle(item.pinned ? Color.orange : Color.secondary)
                            .padding(5)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(item.pinned ? "取消置顶" : "置顶")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.secondary)
                            .padding(5)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("删除此项")
            }
            .opacity(hovered || item.pinned ? 1 : 0)
            .allowsHitTesting(hovered || item.pinned)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                if hovered {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.065))
                    LiquidGlassStyle.surfaceGloss
                } else if item.pinned {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.04))
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            Group {
                if hovered {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LiquidGlassStyle.cardRimStroke, lineWidth: 0.8)
                } else if item.pinned {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
        .onTapGesture { onSelect() }
        .animation(.easeOut(duration: 0.16), value: hovered)
    }

    @ViewBuilder
    private var leadingBadge: some View {
        switch item.kind {
        case .image:
            if let image = thumbnail() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                    )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: 0xBF5AF2), Color(hex: 0xAF52DE)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    LiquidGlassStyle.surfaceGloss
                    Image(systemName: "photo.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
            }
        case .files:
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xFF9F0A), Color(hex: 0xF38B00)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LiquidGlassStyle.surfaceGloss
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
        case .text:
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x0A84FF), Color(hex: 0x0062D2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LiquidGlassStyle.surfaceGloss
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}
