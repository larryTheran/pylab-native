import Foundation
import Combine

struct KernelEvent {
    let id: String?
    let type: String
    let text: String?
    let image: String?
    let count: Int?
    let wait: Bool?
    let displayID: String?
    let isDisplayUpdate: Bool
    let displayData: [String: Any]?
    let displayMetadata: [String: Any]?
    let notebookTextOutput: [String: Any]?

    init(id: String?, type: String, text: String?, image: String?, count: Int?, wait: Bool?,
         displayID: String? = nil, isDisplayUpdate: Bool = false,
         displayData: [String: Any]? = nil, displayMetadata: [String: Any]? = nil,
         streamName: String? = nil, errorName: String? = nil, errorValue: String? = nil,
         traceback: [String]? = nil) {
        self.id = id; self.type = type; self.text = text; self.image = image
        self.count = count; self.wait = wait
        self.displayID = displayID.flatMap { !$0.isEmpty && $0.utf8.count <= 4096 ? $0 : nil }
        self.isDisplayUpdate = isDisplayUpdate
        if type == "error", let errorName {
            self.notebookTextOutput = ["output_type": "error", "ename": errorName,
                                       "evalue": errorValue ?? "", "traceback": traceback ?? []]
        } else if let text, !text.isEmpty, type == "stream" || type == "error" {
            // Controller and legacy bridge errors have no Python traceback.
            let channel = type == "error" || streamName == "stderr" ? "stderr" : "stdout"
            self.notebookTextOutput = ["output_type": "stream", "name": channel, "text": text]
        } else {
            self.notebookTextOutput = nil
        }
        if ["image", "result", "display"].contains(type) {
            var bundle = displayData ?? [:]
            if let image { bundle["image/png"] = image }
            if type == "result", let text { bundle["text/plain"] = text }
            self.displayData = bundle
            self.displayMetadata = displayMetadata ?? [:]
        } else {
            self.displayData = displayData
            self.displayMetadata = displayMetadata
        }
    }
}

struct WorkspaceVariable: Identifiable {
    let name: String
    let type: String
    let shape: String
    let value: String
    let editable: Bool
    let originID: String?
    let exportExtension: String?
    let exportLabel: String?
    let plottable: Bool
    var savable: Bool { exportExtension != nil }
    var scopeID: String? = nil
    var id: String { Self.identity(name: name, scopeID: scopeID) }
    static func identity(name: String, scopeID: String?) -> String {
        scopeID.map { "scope:" + String($0.utf8.count) + ":" + $0 + ":" + name } ?? ("shared:" + name)
    }
}

struct WorkspaceTable {
    let name: String
    let columns: [String]
    let indices: [String]
    let cells: [[String]]
    let total: Int
    let width: Int
    let offset: Int
    var scopeID: String? = nil
}

struct VariableStatisticField: Codable, Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct VariableStatisticColumn: Codable, Identifiable {
    let title: String
    let fields: [VariableStatisticField]
    var id: String { title }
}

struct VariableStatistics: Codable {
    let name: String
    let type: String
    let shape: String
    let fields: [VariableStatisticField]
    let columns: [VariableStatisticColumn]
    let notes: [String]
}

enum KernelExecutionSource: String {
    case cell, console
    case internalCommand = "internal"
}

/// Bounds one JSON-lines frame, including an unfinished line, before decoding.
/// Large plots remain supported up to 128 MiB per protocol message; a broken or
/// noisy pipe cannot grow the desktop's partial-message storage indefinitely.
struct KernelMessageBuffer {
    enum Failure: LocalizedError {
        case messageTooLarge
        var errorDescription: String? {
            "A kernel message exceeded the 128 MiB limit. Restart the kernel; reduce very large displayed images or outputs and save them to a file instead."
        }
    }
    private var pending = Data()
    let maximumMessageBytes: Int
    init(maximumMessageBytes: Int = 128 * 1024 * 1024) { self.maximumMessageBytes = maximumMessageBytes }
    mutating func clear() { pending.removeAll() }
    mutating func append(_ data: Data) throws -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0a) {
            guard pending.distance(from: pending.startIndex, to: newline) <= maximumMessageBytes else {
                clear(); throw Failure.messageTooLarge
            }
            lines.append(Data(pending.prefix(upTo: newline)))
            pending.removeSubrange(...newline)
        }
        guard pending.count <= maximumMessageBytes else { clear(); throw Failure.messageTooLarge }
        return lines
    }
}

