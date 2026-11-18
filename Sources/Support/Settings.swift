import Foundation
import Combine

// MARK: - 状态栏模块

enum SegmentKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case cpu, gpu, memory, thermal, network, clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU 占用"
        case .gpu: return "GPU 占用"
        case .memory: return "内存"
        case .thermal: return "温度"
        case .network: return "网速"
        case .clipboard: return "剪贴板"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .network: return "network"
        case .clipboard: return "doc.on.clipboard"
        }
    }

    /// 文字标签模式下显示的名字
    var textLabel: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .thermal: return "温度"
        case .network: return "网速"
        case .clipboard: return "剪贴板"
        }
    }

    var detail: String {
        switch self {
        case .cpu: return "处理器占用，可附带温度"
        case .gpu: return "图形处理器占用"
        case .memory: return "物理内存占用"
        case .thermal: return "CPU / GPU 温度"
        case .network: return "实时下载 / 上传速度"
        case .clipboard: return "打开剪贴板历史"
        }
    }
}

enum SegmentLabelMode: String, Codable, CaseIterable, Identifiable {
    case symbol = "图标"
    case text = "文字"
    case none = "无"
    var id: String { rawValue }
}

struct SegmentConfig: Codable, Identifiable, Hashable {
    var kind: SegmentKind
    var enabled: Bool = true
    var showText: Bool = true
    /// 数值前的标识：SF Symbol 图标 / 文字标签 / 不显示
    var labelMode: SegmentLabelMode = .symbol

    var id: String { kind.rawValue }

    init(kind: SegmentKind, enabled: Bool = true, showText: Bool = true,
         labelMode: SegmentLabelMode = .symbol) {
        self.kind = kind
        self.enabled = enabled
        self.showText = showText
        self.labelMode = labelMode
    }

    enum CodingKeys: String, CodingKey {
        case kind, enabled, showText, labelMode
        /// 旧版本字段，仅用于迁移
        case showIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(SegmentKind.self, forKey: .kind)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        showText = (try? container.decodeIfPresent(Bool.self, forKey: .showText)) ?? true
        if let mode = try? container.decodeIfPresent(SegmentLabelMode.self, forKey: .labelMode) {
            labelMode = mode
        } else {
            let showIcon = (try? container.decodeIfPresent(Bool.self, forKey: .showIcon)) ?? true
            labelMode = showIcon ? .symbol : .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(showText, forKey: .showText)
        try container.encode(labelMode, forKey: .labelMode)
    }

    static var defaults: [SegmentConfig] {
        [
            SegmentConfig(kind: .cpu),
            SegmentConfig(kind: .thermal),
            SegmentConfig(kind: .memory),
            SegmentConfig(kind: .network),
            SegmentConfig(kind: .gpu, enabled: false),
            SegmentConfig(kind: .clipboard),
        ]
    }
}

enum TemperatureMode: String, Codable, CaseIterable, Identifiable {
    case average = "平均值"
    case maximum = "最高值"
    var id: String { rawValue }
}

// MARK: - 外观

enum InterfaceAppearance: String, Codable, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "夜览"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

enum BarBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case none = "无"
    case solid = "纯色"
    case glass = "毛玻璃"
    var id: String { rawValue }
}

enum BarTextAlignment: String, Codable, CaseIterable, Identifiable {
    case center = "居中"
    case trailing = "靠右"
    var id: String { rawValue }
}

struct BarAppearance: Codable {
    /// 模块之间的间距
    var segmentSpacing: Double = 6
    /// 状态栏左右内边距
    var horizontalPadding: Double = 6
    /// SF Symbol 图标字号
    var iconPointSize: Double = 11
    /// 数值在预留槽位内的对齐方式
    var textAlignment: BarTextAlignment = .center

    var backgroundStyle: BarBackgroundStyle = .none
    var backgroundColor: String = "#1E1E1E"
    var backgroundOpacity: Double = 0.35
    var cornerRadius: Double = 6

