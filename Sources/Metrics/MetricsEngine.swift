import Foundation

struct MetricsSnapshot {
    var cpu = CPUSample()
    var gpu = GPUSample()
    var memory = MemorySample()
    var network = NetworkSample()
    var thermal = ThermalSample()
    var updatedAt = Date()
}

/// 后台串行队列采样，主线程回调，避免阻塞 UI。
final class MetricsEngine {
    var onUpdate: ((MetricsSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "local.clipstats.metrics", qos: .utility)
    private var fastTimer: DispatchSourceTimer?
    private var thermalTimer: DispatchSourceTimer?
    private var snapshot = MetricsSnapshot()
    private var thermalEnabled = true

    private let cpuReader = CPUReader()
    private let gpuReader = GPUReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkReader()
    private let thermalReader = ThermalReader()

    func start(settings: AppSettings, thermalEnabled: Bool) {
        stop()
        self.thermalEnabled = thermalEnabled

        let fastInterval = max(0.5, settings.metricsInterval)
        let fast = DispatchSource.makeTimerSource(queue: queue)
        fast.schedule(deadline: .now(), repeating: fastInterval, leeway: .milliseconds(100))
        fast.setEventHandler { [weak self] in self?.sampleFast() }
        fast.resume()
        fastTimer = fast

        if thermalEnabled {
            let thermalInterval = max(1, settings.thermalInterval)
            let thermal = DispatchSource.makeTimerSource(queue: queue)
            thermal.schedule(deadline: .now() + 0.3, repeating: thermalInterval, leeway: .milliseconds(300))
            thermal.setEventHandler { [weak self] in self?.sampleThermal() }
            thermal.resume()
            thermalTimer = thermal
        }
    }

    func stop() {
        fastTimer?.cancel()
        fastTimer = nil
        thermalTimer?.cancel()
        thermalTimer = nil
    }

    private func sampleFast() {
        snapshot.cpu = cpuReader.sample()
        snapshot.gpu = gpuReader.sample()
        snapshot.memory = memoryReader.sample()
        snapshot.network = networkReader.sample()
        snapshot.updatedAt = Date()
        deliver()
    }

    private func sampleThermal() {
        guard thermalEnabled else { return }
        snapshot.thermal = thermalReader.sample()
        snapshot.updatedAt = Date()
        deliver()
    }

    private func deliver() {
        let current = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(current)
        }
    }
}