@MainActor
final class KernelController: ObservableObject {
    @Published var state = "Disconnected"
    @Published var workspace: [WorkspaceVariable] = []
    @Published var table: WorkspaceTable?
    @Published var workspaceError: String?
    @Published var tableError: String?
    @Published var inputPrompt: String?
    @Published var inputIsPassword = false
    @Published var inputRequestID: String?
    @Published private(set) var executionActivities: [String: KernelExecutionActivity] = [:]
    @Published private(set) var activity: KernelActivitySnapshot?
    @Published private(set) var activityHistory: [KernelActivitySample] = []
    @Published private(set) var activityUnavailable = false
    private var activityMonitor: KernelActivityMonitor?
    var onEvent: ((KernelEvent) -> Void)?

    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = KernelMessageBuffer()
    private var currentDirectory: URL?
    private var lastTable: (name: String, offset: Int, scopeID: String?)?
    private var exportCallbacks: [String: (String?) -> Void] = [:]
    private var plotCallbacks: [String: (Data?, String?) -> Void] = [:]
    private var plotFormats: [String: String] = [:]
    private var completionCallbacks: [String: ([String], Int, Int) -> Void] = [:]
    private var statisticsCallbacks: [String: (VariableStatistics?, String?) -> Void] = [:]
    private var manageCallbacks: [String: (String?) -> Void] = [:]
    private var directoryCallbacks: [String: (URL, (String?) -> Void)] = [:]
    private var executions = Set<String>()
    private var sessionFailure: String?
    @Published private(set) var interpreter: String
    @Published private(set) var variableMode: VariableSharingMode
    private static let pythonPreferenceKey = "kernelPython"
    private let preferences: UserDefaults

    init(python: String? = nil, preferences: UserDefaults = .standard, variableMode: VariableSharingMode = .shared) {
        self.preferences = preferences
        self.variableMode = variableMode
        interpreter = ProcessInfo.processInfo.environment["PYLAB_KERNEL_PYTHON"] ?? python
            ?? preferences.string(forKey: Self.pythonPreferenceKey)
            ?? "/opt/miniconda3/bin/python3.12"
    }

    /// The caller confirms clearing live values before changing an active mode.
    /// Initial/stopped configuration deliberately does not launch a process.
    func setVariableMode(_ mode: VariableSharingMode, cwd: URL? = nil) {
        guard variableMode != mode else { return }
        let wasStarted = process != nil
        variableMode = mode
        if wasStarted { restart(cwd: cwd) }
        else {
            currentDirectory = cwd ?? currentDirectory
            clearLiveState()
        }
    }

    private func normalizedScope(_ scopeID: String?) -> String? {
        guard variableMode == .independent else { return nil }
        return scopeID.flatMap { $0.isEmpty ? nil : $0 } ?? "internal:console"
    }

    private func scopedMessage(_ message: [String: Any], scopeID: String?) -> [String: Any] {
        var result = message
        if let scope = normalizedScope(scopeID) { result["scope_id"] = scope }
        return result
    }

    /// Only replaces a running kernel after validating the selected executable.
    @discardableResult
    func selectPython(path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard !expanded.isEmpty, FileManager.default.isExecutableFile(atPath: expanded) else { return false }
        interpreter = expanded
        preferences.set(expanded, forKey: Self.pythonPreferenceKey)
        restart(cwd: currentDirectory)
        return true
    }