    var useCustomTextColor: Bool = false
    var textColor: String = "#FFFFFF"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarAppearance()
        segmentSpacing = (try? c.decodeIfPresent(Double.self, forKey: .segmentSpacing)) ?? d.segmentSpacing
        horizontalPadding = (try? c.decodeIfPresent(Double.self, forKey: .horizontalPadding)) ?? d.horizontalPadding
        iconPointSize = (try? c.decodeIfPresent(Double.self, forKey: .iconPointSize)) ?? d.iconPointSize
        textAlignment = (try? c.decodeIfPresent(BarTextAlignment.self, forKey: .textAlignment)) ?? d.textAlignment
        backgroundStyle = (try? c.decodeIfPresent(BarBackgroundStyle.self, forKey: .backgroundStyle)) ?? d.backgroundStyle
        backgroundColor = (try? c.decodeIfPresent(String.self, forKey: .backgroundColor)) ?? d.backgroundColor
        backgroundOpacity = (try? c.decodeIfPresent(Double.self, forKey: .backgroundOpacity)) ?? d.backgroundOpacity
        cornerRadius = (try? c.decodeIfPresent(Double.self, forKey: .cornerRadius)) ?? d.cornerRadius
        useCustomTextColor = (try? c.decodeIfPresent(Bool.self, forKey: .useCustomTextColor)) ?? d.useCustomTextColor
        textColor = (try? c.decodeIfPresent(String.self, forKey: .textColor)) ?? d.textColor
        normalize()
    }

    mutating func normalize() {
        segmentSpacing = min(max(segmentSpacing, 0), 20)
        horizontalPadding = min(max(horizontalPadding, 0), 20)
        iconPointSize = min(max(iconPointSize, 8), 18)
        backgroundOpacity = min(max(backgroundOpacity, 0.05), 1)
        cornerRadius = min(max(cornerRadius, 0), 14)
    }
}

// MARK: - 全局快捷键

struct HotKeyConfig: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon: cmdKey / shiftKey / optionKey / controlKey
    var display: String

    static let optionCommandV = HotKeyConfig(
        keyCode: 9,
        modifiers: 2048 | 256,
        display: "⌥⌘V"
    )
}

// MARK: - 设置模型

struct AppSettings: Codable {
    var schemaVersion: Int = 1

    // 状态栏
    var segments: [SegmentConfig] = SegmentConfig.defaults
    var showCPUWithTemperature: Bool = false
    var barFontSize: Double = 12
    var temperatureMode: TemperatureMode = .average
    /// 固定每个模块的槽位宽度，避免数值跳动时菜单栏宽度变化
    var stabilizeBarWidth: Bool = true

    /// 网速模块上下排列（下载在上、上传在下），用于节省横向空间
    var networkVertical: Bool = false

    // 外观
    var appearance: BarAppearance = BarAppearance()
    /// 面板与设置窗口的界面主题，不影响状态栏自定义颜色
    var interfaceAppearance: InterfaceAppearance = .system

    // 采样
    var metricsInterval: Double = 1.0
    var thermalInterval: Double = 3.0
    var clipboardPollInterval: Double = 0.3

    // 剪贴板
    var clipboardEnabled: Bool = true
    var clipboardPaused: Bool = false
    var clipboardMaxItems: Int = 500
    var skipSensitive: Bool = true
    var maxImageBytes: Int = 10 * 1024 * 1024
    var clipboardPanelHeight: Double = 460

