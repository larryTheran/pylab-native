import Foundation
import Darwin

@main struct ExecutionActivityChecks {
    @MainActor static func main() throws {
        let queued = Date(timeIntervalSince1970: 100)
        let began = Date(timeIntervalSince1970: 105)
        var value = KernelExecutionActivity(id: "one", originID: "book|A", phase: .queued, queuedAt: queued, startedAt: nil)
        precondition(value.startedAt == nil)
        value.mark(.running, at: began)
        value.mark(.waitingForInput, at: began.addingTimeInterval(2))
        value.mark(.running, at: began.addingTimeInterval(5))
        precondition(value.startedAt == began && value.queuedAt == queued)
        let waiting = KernelExecutionActivity(id: "waiting", originID: "book|A", phase: .waitingForInput, queuedAt: queued, startedAt: began)
        let other = KernelExecutionActivity(id: "other", originID: "book|B", phase: .queued, queuedAt: queued.addingTimeInterval(-5), startedAt: nil)
        precondition(KernelExecutionActivity.representative(in: [other, value, waiting]) == waiting)
        precondition(KernelExecutionActivity.representative(forOriginID: "book|A", in: [other, value]) == value)
        precondition(KernelExecutionActivity.representative(forOriginID: "missing", in: [other, value]) == nil)
        let tie = KernelExecutionActivity(id: "two", originID: "book|A", phase: .running, queuedAt: queued, startedAt: began)
        precondition(KernelExecutionActivity.representative(in: [tie, value])?.id == "one")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-execution-activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let variables = ["IPYTHONDIR", "JUPYTER_CONFIG_DIR", "JUPYTER_DATA_DIR", "JUPYTER_RUNTIME_DIR", "MPLCONFIGDIR", "PYTHONDONTWRITEBYTECODE"]
        let original = Dictionary(uniqueKeysWithValues: variables.map { ($0, ProcessInfo.processInfo.environment[$0]) })
        for key in variables {
            if key == "PYTHONDONTWRITEBYTECODE" { setenv(key, "1", 1) }
            else {
                let directory = folder.appendingPathComponent(key)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                setenv(key, directory.path, 1)
            }
        }
        defer { for key in variables { if let saved = original[key] ?? nil { setenv(key, saved, 1) } else { unsetenv(key) } } }
        let suite = "org.pylab.test.execution-activity." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let kernel = KernelController(python: "/opt/miniconda3/bin/python3.12", preferences: preferences)
        defer { kernel.stop() }
        var events: [KernelEvent] = []
        var errorWhileRunning = false
        kernel.onEvent = { event in
            if let id = event.id {
                if (event.type == "status" && event.text == "busy") || event.type == "execute_input" {
                    precondition(kernel.executionActivities[id]?.phase == .running, "Activity not updated before event callback")
                    precondition(kernel.executionActivities[id]?.startedAt != nil)
                }
                if event.type == "error" && id == "error" { errorWhileRunning = kernel.executionActivities[id]?.phase == .running }
                if event.type == "finished" { precondition(kernel.executionActivities[id] == nil, "Finished activity remained visible") }
            }
            events.append(event)
        }
        func wait(_ predicate: () -> Bool, _ message: String, timeout: TimeInterval = 10) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while !predicate() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
            precondition(predicate(), message + ": " + kernel.state)
        }
        func finished(_ id: String) -> Bool { events.contains { $0.id == id && $0.type == "finished" } }
        kernel.start(cwd: folder)
        wait({ kernel.state == "Ready" }, "Kernel did not start", timeout: 40)
        kernel.execute(code: "import time; time.sleep(0.7); print('first')", id: "first", originID: "book|A")
        kernel.execute(code: "import time; time.sleep(0.6); print('second')", id: "second", originID: "book|B")
        precondition(kernel.executionActivities["first"]?.phase == .queued && kernel.executionActivities["first"]?.startedAt == nil)
        precondition(kernel.executionActivities["second"]?.phase == .queued && kernel.executionActivities["second"]?.startedAt == nil)
        wait({ kernel.executionActivities["first"]?.phase == .running }, "First request never ran")
        precondition(kernel.executionActivities["second"]?.phase == .queued, "Waiting request was shown as running")
        precondition(kernel.executionActivities["first"]?.originID == "book|A")
        wait({ finished("first") && kernel.executionActivities["second"]?.phase == .running }, "Queue did not advance")
        let second = kernel.executionActivities["second"]!
        precondition((second.startedAt?.timeIntervalSince(second.queuedAt) ?? 0) > 0.35, "Queued time incorrectly counted as active start")
        wait({ finished("second") }, "Second request did not finish")
        precondition(kernel.executionActivities.isEmpty)

        kernel.execute(code: "answer = input('Activity input: '); print(answer)", id: "input", source: .console)
        wait({ kernel.executionActivities["input"]?.phase == .waitingForInput && kernel.inputPrompt != nil }, "Input wait was not reported")
        precondition(kernel.executionActivities["input"]?.originID == nil)
        let inputStart = kernel.executionActivities["input"]?.startedAt
        kernel.replyToInput("fixture")
        precondition(kernel.executionActivities["input"]?.phase == .running && kernel.executionActivities["input"]?.startedAt == inputStart)
        wait({ finished("input") }, "Input request did not complete")

        kernel.execute(code: "raise RuntimeError('activity fixture')", id: "error")
        wait({ finished("error") }, "Error did not finish")
        precondition(errorWhileRunning && kernel.executionActivities.isEmpty)
        kernel.execute(code: "import time; time.sleep(30)", id: "interrupt")
        wait({ kernel.executionActivities["interrupt"]?.phase == .running }, "Interrupted request never started")
        kernel.interrupt()
        wait({ finished("interrupt") }, "Interrupt left activity stuck")
        precondition(kernel.executionActivities.isEmpty)

        kernel.execute(code: "import time; time.sleep(30)", id: "stopping")
        kernel.execute(code: "print('must remain queued')", id: "queued-stop")
        wait({ kernel.executionActivities["stopping"]?.phase == .running }, "Stop fixture never started")
        precondition(kernel.executionActivities["queued-stop"]?.phase == .queued)
        kernel.stop()
        precondition(kernel.executionActivities.isEmpty && finished("stopping") && finished("queued-stop"))
        kernel.restart(cwd: folder)
        wait({ kernel.state == "Ready" }, "Restart failed", timeout: 40)
        precondition(kernel.executionActivities.isEmpty)
        kernel.execute(code: "import os; os._exit(7)", id: "crash")
        wait({ finished("crash") }, "Kernel death left activity stuck")
        precondition(kernel.executionActivities.isEmpty)
        kernel.stop()
        kernel.execute(code: "print('disconnected')", id: "disconnected")
        precondition(kernel.executionActivities.isEmpty && finished("disconnected"))
        print("PASS: accurate queued/running/input phases and start time, queue advance, error/interrupt/stop/crash cleanup, disconnected sends, origin grouping and callback ordering")
    }
}
