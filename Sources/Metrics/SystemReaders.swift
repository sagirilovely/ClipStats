// 部分实现参考自 Stats (https://github.com/exelban/stats)
// MIT License, Copyright (c) 2019 Serhiy Mytrovtsiy
// 详见项目根目录的 THIRD_PARTY_NOTICES.md

import Foundation
import IOKit

// MARK: - CPU

struct CPUSample {
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    var perCore: [Double] = []
}

final class CPUReader {
    private var previous: host_cpu_load_info?
    private var previousPerCore: [[UInt32]] = []

    func sample() -> CPUSample {
        var sample = CPUSample()
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if result == KERN_SUCCESS, let prev = previous {
            let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
            let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
            let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
            let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
            let total = user + system + idle + nice
            if total > 0 {
                sample.user = user / total
                sample.system = system / total
                sample.total = min(1, max(0, (user + system + nice) / total))
            }
        }
        previous = info
        sample.perCore = perCoreSample()
        return sample
    }

    private func perCoreSample() -> [Double] {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &numCpus, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo, numCpus > 0 else { return [] }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        var usage: [Double] = []
        current.reserveCapacity(Int(numCpus))
        usage.reserveCapacity(Int(numCpus))

        for cpu in 0..<Int(numCpus) {
            let base = cpu * states
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            current.append([user, system, idle, nice])

            if cpu < previousPerCore.count {
                let prev = previousPerCore[cpu]
                let dUser = Double(user &- prev[0])
                let dSystem = Double(system &- prev[1])
                let dIdle = Double(idle &- prev[2])
                let dNice = Double(nice &- prev[3])
                let total = dUser + dSystem + dIdle + dNice
                usage.append(total > 0 ? min(1, max(0, (dUser + dSystem + dNice) / total)) : 0)
            } else {
                usage.append(0)
            }
        }
        previousPerCore = current
        return usage
    }
}

// MARK: - GPU

struct GPUSample {
    var utilization: Double?
    var rendererUtilization: Double?
    var memoryUsed: Double?
    /// Apple Silicon 是统一内存：GPU 可用总量就是物理内存
    var memoryTotal: Double?
}

final class GPUReader {
    func sample() -> GPUSample {
        var sample = GPUSample()
        // Apple Silicon 是统一内存，GPU 可用的就是整块物理内存；
        // Intel 的独显/核显显存要走别的 IORegistry 键，这里不臆造
        #if arch(arm64)
        sample.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        #endif
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return sample }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = props?.takeRetainedValue() as? [String: Any],
              let perf = dictionary["PerformanceStatistics"] as? [String: Any] else {
            return sample
        }
        if let value = (perf["Device Utilization %"] as? NSNumber)?.doubleValue {
            sample.utilization = min(1, max(0, value / 100))
        } else if let value = (perf["GPU Activity(%)"] as? NSNumber)?.doubleValue {
            sample.utilization = min(1, max(0, value / 100))
        }
        if let value = (perf["Renderer Utilization %"] as? NSNumber)?.doubleValue {
            sample.rendererUtilization = min(1, max(0, value / 100))
        }
        if let value = (perf["In use system memory"] as? NSNumber)?.doubleValue {
            sample.memoryUsed = value
        }
        return sample
    }
}

// MARK: - 内存

struct MemorySample {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var free: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: Double = 0

    var usage: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

final class MemoryReader {
    func sample() -> MemorySample {
        var sample = MemorySample()
        sample.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return sample }

        let page = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let external = UInt64(stats.external_page_count) * page

        let usedSigned = Int64(active) + Int64(inactive) + Int64(speculative) + Int64(wired)
            + Int64(compressed) - Int64(purgeable) - Int64(external)
        let used = UInt64(max(0, usedSigned))
        sample.used = min(used, sample.total)
        sample.free = sample.total > used ? sample.total - used : 0
        sample.wired = wired
        sample.compressed = compressed
        sample.cached = purgeable + external

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            sample.swapUsed = swap.xsu_used
            sample.swapTotal = swap.xsu_total
        }

        var pressureLevel: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.stride
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &pressureSize, nil, 0) == 0 {
            sample.pressure = Double(pressureLevel)
        }
        return sample
    }
}

// MARK: - 网络

struct NetworkSample {
    var download: Double = 0   // bytes / second
    var upload: Double = 0
    var totalDownload: UInt64 = 0
    var totalUpload: UInt64 = 0
    var interfaceName: String = ""
}

final class NetworkReader {
    private var previous: (rx: UInt64, tx: UInt64)?
    private var previousDate: Date?
    private var lastTotals: (rx: UInt64, tx: UInt64) = (0, 0)

    private let ignoredPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "ap", "anpi",
                                   "gif", "stf", "ipsec", "p2p", "XHC", "vmenet"]

    func sample() -> NetworkSample {
        var sample = NetworkSample()
        let counters = readCounters()
        let now = Date()

        sample.totalDownload = counters.rx
        sample.totalUpload = counters.tx
        lastTotals = (counters.rx, counters.tx)

        if let previous, let previousDate {
            let elapsed = now.timeIntervalSince(previousDate)
            if elapsed > 0.05 {
                let rxDelta = counters.rx >= previous.rx ? counters.rx - previous.rx : 0
                let txDelta = counters.tx >= previous.tx ? counters.tx - previous.tx : 0
                sample.download = Double(rxDelta) / elapsed
                sample.upload = Double(txDelta) / elapsed
            }
        }
        self.previous = (counters.rx, counters.tx)
        self.previousDate = now
        return sample
    }

    private func readCounters() -> (rx: UInt64, tx: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.stride <= length {
                let pointer = base.advanced(by: offset)
                var header = if_msghdr()
                memcpy(&header, pointer, MemoryLayout<if_msghdr>.size)
                let messageLength = Int(header.ifm_msglen)
                if messageLength <= 0 { break }
                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    var header2 = if_msghdr2()
                    memcpy(&header2, pointer, MemoryLayout<if_msghdr2>.size)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ) + 1)
                    if if_indextoname(UInt32(header2.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        let ignored = ignoredPrefixes.contains { name.hasPrefix($0) }
                        if !ignored {
                            rx += UInt64(header2.ifm_data.ifi_ibytes)
                            tx += UInt64(header2.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += messageLength
            }
        }
        return (rx, tx)
    }
}
