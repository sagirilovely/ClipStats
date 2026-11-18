import Foundation

enum Fmt {
    /// 单机不可能达到的量级，超过它一律视为异常数据
    private static let absurdBytes: Double = 1e12

    /// 复用同一个 formatter：每行每帧新建 DateFormatter 是毫秒级开销
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    /// 0.23 -> "23%"
    static func percent(_ value: Double, digits: Int = 0) -> String {
        guard value.isFinite else { return "--" }
        let pct = max(0, min(1, value)) * 100
        return String(format: "%.0f%%", pct)
    }

    /// bytes per second -> "1.2M", "860K", "12B"
    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "--" }
        // 兜底：超过 1 TB/s 的速率在单机上不可能出现，说明采样出了问题
        guard bytesPerSecond < Self.absurdBytes else { return "--" }
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

    /// bytes -> 紧凑写法，去掉无意义的小数：16G、1.5G、523M
    static func compactBytes(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--" }
        guard value < absurdBytes else { return "--" }
        let units = ["B", "K", "M", "G", "T"]
        var scaled = value
        var index = 0
        while scaled >= 1024 && index < units.count - 1 {
            scaled /= 1024
            index += 1
        }
        let number: String
        if scaled >= 100 {
            number = String(format: "%.0f", scaled)
            // 1023.6M 取整后会变成 1024M，这里进位成 1G
            if number == "1024", index < units.count - 1 {
                return "1" + units[index + 1]
            }
        } else if scaled >= 10 {
            number = Self.trimZeros(String(format: "%.1f", scaled))
        } else {
            number = Self.trimZeros(String(format: "%.2f", scaled))
        }
        return number + units[index]
    }

    /// "16.0" -> "16"、"1.50" -> "1.5"、"1.00" -> "1"
    private static func trimZeros(_ text: String) -> String {
        guard text.contains(".") else { return text }
        var result = text
        while result.hasSuffix("0") {
            result.removeLast()
        }
        if result.hasSuffix(".") {
            result.removeLast()
        }
        return result
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
        return Fmt.dayFormatter.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