    // 系统
    var launchAtLogin: Bool = false
    var hotKey: HotKeyConfig? = .optionCommandV

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? d.schemaVersion
        segments = (try? c.decodeIfPresent([SegmentConfig].self, forKey: .segments)) ?? d.segments
        showCPUWithTemperature = (try? c.decodeIfPresent(Bool.self, forKey: .showCPUWithTemperature)) ?? d.showCPUWithTemperature
        barFontSize = (try? c.decodeIfPresent(Double.self, forKey: .barFontSize)) ?? d.barFontSize
        temperatureMode = (try? c.decodeIfPresent(TemperatureMode.self, forKey: .temperatureMode)) ?? d.temperatureMode
        stabilizeBarWidth = (try? c.decodeIfPresent(Bool.self, forKey: .stabilizeBarWidth)) ?? d.stabilizeBarWidth
        networkVertical = (try? c.decodeIfPresent(Bool.self, forKey: .networkVertical)) ?? d.networkVertical
        appearance = (try? c.decodeIfPresent(BarAppearance.self, forKey: .appearance)) ?? d.appearance
        interfaceAppearance = (try? c.decodeIfPresent(InterfaceAppearance.self, forKey: .interfaceAppearance)) ?? d.interfaceAppearance
        metricsInterval = (try? c.decodeIfPresent(Double.self, forKey: .metricsInterval)) ?? d.metricsInterval
        thermalInterval = (try? c.decodeIfPresent(Double.self, forKey: .thermalInterval)) ?? d.thermalInterval
        clipboardPollInterval = (try? c.decodeIfPresent(Double.self, forKey: .clipboardPollInterval)) ?? d.clipboardPollInterval
        clipboardEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .clipboardEnabled)) ?? d.clipboardEnabled
        clipboardPaused = (try? c.decodeIfPresent(Bool.self, forKey: .clipboardPaused)) ?? d.clipboardPaused
        clipboardMaxItems = (try? c.decodeIfPresent(Int.self, forKey: .clipboardMaxItems)) ?? d.clipboardMaxItems
        skipSensitive = (try? c.decodeIfPresent(Bool.self, forKey: .skipSensitive)) ?? d.skipSensitive
        maxImageBytes = (try? c.decodeIfPresent(Int.self, forKey: .maxImageBytes)) ?? d.maxImageBytes
        clipboardPanelHeight = (try? c.decodeIfPresent(Double.self, forKey: .clipboardPanelHeight)) ?? d.clipboardPanelHeight
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        hotKey = (try? c.decodeIfPresent(HotKeyConfig.self, forKey: .hotKey)) ?? d.hotKey
        normalize()
    }

    mutating func normalize() {
        // 保证所有模块都在列表里（新增模块自动追加），且顺序合法
        var seen = Set<SegmentKind>()
        var result: [SegmentConfig] = []
        for config in segments where !seen.contains(config.kind) {
            seen.insert(config.kind)
            result.append(config)
        }
        for kind in SegmentKind.allCases where !seen.contains(kind) {
            result.append(SegmentConfig(kind: kind, enabled: false))
        }
        segments = result
        metricsInterval = min(max(metricsInterval, 0.5), 10)
        thermalInterval = min(max(thermalInterval, 1), 30)
        clipboardPollInterval = min(max(clipboardPollInterval, 0.2), 5)
        clipboardMaxItems = min(max(clipboardMaxItems, 20), 5000)
        clipboardPanelHeight = min(max(clipboardPanelHeight, 300), 900)
        barFontSize = min(max(barFontSize, 10), 16)
    }
}

// MARK: - 设置存储

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { persist() }
    }

    /// 任意设置变更后的回调（主线程）
    var onChange: ((AppSettings) -> Void)?

    private let defaultsKey = "clipstats.settings.v1"
    /// 允许通过环境变量指定独立的配置域（自检 / 便携运行）
    private let defaults: UserDefaults

    private init() {
        if let suite = ProcessInfo.processInfo.environment["CLIPSTATS_DEFAULTS_SUITE"],
           let scoped = UserDefaults(suiteName: suite) {
            defaults = scoped
        } else {
            defaults = .standard
        }
        if let data = defaults.data(forKey: defaultsKey),
           var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            decoded.normalize()
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: defaultsKey)
        onChange?(settings)
    }

    func set(_ transform: (inout AppSettings) -> Void) {
        var copy = settings
        transform(&copy)
        copy.normalize()
        settings = copy
    }

    func resetToDefaults() {
        settings = AppSettings()
    }

    func moveSegment(from source: IndexSet, to destination: Int) {
        set { $0.segments.move(fromOffsets: source, toOffset: destination) }
    }
}
