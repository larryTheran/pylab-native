import Foundation
import Darwin

@main struct RuntimeEnvironmentChecks {
    @MainActor static func main() throws {
        var accumulator = KernelActivityAccumulator(historyLimit: 3)
        func reading(_ time: UInt64, _ cpu: UInt64, start: UInt64 = 9, pid: Int32 = 11) -> KernelActivityReading {
            KernelActivityReading(pid: pid, processStart: start, uptimeNanoseconds: time, cpuNanoseconds: cpu, residentBytes: time)
        }
        precondition(accumulator.update(reading(1_000_000_000, 200_000_000)).cpuPercent == nil)
        let active = accumulator.update(reading(3_000_000_000, 3_200_000_000))
        precondition(abs((active.cpuPercent ?? 0) - 150) < 0.0001, "CPU must permit multiple busy cores")
        for n in 4...8 { _ = accumulator.update(reading(UInt64(n) * 1_000_000_000, UInt64(n) * 1_000_000_000)) }
        precondition(accumulator.history.count == 3 && accumulator.history.last?.residentBytes == 8_000_000_000)
        precondition(accumulator.update(reading(9_000_000_000, 9_000_000_000, start: 10)).cpuPercent == nil && accumulator.history.count == 1, "PID reuse must reset CPU/history")
        precondition(accumulator.update(reading(10_000_000_000, 1, start: 10)).cpuPercent == nil, "Counter reset must not underflow")
        accumulator.reset(); precondition(accumulator.history.isEmpty)
        precondition(KernelActivityMonitor.read(pid: -1) == nil)
        guard let selfReading = KernelActivityMonitor.read(pid: getpid()) else { preconditionFailure("Native process statistics unavailable") }
        precondition(selfReading.residentBytes > 0 && selfReading.processStart > 0)
        let monitor = KernelActivityMonitor()
        var updates = 0
        monitor.onUpdate = { snapshot, _, unavailable in precondition(snapshot != nil && !unavailable); updates += 1 }
        monitor.start(pid: getpid()); precondition(updates == 1)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.6)); precondition(updates >= 2)
        monitor.stop(); let stopped = updates
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.6)); precondition(updates == stopped, "Stopped monitor kept polling")

        let missing = PythonPackageStatus(name: "numpy", version: nil, required: true)
        let report = PythonEnvironmentReport(executable: "/tmp/python", version: "3.12", implementation: "CPython", architecture: "arm64", prefix: "/tmp", packages: [missing, PythonPackageStatus(name: "torch", version: nil, required: false)])
        let command = report.installCommand(pythonPath: "/tmp/Python's env/bin/python")!
        precondition(command == "'/tmp/Python'\\''s env/bin/python' -m pip install 'numpy'")
        precondition(report.missingRequired.count == 1)
        let actual = try EnvironmentProbeOperation().run(pythonPath: "/opt/miniconda3/bin/python3.12")
        precondition(!actual.version.isEmpty && actual.packages.contains { $0.name == "numpy" } && actual.packages.filter(\.required).count == 5)
        do { _ = try EnvironmentProbeOperation().run(pythonPath: "/not/a/python"); preconditionFailure("Invalid executable accepted") }
        catch EnvironmentProbeOperation.Failure.invalidPath { }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-probe-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        func script(_ name: String, _ source: String) throws -> String {
            let url = directory.appendingPathComponent(name)
            try source.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url.path
        }
        let invalid = try script("not-python", "#!/bin/sh\nprintf hello\n")
        do { _ = try EnvironmentProbeOperation().run(pythonPath: invalid); preconditionFailure("Malformed response accepted") }
        catch EnvironmentProbeOperation.Failure.invalidResponse { }
        let failed = try script("failure", "#!/bin/sh\nprintf 'deliberate probe failure' >&2\nexit 1\n")
        do { _ = try EnvironmentProbeOperation().run(pythonPath: failed); preconditionFailure("Failure accepted") }
        catch EnvironmentProbeOperation.Failure.failed(let detail) { precondition(detail.contains("deliberate probe failure")) }
        let noisy = try script("noisy", "#!/opt/miniconda3/bin/python3.12\nprint('x' * 200000)\n")
        do { _ = try EnvironmentProbeOperation().run(pythonPath: noisy); preconditionFailure("Oversized response accepted") }
        catch EnvironmentProbeOperation.Failure.oversized { }
        let slow = try script("slow", "#!/bin/sh\nexec /bin/sleep 20\n")
        let start = Date()
        do { _ = try EnvironmentProbeOperation().run(pythonPath: slow, timeout: 0.2); preconditionFailure("Timeout was ignored") }
        catch EnvironmentProbeOperation.Failure.timedOut { precondition(Date().timeIntervalSince(start) < 2) }
        let operation = EnvironmentProbeOperation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { operation.cancel() }
        do { _ = try operation.run(pythonPath: slow); preconditionFailure("Cancellation was ignored") }
        catch EnvironmentProbeOperation.Failure.cancelled { }
        let model = EnvironmentInspectionModel()
        model.check(pythonPath: slow)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        model.check(pythonPath: "/opt/miniconda3/bin/python3.12")
        let deadline = Date(timeIntervalSinceNow: 8)
        while model.isChecking && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        precondition(model.report?.version == actual.version && model.error == nil, "Cancelled stale result replaced latest environment")
        model.cancel(); precondition(model.report == nil && !model.isChecking)
        print("PASS: native process readings, per-core CPU math, bounded history/PID reset, timer cleanup; environment metadata, shell quoting, failures, timeout/cancel/output bounds and stale-result rejection")
    }
}
