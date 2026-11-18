import Foundation
import Combine

final class ClipboardPanelModel: ObservableObject {
    enum FilterKind: String, CaseIterable, Identifiable {
        case all = "全部"
        case text = "文本"
        case image = "图片"
        case files = "文件"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .text: return "text.alignleft"
            case .image: return "photo"
            case .files: return "folder"
            }
        }

        var storeKind: ClipboardStore.Kind? {
            switch self {
            case .all: return nil
            case .text: return .text
            case .image: return .image
            case .files: return .files
            }
        }
    }

    @Published var items: [ClipboardStore.Item] = []
    @Published var searchText: String = "" {
        didSet { reload() }
    }
    @Published var selectedFilter: FilterKind = .all {
        didSet { reload() }
    }
    @Published var paused: Bool = false
    @Published var totalCount: Int = 0
    @Published var panelHeight: CGFloat = 480
    @Published var hoveredID: Int64?
    /// 每次打开面板自增，用于把键盘焦点交给搜索框
    @Published var focusToken: Int = 0

    func requestFocus() {
        focusToken += 1
    }

    func setHovered(_ id: Int64, _ hovered: Bool) {
        if hovered {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    var onRestore: ((ClipboardStore.Item) -> Void)?
    var onRequestSettings: (() -> Void)?
    var onRequestQuit: (() -> Void)?
    var onTogglePause: ((Bool) -> Void)?
    var onClearAll: (() -> Void)?

    private let store = ClipboardStore.shared

    func reload() {
        items = store.items(search: searchText, kind: selectedFilter.storeKind, limit: 300)
        totalCount = store.count()
    }

    func restore(_ item: ClipboardStore.Item) {
        onRestore?(item)
    }

    func togglePin(_ item: ClipboardStore.Item) {
        store.togglePin(id: item.id)
        reload()
    }

    func delete(_ item: ClipboardStore.Item) {
        store.delete(id: item.id)
        reload()
    }

    func clearAll() {
        onClearAll?()
        reload()
    }

    func togglePause() {
        paused.toggle()
        onTogglePause?(paused)
    }

    func openSettings() {
        onRequestSettings?()
    }

    func quit() {
        onRequestQuit?()
    }
}
