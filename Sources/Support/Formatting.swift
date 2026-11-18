import Foundation

enum Fmt {
    /// 0.23 -> "23%"
    static func percent(_ value: Double, digits: Int = 0) -> String {
        guard value.isFinite else { return "--" }
        let pct = max(0, min(1, value)) * 100
        return String(format: "%.0f%%", pct)
    }

    /// bytes per second -> "1.2M", "860K", "12B"
    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "--" }
        let units = ["B", "K", "M", "G", "T"]
        var value = bytesPerSecond
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 { return String(format: "%.0f%@", value, units[index]) }
        if value >= 100 { return String(format: "%.0f%@", value, units[index]) }
        if value >= 10 { return String(format: "%.1f%@", value, units[index]) }
        return String(format: "%.2f%@", value, units[index])
    }

    /// bytes -> human readable
    static func bytes(_ value: Double) -> String {
        speed(value)
    }

    /// 62.4 -> "62°"
    static func temperature(_ celsius: Double) -> String {
        guard celsius.isFinite, celsius > 0 else { return "--" }
        return String(format: "%.0f°", celsius)
    }

    /// memory usage "9.8/16G"
    static func memory(used: Double, total: Double) -> String {
        guard total > 0 else { return "--" }
        return String(format: "%.0f%%", used / total * 100)
    }

    static func relativeTime(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 5 { return "刚刚" }
        if delta < 60 { return String(format: "%.0f 秒前", delta) }
        if delta < 3600 { return String(format: "%.0f 分钟前", delta / 60) }
        if delta < 86400 { return String(format: "%.0f 小时前", delta / 3600) }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
