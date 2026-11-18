import AppKit
import SwiftUI

// MARK: - 预览数据

struct PreviewFileEntry: Identifiable {
    enum Kind {
        case text, image, pdf, folder, other, missing
    }

    let path: String
    let name: String
    /// 文件大小 / 「文件夹」/「已不存在」
    let detail: String
    let kind: Kind
    var text: String?
    var failure: String?

    /// 用路径作身份：文本内容异步回填时不会整块重建
    var id: String { path }

    var isTextLike: Bool { kind == .text }
}

enum PreviewContent {
    case loading
    case image(NSImage, pixelWidth: Int, pixelHeight: Int)
    case text(String, truncated: Bool)
    case files([PreviewFileEntry], total: Int, reservePreview: Bool)
    case unavailable(String)
}

final class ClipboardPreviewModel: ObservableObject {
    @Published var content: PreviewContent = .loading
    @Published var caption: String = ""
    @Published var source: String = ""
}

// MARK: - 预览视图

/// 悬停预览：图片显示大图，文本显示内容，文件显示清单 + 文本文件的前几行。
/// 浮层忽略鼠标事件，所以鼠标始终留在列表行上，不会因为预览出现而触发 hover 退出。
struct ClipboardPreviewView: View {
    @ObservedObject var model: ClipboardPreviewModel
    @ObservedObject var store: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
            footer
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassPanel(cornerRadius: 14)
        .preferredColorScheme(store.settings.interfaceAppearance.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("正在载入预览…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .image(let image, _, _):
            // 先按图片自身尺寸贴边绘制，再让外框居中：描边才会贴着图片而不是整块空白
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(LiquidGlassStyle.cardRimStroke(for: colorScheme), lineWidth: 0.6)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .text(let text, let truncated):
            Text(truncated ? text + " …" : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.92))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.30 : 0.42))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .files(let files, let total, _):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(files) { file in
                    fileRow(file)
                }
                if total > files.count {
                    Text("等 \(total) 项")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        case .unavailable(let message):
            VStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileRow(_ file: PreviewFileEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: file))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(file.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(file.detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let text = file.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(LiquidGlassStyle.cardRimStroke(for: colorScheme), lineWidth: 0.6)
                    )
            } else if let failure = file.failure {
                Text(failure)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func iconName(for file: PreviewFileEntry) -> String {
        switch file.kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .folder: return "folder"
        case .missing: return "questionmark.square.dashed"
        case .other: return "doc"
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if !model.source.isEmpty {
                Text(model.source)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
            Text("点击列表项可恢复")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(model.caption)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}
