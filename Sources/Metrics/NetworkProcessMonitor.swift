import Foundation

/// 每进程网速：调用系统自带的 /usr/bin/nettop 读取每个进程的累计收发字节数，做差得到速率。
/// nettop 免 root 可用，单次采样约 20ms，因此在后台队列按固定间隔执行，避免阻塞界面。
final class NetworkProcessMonitor {
    private let queue = DispatchQueue(label: "clipstats.nettop", qos: .utility)
    private let lock = NSLock()

    private var timer: DispatchSourceTimer?
    private var rates: [pid_t: (down: Double, up: Double)] = [:]
    /// 上一轮每个「原始 pid」的累计字节数 + 进程启动时间（启动时间变了说明 pid 被复用）
    private var previous: [pid_t: (rx: UInt64, tx: UInt64, started: UInt64)] = [:]
    private var previousDate: Date?
    private var ratesDate: Date?
    private var isRunning = false

    private let interval: TimeInterval = 2.0
    /// 单进程速率上限（100GbE 线速）。任何真实网卡都不可能跑过它，超过就一定是计数器被重置
    private static let maxRatePerSecond: Double = 12.5 * 1024 * 1024 * 1024
    /// nettop 单次执行的最长等待时间
    private static let nettopTimeout: DispatchTimeInterval = .seconds(3)

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
            self.ratesDate = nil
            self.lock.unlock()
        }
    }

    func snapshot() -> [pid_t: (down: Double, up: Double)] {
        lock.lock()
        defer { lock.unlock() }
        // 采样卡住时不要把过期数据当成实时速率一直显示
        guard let ratesDate, Date().timeIntervalSince(ratesDate) < interval * 2 + 1 else { return [:] }
        return rates
    }

    // MARK: - 采样

    private func sample() {
        let raw = Self.readNettop()
        guard !raw.isEmpty else { return }

        let now = Date()
        let elapsed = max(0.5, now.timeIntervalSince(previousDate ?? now.addingTimeInterval(-interval)))
        let maxDelta = UInt64(Self.maxRatePerSecond * elapsed)

        // 先按原始 pid 算增量，再把增量归并到所属应用。
        // 不能先归并累计值再相减：辅助进程退出会让归并后的总数变小，
        // 无符号相减会回绕成 1.8e19 字节，除以间隔就显示成「xxxxxx T」。
        var fresh: [pid_t: (down: Double, up: Double)] = [:]
        var nextPrevious: [pid_t: (rx: UInt64, tx: UInt64, started: UInt64)] = [:]
        nextPrevious.reserveCapacity(raw.count)

        for (pid, bytes) in raw {
            let started = ProcessIdentity.startTime(pid)
            nextPrevious[pid] = (bytes.rx, bytes.tx, started)
            guard let old = previous[pid] else { continue }        // 首次采样只建立基线
            guard old.started == started else { continue }          // pid 被复用，旧基线作废
            guard bytes.rx >= old.rx, bytes.tx >= old.tx else { continue }
            let rxDelta = bytes.rx - old.rx
            let txDelta = bytes.tx - old.tx
            guard rxDelta <= maxDelta, txDelta <= maxDelta else { continue }

            let responsible = ProcessIdentity.responsible(pid)
            var entry = fresh[responsible] ?? (0, 0)
            entry.down += Double(rxDelta) / elapsed
            entry.up += Double(txDelta) / elapsed
            fresh[responsible] = entry
        }

        // 归并之后再兜一次，任何应用都不该超过单机线速
        fresh = fresh.filter { $0.value.down <= Self.maxRatePerSecond && $0.value.up <= Self.maxRatePerSecond }

        lock.lock()
        rates = fresh
        previous = nextPrevious
        previousDate = now
        ratesDate = now
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

        // 看门狗：nettop 在睡眠唤醒或系统负载极高时可能卡住，采样线程不能无限等下去
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return [:]
        }

        if finished.wait(timeout: .now() + Self.nettopTimeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1.0)
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

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

            // 同一个 pid 万一出现多行（多接口）就累加，而不是互相覆盖
            var entry = result[pid] ?? (0, 0)
            entry.rx &+= rx
            entry.tx &+= tx
            result[pid] = entry
        }
        return result
    }
}
