import AppKit
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
        didSet { scheduleReload() }
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
    /// 由 AppDelegate 注入：切换到「正在运行的应用程序」面板
    var onSwitchToRunningApps: (() -> Void)?
    var onRequestQuit: (() -> Void)?
    var onTogglePause: ((Bool) -> Void)?
    var onClearAll: (() -> Void)?

    private let store = ClipboardStore.shared

    /// 已解码的缩略图缓存：避免每次 body 重新求值时重复解码 PNG
    private var thumbnailCache: [Int64: NSImage] = [:]
    /// 查询放到后台队列，避免点击筛选时同步查 SQLite 卡住首帧
    private static let loadQueue = DispatchQueue(label: "clipstats.clipboard.load", qos: .userInitiated)
    private var loadToken = 0
    private var pendingReload: DispatchWorkItem?

    func reload() {
        loadToken += 1
        let token = loadToken
        let search = searchText
        let kind = selectedFilter.storeKind

        Self.loadQueue.async { [weak self] in
            let items = ClipboardStore.shared.items(search: search, kind: kind, limit: 300)
            let total = ClipboardStore.shared.count()
            DispatchQueue.main.async {
                guard let self, token == self.loadToken else { return }
                self.items = items
                self.totalCount = total
                // 只保留当前列表里还存在的缩略图，避免缓存无限增长
                let ids = Set(items.map(\.id))
                self.thumbnailCache = self.thumbnailCache.filter { ids.contains($0.key) }
            }
        }
    }

    /// 搜索框输入去抖，避免每敲一个字符就查一次库
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// 供行视图在渲染时按需取图（首次解码后缓存）
    func thumbnail(for item: ClipboardStore.Item) -> NSImage? {
        if let cached = thumbnailCache[item.id] {
            return cached
        }
        guard let data = store.thumbnailData(id: item.id), let image = NSImage(data: data) else {
            return nil
        }
        thumbnailCache[item.id] = image
        return image
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

    func switchToRunningApps() {
        onSwitchToRunningApps?()
    }

    func quit() {
        onRequestQuit?()
    }
}
