import Foundation

@main struct KernelLifecycleTests {
    @MainActor static func main() throws {
        var frames = KernelMessageBuffer(maximumMessageBytes: 16)
        let partial = try frames.append(Data("{\"type\":\"ok\"".utf8)); precondition(partial.isEmpty)
        let completedFrames = try frames.append(Data("}\n{}\n".utf8)); precondition(completedFrames.count == 2)
        do { _ = try frames.append(Data(repeating: 65, count: 17)); preconditionFailure("Unfinished oversized frame was accepted") }
        catch KernelMessageBuffer.Failure.messageTooLarge { }
        do { _ = try frames.append(Data((String(repeating: "B", count: 17) + "\n").utf8)); preconditionFailure("Complete oversized frame was accepted") }
        catch KernelMessageBuffer.Failure.messageTooLarge { }
        let recoveredFrames = try frames.append(Data("{}\n".utf8)); precondition(recoveredFrames.count == 1)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-kernel-lifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let executable = temporary.appendingPathComponent("fake-python")
        let script = """
        #!/opt/miniconda3/bin/python3.12
        import json, os, sys
        def emit(**value): print(json.dumps(value), flush=True)
        emit(type='ready')
        for line in sys.stdin:
            command=json.loads(line); kind=command['type']
            if kind=='stop': break
            if kind=='workspace': emit(type='workspace',rows=[['probe','int','1 × 1','42',False]])
            if kind=='execute':
                code=command['code']; ident=command['id']
                if code=='crash': os._exit(2)
                if code=='fatal':
                    emit(type='fatal',text='Preserved diagnostic')
                    sys.exit(1)
                if code=='wait':
                    emit(type='status',id=ident,text='busy')
                    emit(type='input_request',id=ident,prompt='Waiting: ',password=False)
                if code=='pwd':
                    emit(type='stream',id=ident,text=os.getcwd())
                    emit(type='finished',id=ident)
            if kind=='chdir':
                try:
                    os.chdir(command['path'])
                    emit(type='directory_result',request_id=command['request_id'],path=os.getcwd())
                except Exception as error:
                    emit(type='action_error',request_id=command['request_id'],action='chdir',text=str(error))
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let suite = "org.pylab.test.kernel-lifecycle." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let kernel = KernelController(python: executable.path, preferences: preferences)
        defer { kernel.stop() }
        var events: [KernelEvent] = []
        kernel.onEvent = { events.append($0) }
        func wait(_ condition: () -> Bool, _ reason: String) {
            let deadline = Date(timeIntervalSinceNow: 8)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
            precondition(condition(), reason + " (state: " + kernel.state + ")")
        }
        kernel.start(cwd: temporary)
        wait({ kernel.state == "Ready" && !kernel.workspace.isEmpty }, "Initial launch did not become ready")
        var invalidOptionError: String?
        kernel.plotVariable(name: "probe", options: ["minimum": Double.nan]) { _, error in invalidOptionError = error }
        precondition(invalidOptionError != nil && kernel.state == "Ready", "Non-finite JSON request was not safely rejected")
        let next = temporary.appendingPathComponent("new-project")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: false)
        var changeDone = false
        kernel.changeDirectory(to: next) { error in precondition(error == nil); changeDone = true }
        wait({ changeDone }, "Directory success was not acknowledged")
        kernel.restart()
        wait({ kernel.state == "Ready" }, "Restart did not become ready")
        kernel.execute(code: "pwd", id: "directory")
        wait({ events.contains { $0.id == "directory" && $0.type == "finished" } }, "Directory check did not finish")
        precondition(events.contains { $0.id == "directory" && $0.text?.replacingOccurrences(of: "/private/var/", with: "/var/") == next.path.replacingOccurrences(of: "/private/var/", with: "/var/") }, "Restart lost the acknowledged directory")
        var failure: String?
        kernel.changeDirectory(to: temporary.appendingPathComponent("absent")) { failure = $0 }
        wait({ failure != nil }, "Directory failure was not returned")
        kernel.restart()
        wait({ kernel.state == "Ready" }, "Second restart did not become ready")
        kernel.execute(code: "pwd", id: "after-failure")
        wait({ events.contains { $0.id == "after-failure" && $0.type == "finished" } }, "Directory recheck did not finish")
        precondition(events.contains { $0.id == "after-failure" && $0.text?.replacingOccurrences(of: "/private/var/", with: "/var/") == next.path.replacingOccurrences(of: "/private/var/", with: "/var/") }, "A rejected directory changed the restart path")
        var exportError: String?, plotError: String?, statisticsError: String?, manageError: String?
        var completed = false
        kernel.exportVariable(name: "probe", path: temporary.appendingPathComponent("probe.txt").path) { exportError = $0 }
        kernel.plotVariable(name: "probe") { _, error in plotError = error }
        kernel.inspectVariable(name: "probe") { _, error in statisticsError = error }
        kernel.deleteVariable(name: "probe") { manageError = $0 }
        kernel.complete(code: "probe", cursorUTF16: 5) { matches, _ in precondition(matches.isEmpty); completed = true }
        kernel.execute(code: "wait", id: "pending")
        wait({ kernel.inputPrompt != nil }, "Input request was not shown")
        kernel.execute(code: "crash", id: "crash")
        wait({ kernel.state == "Kernel stopped" }, "Unexpected process death was not detected")
        precondition(kernel.workspace.isEmpty && kernel.table == nil && kernel.inputPrompt == nil && kernel.inputRequestID == nil)
        precondition(exportError != nil && plotError != nil && statisticsError != nil && manageError != nil && completed, "Pending operations were stranded")
        for id in ["pending", "crash"] {
            precondition(events.filter { $0.id == id && $0.type == "finished" }.count == 1, "An interrupted execution did not finish exactly once")
            precondition(events.contains { $0.id == id && $0.type == "error" })
        }
        kernel.start()
        wait({ kernel.state == "Ready" }, "Recovery launch did not become ready")
        kernel.execute(code: "fatal", id: "fatal")
        wait({ kernel.state == "Preserved diagnostic" }, "Fatal diagnostic was not surfaced")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        precondition(kernel.state == "Preserved diagnostic", "Termination replaced the useful diagnostic")
        precondition(events.filter { $0.id == "fatal" && $0.type == "finished" }.count == 1)
        kernel.stop()
        precondition(kernel.state == "Disconnected")
        let offline = temporary.appendingPathComponent("offline-project")
        try FileManager.default.createDirectory(at: offline, withIntermediateDirectories: false)
        var offlineSelected = false
        kernel.changeDirectory(to: offline) { error in precondition(error == nil); offlineSelected = true }
        precondition(offlineSelected && kernel.state == "Disconnected", "Offline browsing unexpectedly started the kernel")
        var offlineError: String?
        kernel.changeDirectory(to: temporary.appendingPathComponent("offline-missing")) { offlineError = $0 }
        precondition(offlineError != nil && kernel.state == "Disconnected", "Offline invalid folder was accepted")
        kernel.changeDirectory(to: executable) { offlineError = $0 }
        precondition(offlineError != nil, "A file was accepted as an offline folder")
        kernel.restart()
        wait({ kernel.state == "Ready" }, "Restart after offline folder selection failed")
        kernel.execute(code: "pwd", id: "offline-directory")
        wait({ events.contains { $0.id == "offline-directory" && $0.type == "finished" } }, "Offline directory check did not finish")
        precondition(events.contains { $0.id == "offline-directory" && $0.text?.replacingOccurrences(of: "/private/var/", with: "/var/") == offline.path.replacingOccurrences(of: "/private/var/", with: "/var/") }, "Offline folder selection was not retained across restart")
        kernel.stop()
        kernel.execute(code: "pwd", id: "not-running")
        precondition(events.contains { $0.id == "not-running" && $0.type == "error" })
        precondition(events.filter { $0.id == "not-running" && $0.type == "finished" }.count == 1)
        print("PASS: offline folder navigation/recovery and acknowledged folder survive restart, rejected folder retained, crashed/fatal kernels clear live state and complete pending actions/executions, disconnected sends finish safely")
    }
}
