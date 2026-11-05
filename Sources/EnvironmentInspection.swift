import Foundation
import Combine
import Darwin

struct PythonPackageStatus: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let version: String?
    let required: Bool
    var id: String { name }
}
struct PythonEnvironmentReport: Codable, Equatable, Sendable {
    let executable: String
    let version: String
    let implementation: String
    let architecture: String
    let prefix: String
    let packages: [PythonPackageStatus]
    var missingRequired: [PythonPackageStatus] { packages.filter { $0.required && $0.version == nil } }
    func installCommand(pythonPath: String) -> String? {
        let missing = missingRequired.map(\.name)
        guard !missing.isEmpty else { return nil }
        return Self.shellQuote(pythonPath) + " -m pip install " + missing.map(Self.shellQuote).joined(separator: " ")
    }
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var summary: String {
        (["Python \(version) (\(implementation), \(architecture))", executable, "Environment: " + prefix] +
            packages.map { $0.name + ": " + ($0.version ?? "not installed") }).joined(separator: "\n")
    }
}

/// Checks installed package metadata only; it neither imports heavy frameworks
/// nor changes the selected environment. Each operation owns its subprocess.
final class EnvironmentProbeOperation: @unchecked Sendable {
    enum Failure: LocalizedError {
        case invalidPath, cancelled, timedOut, oversized, failed(String), invalidResponse
        var errorDescription: String? {
            switch self {
            case .invalidPath: return "Choose an absolute path to an executable Python file."
            case .cancelled: return "Environment check cancelled."
            case .timedOut: return "The environment check timed out. Check the Python path and try again."
            case .oversized: return "The environment check returned too much output. Check that this is a Python executable."
            case .failed(let detail): return "The environment could not be inspected. " + detail
            case .invalidResponse: return "This executable did not return Python environment information."
            }
        }
    }
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    private static let outputLimit = 128 * 1024
    private static let script = #"""
import sys, platform, json, importlib.metadata as metadata
required = ['jupyter_client', 'ipykernel', 'numpy', 'pandas', 'matplotlib']
optional = ['scipy', 'scikit-learn', 'torch', 'tensorflow', 'polars', 'duckdb']
packages = []
for name in required + optional:
    try: version = metadata.version(name)
    except metadata.PackageNotFoundError: version = None
    packages.append(dict(name=name, version=version, required=name in required))
print(json.dumps(dict(executable=sys.executable, version=platform.python_version(), implementation=platform.python_implementation(), architecture=platform.machine(), prefix=sys.prefix, packages=packages)))
"""#
    func run(pythonPath: String, timeout: TimeInterval = 8) throws -> PythonEnvironmentReport {
        var directory: ObjCBool = false
        guard pythonPath.hasPrefix("/"), FileManager.default.fileExists(atPath: pythonPath, isDirectory: &directory),
              !directory.boolValue, FileManager.default.isExecutableFile(atPath: pythonPath) else { throw Failure.invalidPath }
        guard !isCancelled else { throw Failure.cancelled }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-environment-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let stdoutURL = temporary.appendingPathComponent("stdout"), stderrURL = temporary.appendingPathComponent("stderr")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL), stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-I", "-c", Self.script]
        process.currentDirectoryURL = temporary
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout; process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONHOME"); environment.removeValue(forKey: "PYTHONPATH")
        process.environment = environment
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        do { try process.run() } catch { throw Failure.failed(error.localizedDescription) }
        let seconds = timeout.isFinite ? min(20, max(0.1, timeout)) : 8
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1_000_000_000)
        var failure: Failure?
        func size(_ url: URL) -> Int {
            ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
        }
        while ended.wait(timeout: .now() + 0.05) == .timedOut {
            if isCancelled { failure = .cancelled; break }
            if size(stdoutURL) > Self.outputLimit || size(stderrURL) > Self.outputLimit { failure = .oversized; break }
            if DispatchTime.now().uptimeNanoseconds >= deadline { failure = .timedOut; break }
        }
        if failure != nil {
            if process.isRunning { process.terminate() }
            if ended.wait(timeout: .now() + 0.4) == .timedOut, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                _ = ended.wait(timeout: .now() + 0.3)
            }
        }
        if isCancelled { throw Failure.cancelled }
        if let failure { throw failure }
        func read(_ url: URL) throws -> Data {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.outputLimit + 1) ?? Data()
            guard data.count <= Self.outputLimit else { throw Failure.oversized }
            return data
        }
        let data = try read(stdoutURL), errors = try read(stderrURL)
        guard !process.isRunning, process.terminationStatus == 0 else {
            let detail = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed(String(detail.prefix(1200)))
        }
        guard let report = try? JSONDecoder().decode(PythonEnvironmentReport.self, from: data),
              !report.version.isEmpty, !report.executable.isEmpty else { throw Failure.invalidResponse }
        return report
    }
}

@MainActor final class EnvironmentInspectionModel: ObservableObject {
    @Published private(set) var report: PythonEnvironmentReport?
    @Published private(set) var error: String?
    @Published private(set) var isChecking = false
    private var operation: EnvironmentProbeOperation?
    private var generation = UUID()
    func check(pythonPath: String) {
        cancel()
        let token = generation
        let operation = EnvironmentProbeOperation()
        self.operation = operation; report = nil; error = nil; isChecking = true
        Task.detached(priority: .utility) { [weak self] in
            let result = Result { try operation.run(pythonPath: pythonPath) }
            await MainActor.run { [weak self] in
                guard let self, self.generation == token else { return }
                self.operation = nil; self.isChecking = false
                switch result {
                case .success(let report): self.report = report
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    func cancel(clearResult: Bool = true) {
        generation = UUID(); operation?.cancel(); operation = nil; isChecking = false
        if clearResult { report = nil; error = nil }
    }
}
