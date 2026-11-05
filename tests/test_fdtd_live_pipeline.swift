import Foundation
import AppKit
import CryptoKit
import Darwin

/// Uses an optional argument, PYLAB_FDTD_ROOT, or sibling fdtd-python checkout.
/// Runs a tiny periodic grid in an owned kernel, never an experiment runner.
@main struct FDTDLivePipelineChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let sibling = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fdtd-python").path
        let path = CommandLine.arguments.dropFirst().first
            ?? ProcessInfo.processInfo.environment["PYLAB_FDTD_ROOT"] ?? sibling
        guard FileManager.default.fileExists(atPath: path + "/fdtd/three_d_live.py") else {
            print("SKIP: clone fdtd-python beside this checkout, set PYLAB_FDTD_ROOT, or pass its folder as the first argument")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-fdtd-pipeline-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let keys = ["IPYTHONDIR", "JUPYTER_CONFIG_DIR", "JUPYTER_DATA_DIR", "JUPYTER_RUNTIME_DIR", "MPLCONFIGDIR", "PYTHONDONTWRITEBYTECODE"]
        let old = Dictionary(uniqueKeysWithValues: keys.map { ($0, ProcessInfo.processInfo.environment[$0]) })
        for key in keys {
            if key == "PYTHONDONTWRITEBYTECODE" { setenv(key, "1", 1) }
            else {
                let location = folder.appendingPathComponent(key)
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                setenv(key, location.path, 1)
            }
        }
        defer { for key in keys { if let value = old[key] ?? nil { setenv(key, value, 1) } else { unsetenv(key) } } }
        let suite = "org.pylab.tests.fdtd-pipeline." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let kernel = KernelController(python: "/opt/miniconda3/bin/python3.12", preferences: preferences)
        defer { kernel.stop() }
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        let projectLiteral = String(data: try encoder.encode(path), encoding: .utf8)!
        let code = """
        import sys
        sys.path.insert(0, \(projectLiteral))
        import numpy as np
        from fdtd.three_d import Config3D, simulate
        from fdtd.three_d_live import LiveFieldPreview
        config = Config3D('live-pipeline', 'Live FDTD integration test', '',
            nx=14, ny=16, nz=12, steps=6, source_x=7, source_y=7, source_z=6,
            geometry='free', injection='point', source='sine', boundary_x='periodic',
            boundary_y='periodic', boundary_z='periodic', backend='numpy',
            energy_stride=2, snapshots=(2, 6))
        baseline = simulate(config)
        with LiveFieldPreview(config) as preview:
            observed = simulate(config, on_frame=preview, preview_stride=2, preview_interval=0)
        assert all(np.array_equal(baseline[key], observed[key]) for key in baseline)
        """
        let store = NotebookStore()
        let cellID = store.cells[0].id
        store.cells[0].source = code
        var gallery: [VariablePlot] = []
        var finished = false
        var errors: [String] = []
        var frameCount = 0
        var hashes = Set<Data>()
        var firstPNG: Data?
        var latestPNG: Data?
        var displayID: String?
        kernel.onEvent = { event in
            guard event.id == "fdtd" else { return }
            if event.type == "finished" { finished = true; return }
            if event.type == "error", let text = event.text { errors.append(text) }
            if event.type == "execute_input", let count = event.count { store.setExecutionCount(cellID, count: count) }
            guard let image = event.image, let bytes = Data(base64Encoded: image),
                  let identity = event.displayID, let data = event.displayData else { return }
            precondition(!finished, "The live FDTD frame arrived after execution finished")
            let output: [String: Any] = ["output_type": "display_data", "data": data, "metadata": event.displayMetadata ?? [:]]
            if event.isDisplayUpdate {
                precondition(identity == displayID && store.updateDisplayOutput(displayID: identity, output: output) == 1)
            } else {
                precondition(gallery.isEmpty, "FDTD created a new figure instead of reusing its display handle")
                let live = store.appendDisplayOutput(cellID, output: output, displayID: identity)!
                gallery.append(VariablePlot(name: "FDTD", data: bytes, liveFigure: live))
                displayID = identity
            }
            frameCount += 1
            hashes.insert(Data(SHA256.hash(data: bytes)))
            firstPNG = firstPNG ?? bytes; latestPNG = bytes
            precondition(store.cells[0].outputs.count == 1 && gallery.count == 1)
            precondition(gallery[0].liveFigure === store.displayFigures[identity])
            precondition(gallery[0].liveFigure?.data == bytes)
        }
        func wait(_ condition: () -> Bool, _ message: String, timeout: TimeInterval = 30) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
            precondition(condition(), message + ": " + kernel.state + "\n" + errors.joined(separator: "\n"))
        }
        kernel.start(cwd: folder)
        wait({ kernel.state == "Ready" }, "Kernel did not start", timeout: 40)
        kernel.execute(code: code, id: "fdtd")
        wait({ frameCount >= 2 }, "No intermediate FDTD frames arrived")
        precondition(!finished, "FDTD frames were buffered until completion")
        wait({ finished }, "FDTD test did not finish")
        precondition(errors.isEmpty, errors.joined(separator: "\n"))
        precondition(frameCount == 4 && hashes.count == 4 && firstPNG != latestPNG)
        precondition(store.cells[0].outputs.count == 1 && gallery.count == 1 && kernel.executionActivities.isEmpty)
        precondition(store.cells[0].executionCount == 1)
        let finalBundle = store.cells[0].outputs[0]["data"] as! [String: Any]
        precondition((finalBundle["text/plain"] as? String)?.contains("step 6/6") == true)
        precondition(Data(base64Encoded: finalBundle["image/png"] as! String) == latestPNG)
        let notebookURL = folder.appendingPathComponent("Live FDTD.ipynb")
        try store.save(to: notebookURL)
        let reopened = NotebookStore()
        try reopened.load(from: notebookURL)
        precondition(reopened.cells[0].source == code && reopened.cells[0].outputs.count == 1)
        let reopenedBundle = reopened.cells[0].outputs[0]["data"] as! [String: Any]
        precondition(Data(base64Encoded: NotebookStore.text(reopenedBundle["image/png"])) == latestPNG)
        precondition(reopened.displayOutputTargets.isEmpty && reopened.displayFigures.isEmpty)
        precondition(reopened.cells[0].executionCount == 1)
        try firstPNG!.write(to: URL(fileURLWithPath: "/private/tmp/pylab-fdtd-live-first.png"))
        try latestPNG!.write(to: URL(fileURLWithPath: "/private/tmp/pylab-fdtd-live-last.png"))
        print("PASS: actual tiny FDTD → live PNGs → Swift kernel → one notebook output/shared gallery figure; changing frames before completion, unchanged numerical results, final PNG save/reopen, transient ID cleanup")
    }
}
