import AppKit
import Darwin

// 每进程资源占用采样。
// CPU / 内存走 libproc（proc_listallpids + proc_pid_rusage），
// GPU 走 IOAccelerator 子节点的 AppUsage / accumulatedGPUTime（参考 Stats 的实现思路）。
// 辅助进程（Electron 的 Helper、Chrome 的渲染进程等）通过私有函数
// responsibility_get_pid_responsible_for_pid 归并到所属应用，避免数字被拆散。

/// 把辅助进程归并到所属应用的私有 API 封装
enum ProcessIdentity {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

    private static let responsibleFunction: ResponsibleFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleFn.self)
    }()

    static func responsible(_ pid: pid_t) -> pid_t {
        guard let function = responsibleFunction else { return pid }
        let rid = function(pid)
        return rid > 0 ? rid : pid
    }
}

struct ProcessSample: Identifiable {
    let pid: pid_t
    let name: String
    let cpu: Double        // 0...1，1 表示单核跑满
    let gpu: Double        // 0...1，GPU 时间占比
    let memory: UInt64     // bytes（phys_footprint）

    var id: pid_t { pid }
}

final class ProcessSampler {
    private struct Accumulator {
        var cpuTime: UInt64 = 0
        var gpuTime: UInt64 = 0
        var memory: UInt64 = 0
    }

    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousGPU: [pid_t: UInt64] = [:]
    private var previousDate: Date?

    // MARK: - 采样入口

    func sample(includeGPU: Bool) -> [ProcessSample] {
        let now = Date()
        let elapsed = max(0.2, now.timeIntervalSince(previousDate ?? now.addingTimeInterval(-1)))
        defer {
            previousDate = now
        }

        var accumulator: [pid_t: Accumulator] = [:]
        var responsibleOf: [pid_t: pid_t] = [:]

        for pid in Self.allPIDs() {
            guard let usage = Self.usage(pid) else { continue }
            let rid = responsiblePID(pid)
            responsibleOf[pid] = rid
            var entry = accumulator[rid] ?? Accumulator()
            entry.cpuTime &+= usage.cpu
            entry.memory = entry.memory &+ usage.footprint
            accumulator[rid] = entry
        }

        if includeGPU {
            for (pid, time) in Self.gpuTimes() {
                let rid = responsibleOf[pid] ?? responsiblePID(pid)
                var entry = accumulator[rid] ?? Accumulator()
                entry.gpuTime &+= time
                accumulator[rid] = entry
            }
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var samples: [ProcessSample] = []
        var nextCPU: [pid_t: UInt64] = [:]
        var nextGPU: [pid_t: UInt64] = [:]

        for (rid, entry) in accumulator {
            nextCPU[rid] = entry.cpuTime
            nextGPU[rid] = entry.gpuTime

            guard let app = NSRunningApplication(processIdentifier: rid),
                  app.activationPolicy == .regular,
                  !app.isTerminated,
                  rid != ownPID,
                  !Self.isSystemApp(app)
            else { continue }

            let cpuDelta = entry.cpuTime &- (previousCPU[rid] ?? entry.cpuTime)
            let gpuDelta = entry.gpuTime &- (previousGPU[rid] ?? entry.gpuTime)

            samples.append(ProcessSample(
                pid: rid,
                name: app.localizedName ?? Self.processName(rid),
                cpu: min(8, Double(cpuDelta) / 1_000_000_000 / elapsed),
                gpu: min(1, Double(gpuDelta) / 1_000_000_000 / elapsed),
                memory: entry.memory
            ))
        }

        previousCPU = nextCPU
        previousGPU = nextGPU
        return samples
    }

    // MARK: - 进程枚举

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let got = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        }
        guard got > 0 else { return [] }
        return Array(pids.prefix(Int(got))).filter { $0 > 0 }
    }

    private static func usage(_ pid: pid_t) -> (cpu: UInt64, footprint: UInt64)? {
        var info = rusage_info_current()
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                proc_pid_rusage(pid, 6 /* RUSAGE_INFO_CURRENT */, pointer)
            }
        }
        guard ok == 0 else { return nil }
        return (info.ri_user_time &+ info.ri_system_time, info.ri_phys_footprint)
    }

    private func responsiblePID(_ pid: pid_t) -> pid_t {
        ProcessIdentity.responsible(pid)
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            return String(cString: buffer)
        }
        return "pid \(pid)"
    }

    private static func isSystemApp(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier == "com.apple.finder" { return true }
        if let path = app.bundleURL?.path, path.hasPrefix("/System/Library/CoreServices/") {
            return true
        }
        return false
    }

    // MARK: - GPU

    private static func gpuTimes() -> [pid_t: UInt64] {
        var result: [pid_t: UInt64] = [:]

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        var accelerator = IOIteratorNext(iterator)
        while accelerator != 0 {
            var children: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS {
                defer { IOObjectRelease(children) }

                var child = IOIteratorNext(children)
                while child != 0 {
                    var properties: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let dictionary = properties?.takeRetainedValue() as? [String: Any],
                       let creator = dictionary["IOUserClientCreator"] as? String,
                       creator.hasPrefix("pid "),
                       let queues = dictionary["AppUsage"] as? [[String: Any]] {
                        let pidText = creator.dropFirst(4).split(separator: ",").first ?? ""
                        if let pid = pid_t(pidText.trimmingCharacters(in: .whitespaces)) {
                            let times = queues.compactMap {
                                ($0["accumulatedGPUTime"] as? NSNumber)?.uint64Value
                            }
                            if !times.isEmpty {
                                result[pid, default: 0] &+= times.reduce(0, +)
                            }
                        }
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(children)
                }
            }
            IOObjectRelease(accelerator)
            accelerator = IOIteratorNext(iterator)
        }
        return result
    }
}
