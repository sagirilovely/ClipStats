import Foundation

/// 每进程网速：调用系统自带的 /usr/bin/nettop 读取每个进程的累计收发字节数，做差得到速率。
/// nettop 免 root 可用，单次采样约 20ms，因此在后台队列按固定间隔执行，避免阻塞界面。
final class NetworkProcessMonitor {
    private let queue = DispatchQueue(label: "clipstats.nettop", qos: .utility)
    private let lock = NSLock()

    private var timer: DispatchSourceTimer?
    private var rates: [pid_t: (down: Double, up: Double)] = [:]
    private var previous: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
    private var previousDate: Date?
    private var isRunning = false

    private let interval: TimeInterval = 2.0

    // MARK: - 启停

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.interval, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.sample() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
            self.lock.lock()
            self.rates = [:]
            self.previous = [:]
            self.previousDate = nil
            self.lock.unlock()
        }
    }

    func snapshot() -> [pid_t: (down: Double, up: Double)] {
        lock.lock()
        defer { lock.unlock() }
        return rates
    }

    // MARK: - 采样

    private func sample() {
        let raw = Self.readNettop()
        guard !raw.isEmpty else { return }

        let now = Date()
        let elapsed = max(0.5, now.timeIntervalSince(previousDate ?? now.addingTimeInterval(-interval)))

        // 辅助进程的流量归并到所属应用
        var aggregated: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
        for (pid, bytes) in raw {
            let rid = ProcessIdentity.responsible(pid)
            var entry = aggregated[rid] ?? (0, 0)
            entry.rx &+= bytes.rx
            entry.tx &+= bytes.tx
            aggregated[rid] = entry
        }

        var fresh: [pid_t: (down: Double, up: Double)] = [:]
        for (rid, bytes) in aggregated {
            if let old = previous[rid] {
                fresh[rid] = (
                    Double(bytes.rx &- old.rx) / elapsed,
                    Double(bytes.tx &- old.tx) / elapsed
                )
            }
        }

        lock.lock()
        rates = fresh
        previous = aggregated
        previousDate = now
        lock.unlock()
    }

    private static func readNettop() -> [pid_t: (rx: UInt64, tx: UInt64)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = [
            "-P", "-L", "1", "-n",
            "-k", "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return [:] }

        var result: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
        var isFirstLine = true
        output.enumerateLines { line, _ in
            if isFirstLine {
                isFirstLine = false
                return
            }
            let columns = line.split(separator: ",")
            guard columns.count >= 3 else { return }

            let nameParts = columns[0].split(separator: ".")
            guard let pidPart = nameParts.last, let pid = pid_t(pidPart) else { return }
            guard let rx = UInt64(columns[1].trimmingCharacters(in: .whitespaces)),
                  let tx = UInt64(columns[2].trimmingCharacters(in: .whitespaces)) else { return }

            result[pid] = (rx, tx)
        }
        return result
    }
}
