// 部分实现参考自 Stats (https://github.com/exelban/stats)
// MIT License, Copyright (c) 2019 Serhiy Mytrovtsiy
// 详见项目根目录的 THIRD_PARTY_NOTICES.md

import Foundation

enum TemperatureGroup: String {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "内存"
    case battery = "电池"
    case ambient = "环境"
    case other = "其它"
}

struct TemperatureReading: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let group: TemperatureGroup
    let value: Double
}

struct ThermalSample {
    var smcAvailable: Bool = false
    var cpuTemperature: Double?
    var cpuTemperatureAverage: Double?
    var gpuTemperature: Double?
    var ambientTemperature: Double?
    var fanRPM: Double?
    var readings: [TemperatureReading] = []
}

/// 通过 AppleSMC 读取温度。首次使用枚举全部键并动态分类，
/// 因为不同芯片/系统版本的键名并不一致（本项目实测机型的键名与常见 M1 列表不同）。
final class ThermalReader {
    private let smc = SMCConnection()
    private var temperatureKeys: [String] = []
    private var lastDiscovery = Date.distantPast
    private let discoveryInterval: TimeInterval = 300

    func sample() -> ThermalSample {
        var sample = ThermalSample()
        sample.smcAvailable = smc.isOpen
        guard smc.isOpen else { return sample }

        if temperatureKeys.isEmpty || Date().timeIntervalSince(lastDiscovery) > discoveryInterval {
            discoverKeys()
        }
        guard !temperatureKeys.isEmpty else { return sample }

        var grouped: [TemperatureGroup: [Double]] = [:]
        for key in temperatureKeys {
            guard let value = smc.readValue(key), value > 0.5, value < 125 else { continue }
            let group = Self.group(for: key)
            grouped[group, default: []].append(value)
            sample.readings.append(TemperatureReading(key: key, group: group, value: value))
        }

        sample.cpuTemperature = grouped[.cpu]?.max()
        if let values = grouped[.cpu], !values.isEmpty {
            sample.cpuTemperatureAverage = values.reduce(0, +) / Double(values.count)
        }
        sample.gpuTemperature = grouped[.gpu]?.max()
        sample.ambientTemperature = grouped[.ambient]?.max()

        // 风扇（Apple Silicon MacBook Air 无风扇，读不到就是 nil）
        if let fan = smc.readValue("F0Ac"), fan > 0 {
            sample.fanRPM = fan
        }
        sample.readings.sort { $0.key < $1.key }
        return sample
    }

    private func discoverKeys() {
        lastDiscovery = Date()
        let allKeys = smc.allKeys()
        guard !allKeys.isEmpty else { return }
        var keys: [String] = []
        for key in allKeys where key.hasPrefix("T") && key.count == 4 {
            guard let value = smc.readValue(key) else { continue }
            if value > 0.5 && value < 125 {
                keys.append(key)
            }
        }
        temperatureKeys = keys
        NSLog("ClipStats: discovered \(keys.count) temperature keys")
    }

    static func group(for key: String) -> TemperatureGroup {
        if key.hasPrefix("Tg") || key.hasPrefix("TG") { return .gpu }
        if key.hasPrefix("TB") { return .battery }
        if key.hasPrefix("Ta") { return .ambient }
        if key.hasPrefix("Tm") || key.hasPrefix("TM") { return .memory }
        if key.hasPrefix("Tp") || key.hasPrefix("Tc") || key.hasPrefix("Te")
            || key.hasPrefix("Th") || key.hasPrefix("Tf") {
            return .cpu
        }
        return .other
    }
}
