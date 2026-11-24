import Foundation
import Darwin

@main struct LiveDisplayEventChecks {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-live-display-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let keys = ["IPYTHONDIR", "JUPYTER_CONFIG_DIR", "JUPYTER_DATA_DIR", "JUPYTER_RUNTIME_DIR", "MPLCONFIGDIR", "PYTHONDONTWRITEBYTECODE"]
        let old = Dictionary(uniqueKeysWithValues: keys.map { ($0, ProcessInfo.processInfo.environment[$0]) })
        for key in keys {
            if key == "PYTHONDONTWRITEBYTECODE" { setenv(key, "1", 1) }
            else {
                let path = folder.appendingPathComponent(key)
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                setenv(key, path.path, 1)
            }
        }
        defer { for key in keys { if let value = old[key] ?? nil { setenv(key, value, 1) } else { unsetenv(key) } } }
        let suite = "org.pylab.tests.live-display." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let kernel = KernelController(python: "/opt/miniconda3/bin/python3.12", preferences: preferences)
        defer { kernel.stop() }
        var events: [KernelEvent] = []
        var framesBeforeFinish = 0
        kernel.onEvent = { event in
            if event.id == "movie", event.type == "image" {
                precondition(!events.contains { $0.id == "movie" && $0.type == "finished" })
                framesBeforeFinish += 1
            }
            events.append(event)
        }
        func wait(_ condition: () -> Bool, _ message: String, timeout: TimeInterval = 15) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
            precondition(condition(), message + ": " + kernel.state)
        }
        func finished(_ id: String) -> Bool { events.contains { $0.id == id && $0.type == "finished" } }
        func noError(_ id: String) {
            precondition(!events.contains { $0.id == id && $0.type == "error" }, events.filter { $0.id == id }.compactMap(\.text).joined(separator: "\n"))
        }
        kernel.start(cwd: folder)
        wait({ kernel.state == "Ready" }, "Kernel did not start", timeout: 40)
        kernel.execute(code: """
        import time, threading
        import matplotlib.pyplot as plt
        from IPython.display import display, update_display, clear_output
        fig, ax = plt.subplots(figsize=(3, 2))
        line, = ax.plot([0, 1], [0, 0])
        ax.set_ylim(-1, 4)
        live = display(fig, display_id='pylab-live-check', metadata={'image/png': {'width': 300}})
        for frame in range(1, 4):
            line.set_ydata([0, frame])
            live.update(fig)
            time.sleep(.15)
        plt.close(fig)
        """, id: "movie")
        wait({ framesBeforeFinish >= 2 }, "No intermediate plot frames arrived")
        precondition(!finished("movie"), "Frames only became available after completion")
        wait({ finished("movie") }, "Animation did not finish")
        noError("movie")
        let frames = events.filter { $0.id == "movie" && $0.type == "image" }
        precondition(frames.count == 4 && frames.allSatisfy { $0.displayID == "pylab-live-check" })
        precondition(!frames[0].isDisplayUpdate && frames.dropFirst().allSatisfy(\.isDisplayUpdate))
        precondition(Set(frames.compactMap(\.image)).count == 4, "Plot frames did not change")
        precondition(frames[0].displayData?["image/png"] as? String == frames[0].image)
        precondition((frames[0].displayMetadata?["image/png"] as? [String: Any])?["width"] as? Int == 300)
        kernel.execute(code: """
        live.update('now text')
        update_display({'image/svg+xml': '<svg xmlns="http://www.w3.org/2000/svg"/>'}, raw=True,
                       display_id='pylab-live-check', metadata={'svg-note': 'retained'})
        update_display({}, raw=True, display_id='pylab-live-check')
        """, id: "later-cell")
        wait({ finished("later-cell") }, "Later-cell update did not finish")
        noError("later-cell")
        let later = events.filter { $0.id == "later-cell" && $0.isDisplayUpdate }
        precondition(later.count == 3 && later.allSatisfy { $0.displayID == "pylab-live-check" })
        precondition(later[0].image == nil && later[0].displayData?["image/png"] == nil && later[0].displayData?["text/plain"] as? String == "'now text'")
        precondition(later[1].type == "display" && later[1].displayData?["image/svg+xml"] != nil && later[1].displayData?["image/png"] == nil)
        precondition(later[1].displayMetadata?["svg-note"] as? String == "retained")
        precondition(later[2].type == "display" && later[2].displayData?.isEmpty == true)
        kernel.execute(code: """
        def delayed_update():
            time.sleep(.4)
            live.update('background frame')
        thread = threading.Thread(target=delayed_update, daemon=True)
        thread.start()
        """, id: "background")
        wait({ finished("background") }, "Background scheduling did not finish")
        wait({ events.contains { $0.id == nil && $0.isDisplayUpdate && $0.displayID == "pylab-live-check" } }, "Late background update was lost")
        kernel.execute(code: "plt.figure(figsize=(2, 1)); plt.plot([1, 2]); plt.show()", id: "ordinary")
        wait({ finished("ordinary") }, "Normal figure did not finish")
        noError("ordinary")
        precondition(events.contains { $0.id == "ordinary" && $0.type == "image" && $0.displayID == nil && !$0.isDisplayUpdate })
        kernel.execute(code: "2 + 2", id: "expression")
        wait({ finished("expression") }, "Expression result did not finish")
        noError("expression")
        precondition(events.contains { $0.id == "expression" && $0.type == "result" && $0.text == "4" && $0.count != nil && !$0.isDisplayUpdate })
        kernel.execute(code: """
        import sys
        print('simulation started', flush=True)
        print('mesh warning', file=sys.stderr, flush=True)
        live.update('before error')
        raise RuntimeError('live fixture')
        """, id: "error")
        wait({ finished("error") }, "Error left execution pending")
        let diagnosticEvents = events.filter { $0.id == "error" }
        precondition(diagnosticEvents.contains { $0.isDisplayUpdate })
        let outputs = diagnosticEvents.compactMap(\.notebookTextOutput)
        precondition(outputs.contains { $0["name"] as? String == "stdout" && $0["text"] as? String == "simulation started\n" })
        precondition(outputs.contains { $0["name"] as? String == "stderr" && $0["text"] as? String == "mesh warning\n" })
        let exception = outputs.first { $0["output_type"] as? String == "error" }
        precondition(exception?["ename"] as? String == "RuntimeError" && exception?["evalue"] as? String == "live fixture")
        precondition((exception?["traceback"] as? [String])?.last?.contains("live fixture") == true)
        let bridgeFailure = KernelEvent(id: nil, type: "error", text: "Bridge stopped", image: nil, count: nil, wait: nil)
        precondition(bridgeFailure.notebookTextOutput?["name"] as? String == "stderr")
        kernel.execute(code: "live.update('before interrupt'); time.sleep(30)", id: "interrupt")
        wait({ events.contains { $0.id == "interrupt" && $0.isDisplayUpdate } }, "Interrupted run produced no frame")
        kernel.interrupt()
        wait({ finished("interrupt") }, "Interrupt left execution pending")
        precondition(kernel.executionActivities.isEmpty)
        let malformed = KernelEvent(id: nil, type: "display", text: nil, image: nil, count: nil, wait: nil,
            displayID: String(repeating: "a", count: 4097), isDisplayUpdate: true, displayData: [:])
        precondition(malformed.displayID == nil && malformed.isDisplayUpdate && malformed.displayData?.isEmpty == true)
        print("PASS: live frames before finish, stable display IDs, cross-cell/text/SVG/empty updates, metadata, late background updates, normal plots, error and interrupt cleanup")
    }
}
