import Foundation

@main struct LiveKernelActivityCheck {
    @MainActor static func main() throws {
        let suite = "org.pylab.activity." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let kernel = KernelController(python: "/opt/miniconda3/bin/python3.12", preferences: defaults)
        defer { kernel.stop() }
        var finished = false, output = ""
        kernel.onEvent = { event in
            if event.id == "long-activity" {
                if let text = event.text { output += text }
                if event.type == "finished" { finished = true }
            }
        }
        func wait(_ condition: () -> Bool, timeout: Double, _ reason: String) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
            precondition(condition(), reason + ": " + kernel.state)
        }
        kernel.start(cwd: URL(fileURLWithPath: "/private/tmp"))
        wait({ kernel.state == "Ready" }, timeout: 40, "Kernel did not start")
        precondition(kernel.activity != nil && (kernel.activity?.residentBytes ?? 0) > 0 && !kernel.activityUnavailable)
        let first = kernel.activityHistory.last?.timestamp
        kernel.execute(code: "import time; time.sleep(4); print('metrics alive')", id: "long-activity")
        wait({ kernel.state == "Busy" }, timeout: 5, "Kernel never became busy")
        wait({ kernel.activityHistory.last?.timestamp != first && kernel.activity?.cpuPercent != nil }, timeout: 3.5, "Native readings did not advance while kernel busy")
        precondition(kernel.state == "Busy" && !finished, "Activity sampling waited for Python code to finish")
        wait({ finished }, timeout: 10, "Long execution did not finish")
        precondition(output.contains("metrics alive"))
        kernel.stop()
        precondition(kernel.activity == nil && kernel.activityHistory.isEmpty && !kernel.activityUnavailable)
        print("PASS: live IPython CPU/RAM samples advance during long execution without queued kernel requests; stop clears metrics")
    }
}
