import SwiftUI
import AppKit

struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            listArea
            Divider()
            footer
        }
        .frame(width: 380, height: CGFloat(model.panelHeight))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            model.reload()
            searchFocused = true
        }
        .onChange(of: model.focusToken) { _ in
            searchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("搜索剪贴板历史", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var listArea: some View {
        Group {
            if model.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(model.searchText.isEmpty ? "暂无剪贴板记录" : "没有匹配的记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in
                            ClipRow(
                                item: item,
                                hovered: model.hoveredID == item.id,
                                onSelect: { model.restore(item) },
                                onDelete: { model.delete(item) },
                                onHoverChange: { model.setHovered(item.id, $0) }
                            )
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.paused ? "play.circle" : "pause.circle")
            }
            .buttonStyle(.plain)
            .help(model.paused ? "恢复记录" : "暂停记录")

            Text(model.paused ? "已暂停记录" : "\(model.totalCount) 条记录")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Spacer()

            Button("清空") { model.clearAll() }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ClipRow: View {
    let item: ClipboardStore.Item
    let hovered: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            leading
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview.isEmpty ? "（空内容）" : item.preview)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let app = item.sourceApp, !app.isEmpty {
                        Text(app)
                    }
                    Text(Fmt.relativeTime(item.createdAt))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            if hovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除这条记录")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovered ? Color.primary.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
        .onTapGesture { onSelect() }
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .image:
            if let data = item.thumbData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .padding(2)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .files:
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
