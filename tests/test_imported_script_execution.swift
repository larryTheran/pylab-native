import Foundation
import Darwin

/// Exercises the actual Swift controller and Jupyter bridge with imported cell
/// metadata, rather than invoking the Python helper directly.
@main struct ImportedScriptExecutionChecks {
    @MainActor static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-imported-script-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Keep kernel history, plotting configuration, and bytecode out of the
        // user's Python configuration and source folders.
        setenv("IPYTHONDIR", temporary.appendingPathComponent("ipython").path, 1)
        setenv("MPLCONFIGDIR", temporary.appendingPathComponent("matplotlib").path, 1)
        setenv("JUPYTER_RUNTIME_DIR", temporary.appendingPathComponent("runtime").path, 1)
        setenv("JUPYTER_CONFIG_DIR", temporary.appendingPathComponent("jupyter-config").path, 1)
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
        let scripts = temporary.appendingPathComponent("Project 'quote 🚀", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let original = scripts.appendingPathComponent("analysis.py")
        let source = """
        import argparse, sys
        from pathlib import Path
        import sibling_probe
        parser = argparse.ArgumentParser()
        parser.add_argument('--scale', type=int, default=2)
        parsed = parser.parse_args()
        assert Path(__file__).name == 'analysis.py'
        assert sys.argv == [str(Path(__file__))]
        assert __name__ == '__main__'
        imported_value = 40 + parsed.scale
        sibling_value = sibling_probe.value
        print('IMPORTED_OK', imported_value, sibling_value)
        """
        try source.write(to: original, atomically: true, encoding: .utf8)
        try "value = 7\n".write(to: scripts.appendingPathComponent("sibling_probe.py"), atomically: true, encoding: .utf8)
        let imported = try PythonScriptImport.read(original)
        let editedSource = imported.source + "\nedited_in_notebook = 43\n"
        let cell = NotebookCell(name: imported.cellName, source: editedSource,
            original: ["metadata": [ImportedScriptContext.metadataKey: imported.sourcePath]])
        // Round-trip the actual cell JSON before executing, like save/reopen.
        let data = try JSONSerialization.data(withJSONObject: cell.json)
        let restoredJSON = try JSONSerialization.jsonObject(with: data) as! [String:Any]
        let restored = NotebookCell(name: cell.name, source: cell.source, original: restoredJSON)
        guard let scriptPath = ImportedScriptContext.path(for: restored) else { preconditionFailure("Imported source metadata was lost") }
        precondition(scriptPath == imported.sourcePath)
        for mode in [VariableSharingMode.shared, .independent] {
            let suite = "org.pylab.tests.imported-script." + UUID().uuidString
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let kernel = KernelController(python: "/opt/miniconda3/bin/python3.12", preferences: preferences, variableMode: mode)
            defer { kernel.stop() }
            var events: [KernelEvent] = []
            kernel.onEvent = { events.append($0) }
            func wait(_ condition: () -> Bool, _ reason: String) {
                let deadline = Date(timeIntervalSinceNow: 25)
                while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
                precondition(condition(), reason + " (mode: " + mode.rawValue + ", state: " + kernel.state + ")")
            }
            func finished(_ id: String) -> Bool { events.contains { $0.id == id && $0.type == "finished" } }
            func noError(_ id: String) {
                let errors = events.filter { $0.id == id && $0.type == "error" }.compactMap(\.text)
                precondition(errors.isEmpty, errors.joined(separator: "\n"))
            }
            let scope = "scope-A"
            kernel.start(cwd: temporary)
            wait({ kernel.state == "Ready" }, "Kernel did not start")
            kernel.execute(code: """
            import sys
            _pylab_test_argv = list(sys.argv)
            _pylab_test_file = globals().get('__file__')
            _pylab_test_name = __name__
            _pylab_test_path = list(sys.path)
            """, id: "baseline", scopeID: scope)
            wait({ finished("baseline") }, "Context baseline did not finish")
            noError("baseline")
            kernel.execute(code: restored.source, id: "imported", scopeID: scope, scriptPath: scriptPath)
            wait({ finished("imported") }, "Imported script did not finish")
            noError("imported")
            precondition(events.contains { $0.id == "imported" && $0.text?.contains("IMPORTED_OK 42 7") == true })
            wait({ kernel.workspace.contains { $0.name == "imported_value" && $0.value == "42" } &&
                   kernel.workspace.contains { $0.name == "edited_in_notebook" && $0.value == "43" } }, "Edited cell variables did not reach Workspace")
            kernel.execute(code: """
            assert sys.argv == _pylab_test_argv
            assert globals().get('__file__') == _pylab_test_file
            assert __name__ == _pylab_test_name
            assert sys.path == _pylab_test_path
            assert imported_value == 42 and sibling_value == 7 and edited_in_notebook == 43
            print('RESTORED_CONTEXT')
            """, id: "ordinary", scopeID: scope)
            wait({ finished("ordinary") }, "Ordinary cell did not finish")
            noError("ordinary")
            precondition(events.contains { $0.id == "ordinary" && $0.text?.contains("RESTORED_CONTEXT") == true })
            let unchanged = try String(contentsOf: original, encoding: .utf8)
            precondition(unchanged == source, "Execution wrote notebook edits into the original script")
            kernel.stop()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            print("PASS: " + mode.rawValue + " imported metadata → Swift controller → Jupyter: file/argv/import context, edited code, live workspace and restored ordinary cell")
        }
    }
}