    func start(cwd: URL? = nil) {
        guard process == nil else { return }
        currentDirectory = cwd ?? currentDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        sessionFailure = nil
        let resource = Bundle.main.url(forResource: "kernel_bridge", withExtension: "py")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/kernel_bridge.py")
        guard FileManager.default.isExecutableFile(atPath: interpreter) else {
            state = "Python not found: \(interpreter)"
            return
        }
        guard FileManager.default.fileExists(atPath: resource.path) else {
            state = "Kernel bridge not found"
            return
        }
        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        proc.executableURL = URL(fileURLWithPath: interpreter)
        proc.arguments = ["-u", resource.path]
        proc.currentDirectoryURL = currentDirectory
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.standardError
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYLAB_VARIABLE_MODE"] = variableMode.rawValue
        // Avoid inheriting environment settings from a different Python runtime.
        environment.removeValue(forKey: "PYTHONHOME")
        environment.removeValue(forKey: "PYTHONPATH")
        proc.environment = environment
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak proc] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { [weak self, weak proc] in
                guard let self, let proc, self.process === proc else { return }
                self.receive(data)
            }
        }
        proc.terminationHandler = { [weak self] exited in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.process === exited else { return }
                self.output?.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.input = nil
                self.output = nil
                self.buffer.clear()
                let reason = self.sessionFailure ?? "The Python kernel stopped unexpectedly. Restart it to continue."
                self.state = self.sessionFailure ?? "Kernel stopped"
                self.clearLiveState()
                self.finishExecutions(reason)
                self.failPendingActions(reason)
            }
        }
        process = proc
        input = stdin
        output = stdout
        buffer.clear()
        state = "Starting"
        do { try proc.run() }
        catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            process = nil
            input = nil
            output = nil
            state = "Kernel could not start: \(error.localizedDescription)"
            clearLiveState()
            finishExecutions(state)
            failPendingActions(state)
        }
    }

    func execute(code: String, id: String, source: KernelExecutionSource = .cell, originID: String? = nil, scopeID: String? = nil, scriptPath: String? = nil) {
        var message: [String: Any] = ["type": "execute", "code": code, "id": id, "source": source.rawValue]
        if let originID { message["origin_id"] = originID }
        if let scriptPath { message["script_path"] = scriptPath }
        if variableMode == .independent, let scopeID, !scopeID.isEmpty { message["scope_id"] = scopeID }
        executions.insert(id)
        executionActivities[id] = KernelExecutionActivity(id: id,
            originID: originID ?? (source == .cell ? id : nil), phase: .queued,
            queuedAt: Date(), startedAt: nil)
        if !send(message) {
            executions.remove(id)
            executionActivities.removeValue(forKey: id)
            onEvent?(KernelEvent(id: id, type: "error", text: "The code could not be sent to the Python kernel. Restart the kernel and try again.", image: nil, count: nil, wait: nil))
            onEvent?(KernelEvent(id: id, type: "finished", text: nil, image: nil, count: nil, wait: nil))
        }
    }

    /// The acknowledged working directory is also used on interpreter changes
    /// and restarts, so navigation cannot silently return to an older folder.
    func changeDirectory(to url: URL, completion: @escaping (String?) -> Void) {
        guard process?.isRunning == true else {
            // Browsing must remain available when Python cannot launch, for
            // example when a previously saved project folder has disappeared.
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
                completion("The selected folder is unavailable or is not a directory."); return
            }
            do {
                _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                currentDirectory = url
                completion(nil)
            } catch {
                completion("The selected folder could not be opened: " + error.localizedDescription)
            }
            return
        }
        let requestID = UUID().uuidString
        directoryCallbacks[requestID] = (url, completion)
        if !send(["type": "chdir", "path": url.path, "request_id": requestID]) {
            directoryCallbacks.removeValue(forKey: requestID)?.1("Could not send the folder change to the kernel.")
        }
    }

    func complete(code: String, cursorUTF16: Int, scopeID: String? = nil, completion: @escaping ([String], NSRange) -> Void) {
        let source = code as NSString
        guard cursorUTF16 >= 0, cursorUTF16 <= source.length else { return }
        let pythonCursor = source.substring(to: cursorUTF16).unicodeScalars.count
        let requestID = UUID().uuidString
        completionCallbacks[requestID] = { matches, start, end in
            let scalars = Array(code.unicodeScalars)
            guard start >= 0, end >= start, end <= scalars.count else { return }
            let prefix = String(String.UnicodeScalarView(scalars.prefix(start)))
            let selected = String(String.UnicodeScalarView(scalars[start..<end]))
            completion(matches, NSRange(location: (prefix as NSString).length, length: (selected as NSString).length))
        }
        if !send(scopedMessage(["type": "complete", "code": code, "cursor_pos": pythonCursor, "request_id": requestID], scopeID: scopeID)) {
            completionCallbacks.removeValue(forKey: requestID)?([], 0, 0)
        }
    }

    func refreshWorkspace() { send(["type": "workspace"]) }

    func inspectVariable(name: String, scopeID: String? = nil, completion: @escaping (VariableStatistics?, String?) -> Void) {
        guard state == "Ready", inputPrompt == nil, process?.isRunning == true else {
            completion(nil, "Wait until the Python kernel is ready before inspecting a variable."); return
        }
        let requestID = UUID().uuidString
        statisticsCallbacks[requestID] = completion
        if !send(scopedMessage(["type": "statistics", "name": name, "request_id": requestID], scopeID: scopeID)) {
            statisticsCallbacks.removeValue(forKey: requestID)?(nil, "Could not send the inspection request.")
        }
    }

    func renameVariable(name: String, to newName: String, scopeID: String? = nil, completion: @escaping (String?) -> Void) {
        manageVariable(name: name, action: "rename", newName: newName, scopeID: scopeID, completion: completion)
    }

    func deleteVariable(name: String, scopeID: String? = nil, completion: @escaping (String?) -> Void) {
        manageVariable(name: name, action: "delete", scopeID: scopeID, completion: completion)
    }

    private func manageVariable(name: String, action: String, newName: String? = nil, scopeID: String? = nil,
                                completion: @escaping (String?) -> Void) {
        guard state == "Ready", inputPrompt == nil, process?.isRunning == true else {
            completion("Wait until the Python kernel is ready before changing workspace variables."); return
        }
        let requestID = UUID().uuidString
        manageCallbacks[requestID] = completion
        var message: [String: Any] = ["type": action, "name": name, "request_id": requestID]
        if let newName { message["new_name"] = newName }
        if !send(scopedMessage(message, scopeID: scopeID)) {
            manageCallbacks.removeValue(forKey: requestID)?("Could not send the workspace request.")
        }
    }

    func loadTable(name: String, offset: Int = 0, scopeID: String? = nil) {
        let scope = normalizedScope(scopeID)
        if table?.name != name || table?.offset != offset || table?.scopeID != scope { table = nil }
        lastTable = (name, offset, scope)
        workspaceError = nil
        tableError = nil
        if !send(scopedMessage(["type": "table", "name": name, "offset": offset], scopeID: scopeID)) { tableError = "Could not load this variable from Python." }
    }

    func editTable(name: String, row: Int, column: Int, literal: String, scopeID: String? = nil) {
        workspaceError = nil
        tableError = nil
        if !send(scopedMessage(["type": "edit", "name": name, "row": row, "column": column, "literal": literal], scopeID: scopeID)) { tableError = "Could not edit this variable in Python." }
    }

    func pasteTable(name: String, row: Int, column: Int, values: [[String]], scopeID: String? = nil) {
        workspaceError = nil; tableError = nil
        if !send(scopedMessage(["type": "paste", "name": name, "row": row, "column": column, "values": values], scopeID: scopeID)) { tableError = "Could not paste into this variable in Python." }
    }

    func exportVariable(name: String, path: String, replaceExisting: Bool = false, scopeID: String? = nil,
                        completion: @escaping (String?) -> Void) {
        guard process?.isRunning == true else { completion("The Python kernel is not running."); return }
        let requestID = UUID().uuidString
        exportCallbacks[requestID] = completion
        if !send(scopedMessage(["type": "export_as", "name": name, "path": path,
                  "replace_existing": replaceExisting, "request_id": requestID], scopeID: scopeID)) {
            exportCallbacks.removeValue(forKey: requestID)?("Could not send the export request to the kernel.")
        }
    }

    func plotVariable(name: String, column: Int? = nil, options: [String: Any] = [:], scopeID: String? = nil, completion: @escaping (Data?, String?) -> Void) {
        guard process?.isRunning == true else { completion(nil, "The Python kernel is not running."); return }
        let requestID = UUID().uuidString
        plotCallbacks[requestID] = completion
        var message: [String: Any] = ["type": "plot", "name": name, "request_id": requestID, "options": options]
        let format = options["format"] as? String ?? "png"
        plotFormats[requestID] = format
        if let column { message["column"] = column }
        if !send(scopedMessage(message, scopeID: scopeID)) {
            plotFormats.removeValue(forKey: requestID)
            plotCallbacks.removeValue(forKey: requestID)?(nil, "Could not send the plot request to the kernel.")
        }
    }

    func replyToInput(_ value: String) {
        guard inputPrompt != nil else { return }
        if send(["type": "input_reply", "value": value]) {
            updateExecution(inputRequestID, phase: .running)
            inputPrompt = nil; inputRequestID = nil; inputIsPassword = false
        }
    }
    func interrupt() { send(["type": "interrupt"]) }

    func stop() {
        let proc = process
        if proc != nil { send(["type": "stop"]) }
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        process = nil
        input = nil
        output = nil
        buffer.clear()
        state = "Disconnected"
        clearLiveState()
        finishExecutions("Execution stopped because the Python kernel was stopped.")
        failPendingActions("Kernel stopped before the operation completed.")
        // Give the bridge an opportunity to shut down its Jupyter child cleanly.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if let proc, proc.isRunning { proc.terminate() }
        }
    }

    func restart(cwd: URL? = nil) {
        stop()
        start(cwd: cwd)
    }

    private func failPendingActions(_ message: String) {
        let exports = Array(exportCallbacks.values)
        let plots = Array(plotCallbacks.values)
        let statistics = Array(statisticsCallbacks.values)
        let management = Array(manageCallbacks.values)
        let completions = Array(completionCallbacks.values)
        let directories = Array(directoryCallbacks.values)
        exportCallbacks.removeAll()
        plotCallbacks.removeAll(); plotFormats.removeAll()
        completionCallbacks.removeAll()
        statisticsCallbacks.removeAll(); manageCallbacks.removeAll()
        directoryCallbacks.removeAll()
        exports.forEach { $0(message) }
        plots.forEach { $0(nil, message) }
        statistics.forEach { $0(nil, message) }
        management.forEach { $0(message) }
        completions.forEach { $0([], 0, 0) }
        directories.forEach { $0.1(message) }
    }

    private func clearLiveState() {
        executionActivities.removeAll()
        resetActivity()
        inputPrompt = nil; inputRequestID = nil; inputIsPassword = false
        workspace = []; table = nil; lastTable = nil
        workspaceError = nil; tableError = nil
    }

    private func resetActivity() {
        activityMonitor?.stop(); activityMonitor = nil
        activity = nil; activityHistory = []; activityUnavailable = false
    }
    private func monitorActivity(pid: Int32?) {
        resetActivity()
        guard let pid, pid > 0 else { activityUnavailable = true; return }
        let monitor = KernelActivityMonitor()
        monitor.onUpdate = { [weak self] snapshot, history, unavailable in
            self?.activity = snapshot; self?.activityHistory = history; self?.activityUnavailable = unavailable
        }
        activityMonitor = monitor
        monitor.start(pid: pid)
    }

    private func finishExecutions(_ message: String) {
        let unfinished = executions
        executions.removeAll()
        executionActivities.removeAll()
        for id in unfinished {
            onEvent?(KernelEvent(id: id, type: "error", text: message, image: nil, count: nil, wait: nil))
            onEvent?(KernelEvent(id: id, type: "finished", text: nil, image: nil, count: nil, wait: nil))
        }
    }

    private func updateExecution(_ id: String?, phase: KernelExecutionPhase) {
        guard let id, var activity = executionActivities[id] else { return }
        activity.mark(phase)
        executionActivities[id] = activity
    }

    @discardableResult
    private func send(_ object: [String: Any]) -> Bool {
        guard let handle = input?.fileHandleForWriting, process?.isRunning == true else { return false }
        // Foundation raises an Objective-C exception for some invalid JSON
        // values (notably NaN), which Swift's do/catch cannot intercept.
        guard JSONSerialization.isValidJSONObject(object) else {
            workspaceError = "The request contains a value that cannot be sent to Python. Use finite numbers for plot options."
            return false
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0a)
            try handle.write(contentsOf: data)
            return true
        } catch {
            state = "Kernel communication error: \(error.localizedDescription)"
            return false
        }
    }

    private func receive(_ data: Data) {
        let lines: [Data]
        do { lines = try buffer.append(data) }
        catch {
            let message = error.localizedDescription
            stop()
            sessionFailure = message
            state = message
            return
        }
        for line in lines {
            guard let raw = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = raw["type"] as? String else { continue }
            guard sessionFailure == nil || type == "fatal" else { continue }
            switch type {
            case "ready":
                state = "Ready"
                let rawPID = raw["kernel_pid"] as? Int
                monitorActivity(pid: rawPID.flatMap { $0 > 0 && $0 <= Int(Int32.max) ? Int32($0) : nil })
                refreshWorkspace()
            case "fatal":
                state = raw["text"] as? String ?? "Kernel failed"
                sessionFailure = state
                clearLiveState()
                finishExecutions(state)
                failPendingActions(state)
            case "directory_result":
                if let id = raw["request_id"] as? String,
                   let pending = directoryCallbacks.removeValue(forKey: id) {
                    currentDirectory = (raw["path"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? pending.0
                    pending.1(nil)
                }
            case "workspace":
                workspace = (raw["rows"] as? [[Any]] ?? []).compactMap { row in
                    guard row.count >= 5, let name = row[0] as? String, let kind = row[1] as? String,
                          let shape = row[2] as? String, let value = row[3] as? String,
                          let editable = row[4] as? Bool else { return nil }
                    let origin = row.count > 5 ? row[5] as? String : nil
                    let extensionName = row.count > 6 ? row[6] as? String : nil
                    let label = row.count > 7 ? row[7] as? String : nil
                    let plottable = row.count > 8 ? row[8] as? Bool ?? false : false
                    let scope = row.count > 9 ? row[9] as? String : nil
                    return WorkspaceVariable(name: name, type: kind, shape: shape, value: value, editable: editable,
                                             originID: origin, exportExtension: extensionName,
                                             exportLabel: label, plottable: plottable, scopeID: scope)
                }
            case "table":
                if let name = raw["name"] as? String, let columns = raw["columns"] as? [String],
                   let indices = raw["indices"] as? [String], let cells = raw["cells"] as? [[String]],
                   let total = raw["total"] as? Int, let width = raw["width"] as? Int,
                   let offset = raw["offset"] as? Int,
                   lastTable?.name == name, lastTable?.offset == (raw["requested_offset"] as? Int ?? offset),
                   lastTable?.scopeID == (raw["scope_id"] as? String) {
                    let scope = raw["scope_id"] as? String
                    table = WorkspaceTable(name: name, columns: columns, indices: indices, cells: cells, total: total, width: width, offset: offset, scopeID: scope)
                    lastTable = (name, offset, scope)
                }
            case "input_request":
                updateExecution(raw["id"] as? String, phase: .waitingForInput)
                inputPrompt = raw["prompt"] as? String ?? "Input: "
                inputIsPassword = raw["password"] as? Bool ?? false
                inputRequestID = raw["id"] as? String
            case "complete_result":
                if let id = raw["request_id"] as? String, let start = raw["cursor_start"] as? Int,
                   let end = raw["cursor_end"] as? Int {
                    completionCallbacks.removeValue(forKey: id)?(raw["matches"] as? [String] ?? [], start, end)
                }
            case "export_result":
                if let id = raw["request_id"] as? String { exportCallbacks.removeValue(forKey: id)?(nil) }
            case "plot_result":
                if let id = raw["request_id"] as? String {
                    let payload = raw["result"] as? [String: Any]
                    let format = plotFormats.removeValue(forKey: id) ?? "png"
                    let image = (payload?[format] as? String).flatMap { Data(base64Encoded: $0) }
                    plotCallbacks.removeValue(forKey: id)?(image, image == nil ? "The kernel returned an invalid plot." : nil)
                }
            case "statistics_result":
                if let id = raw["request_id"] as? String {
                    let decoded = (raw["result"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                        .flatMap { try? JSONDecoder().decode(VariableStatistics.self, from: $0) }
                    statisticsCallbacks.removeValue(forKey: id)?(decoded, decoded == nil ? "The kernel returned an invalid variable summary." : nil)
                }
            case "manage_result":
                if let id = raw["request_id"] as? String {
                    if let result = raw["result"] as? [String: Any], let old = result["name"] as? String, lastTable?.name == old,
                       lastTable?.scopeID == (raw["scope_id"] as? String) {
                        table = nil; lastTable = nil
                    }
                    manageCallbacks.removeValue(forKey: id)?(nil)
                    refreshWorkspace()
                }
            case "action_error":
                if let id = raw["request_id"] as? String {
                    let error = raw["text"] as? String ?? "The operation failed."
                    if raw["action"] as? String == "chdir" { directoryCallbacks.removeValue(forKey: id)?.1(error) }
                    else if raw["action"] as? String == "statistics" { statisticsCallbacks.removeValue(forKey: id)?(nil, error) }
                    else if ["rename", "delete"].contains(raw["action"] as? String ?? "") { manageCallbacks.removeValue(forKey: id)?(error) }
                    else if ["export", "export_as"].contains(raw["action"] as? String ?? "") { exportCallbacks.removeValue(forKey: id)?(error) }
                    else { plotFormats.removeValue(forKey: id); plotCallbacks.removeValue(forKey: id)?(nil, error) }
                }
            case "workspace_error":
                workspaceError = raw["text"] as? String ?? "Workspace request failed"
                if lastTable?.scopeID == (raw["scope_id"] as? String) { tableError = workspaceError }
            case "edit":
                if let pending = lastTable, pending.name == (raw["name"] as? String), pending.scopeID == (raw["scope_id"] as? String) {
                    loadTable(name: pending.name, offset: pending.offset, scopeID: pending.scopeID)
                }
                refreshWorkspace()
            default:
                let event = KernelEvent(id: raw["id"] as? String, type: type, text: raw["text"] as? String,
                                        image: raw["image"] as? String, count: raw["count"] as? Int,
                                        wait: raw["wait"] as? Bool,
                                        displayID: raw["display_id"] as? String,
                                        isDisplayUpdate: raw["update"] as? Bool ?? false,
                                        displayData: raw["data"] as? [String: Any],
                                        displayMetadata: raw["metadata"] as? [String: Any],
                                        streamName: raw["name"] as? String,
                                        errorName: raw["ename"] as? String, errorValue: raw["evalue"] as? String,
                                        traceback: raw["traceback"] as? [String])
                if type == "status" {
                    if event.text == "busy" { updateExecution(event.id, phase: .running) }
                    state = event.text == "busy" ? "Busy" : "Ready"
                }
                if type == "execute_input" {
                    updateExecution(event.id, phase: .running)
                    state = "Busy"
                }
                if type == "finished" {
                    executionActivities.removeValue(forKey: event.id ?? "")
                    executions.remove(event.id ?? "")
                    state = "Ready"
                    if event.id == inputRequestID { inputPrompt = nil; inputRequestID = nil; inputIsPassword = false }
                    refreshWorkspace()
                }
                onEvent?(event)
            }
        }
    }
}
