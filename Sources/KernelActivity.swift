import Foundation
import SwiftUI
import Darwin

struct KernelActivityReading: Sendable {
    let pid: Int32
    let processStart: UInt64
    let uptimeNanoseconds: UInt64
    let cpuNanoseconds: UInt64
    let residentBytes: UInt64
}

struct KernelActivitySnapshot: Equatable, Sendable {
    let pid: Int32
    let cpuPercent: Double?
    let residentBytes: UInt64
    var memoryText: String { ByteCountFormatter.string(fromByteCount: Int64(clamping: residentBytes), countStyle: .memory) }
    var cpuText: String { cpuPercent.map { String(format: "%.0f%%", $0) } ?? "—" }
}

struct KernelActivitySample: Equatable, Identifiable, Sendable {
    let timestamp: UInt64
    let cpuPercent: Double?
    let residentBytes: UInt64
    var id: UInt64 { timestamp }
}

/// CPU uses cumulative process time divided by monotonic wall time. One busy
/// core is 100%; multithreaded scientific code can legitimately exceed 100%.
struct KernelActivityAccumulator {
    private var previous: KernelActivityReading?
    private(set) var history: [KernelActivitySample] = []
    let historyLimit: Int
    init(historyLimit: Int = 60) { self.historyLimit = max(1, historyLimit) }
    mutating func reset() { previous = nil; history = [] }
    mutating func update(_ reading: KernelActivityReading) -> KernelActivitySnapshot {
        var percent: Double?
        if let previous, previous.pid == reading.pid, previous.processStart == reading.processStart,
           reading.uptimeNanoseconds > previous.uptimeNanoseconds, reading.cpuNanoseconds >= previous.cpuNanoseconds {
            let value = Double(reading.cpuNanoseconds - previous.cpuNanoseconds) / Double(reading.uptimeNanoseconds - previous.uptimeNanoseconds) * 100
            if value.isFinite { percent = value }
        } else { history.removeAll() }
        previous = reading
        let sample = KernelActivitySample(timestamp: reading.uptimeNanoseconds, cpuPercent: percent, residentBytes: reading.residentBytes)
        history.append(sample)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
        return KernelActivitySnapshot(pid: reading.pid, cpuPercent: percent, residentBytes: reading.residentBytes)
    }
}

@MainActor
final class KernelActivityMonitor {
    var onUpdate: ((KernelActivitySnapshot?, [KernelActivitySample], Bool) -> Void)?
    private var timer: Timer?
    private var accumulator = KernelActivityAccumulator()
    private var pid: Int32?
    deinit { timer?.invalidate() }
    func start(pid: Int32) {
        stop()
        guard pid > 0 else { onUpdate?(nil, [], true); return }
        self.pid = pid
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer?.tolerance = 0.3
    }
    func stop() {
        timer?.invalidate(); timer = nil; pid = nil; accumulator.reset()
    }
    private func sample() {
        guard let pid else { return }
        guard let reading = Self.read(pid: pid) else {
            accumulator.reset()
            onUpdate?(nil, [], true)
            return
        }
        let snapshot = accumulator.update(reading)
        onUpdate?(snapshot, accumulator.history, false)
    }
    static func read(pid: Int32) -> KernelActivityReading? {
        guard pid > 0 else { return nil }
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        let (cpu, overflow) = usage.ri_user_time.addingReportingOverflow(usage.ri_system_time)
        guard result == 0, !overflow else { return nil }
        return KernelActivityReading(pid: pid, processStart: usage.ri_proc_start_abstime,
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds, cpuNanoseconds: cpu, residentBytes: usage.ri_resident_size)
    }
}

struct KernelActivityView: View {
    let activity: KernelActivitySnapshot?
    let history: [KernelActivitySample]
    var unavailable = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Python Activity", systemImage: "waveform.path.ecg").font(.headline)
            if let activity {
                HStack {
                    metric("CPU", value: activity.cpuText, symbol: "cpu")
                    Spacer()
                    metric("Resident memory", value: activity.memoryText, symbol: "memorychip")
                }
                ActivitySparkline(values: history.compactMap(\.cpuPercent), tint: .accentColor)
                    .frame(height: 44).accessibilityLabel("Recent Python CPU usage")
                Text("PID \(activity.pid) · samples about every 2 seconds")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Measures this project's Python process. One CPU core at full use is 100%; multiple cores can exceed 100%. Memory is current resident usage, not a configured limit.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(unavailable ? "Activity readings are unavailable for this Python process." : "Activity appears when the Python kernel is ready.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.padding(18).frame(width: 315)
    }
    private func metric(_ label: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

private struct ActivitySparkline: View {
    let values: [Double]
    let tint: Color
    var body: some View {
        GeometryReader { geometry in
            let maximum = max(100, values.max() ?? 100)
            let points = values.enumerated().map { index, value in
                CGPoint(x: geometry.size.width * CGFloat(index) / CGFloat(max(1, values.count - 1)),
                        y: geometry.size.height * CGFloat(1 - min(max(0, value), maximum) / maximum))
            }
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }.stroke(tint, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
        }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }
}
