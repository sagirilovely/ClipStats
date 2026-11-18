import Foundation
import Combine

final class ClipboardPanelModel: ObservableObject {
    @Published var items: [ClipboardStore.Item] = []
    @Published var searchText: String = "" {
        didSet { reload() }
    }
    @Published var paused: Bool = false
    @Published var totalCount: Int = 0
    @Published var panelHeight: CGFloat = 470
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
        items = store.items(search: searchText, limit: 300)
        totalCount = store.count()
    }

    func restore(_ item: ClipboardStore.Item) {
        onRestore?(item)
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
