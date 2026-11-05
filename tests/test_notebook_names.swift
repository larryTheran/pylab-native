import Foundation

@main
struct NamedNotebookChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-notebook-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("original.ipynb")
        let original: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": ["author": "test", "custom": ["keep": true]], "cells": [
            ["id":"alpha", "cell_type":"code", "source":["x=1\n", "x"], "execution_count": 1, "outputs": [["output_type":"execute_result", "execution_count": 1, "data":["text/plain":"1", "text/html":"<b>1</b>"], "metadata": [:]]], "metadata": ["tags":["preserve"], "custom": ["v":7]]],
            ["id":"beta", "cell_type":"markdown", "source":"# Hello", "metadata": ["pylab_cell_name":"Results", "collapsed":true]],
            ["id":"gamma", "cell_type":"raw", "source":"untouched", "metadata": [:]]
        ]]
        try JSONSerialization.data(withJSONObject: original).write(to: input)
        let store = NotebookStore()
        try store.load(from: input)
        require(store.cells.map(\.id) == ["alpha", "beta", "gamma"], "loading must preserve stable cell IDs")
        require(store.cells[0].source == "x=1\nx", "multiline source arrays must round-trip")
        require(store.cells[1].name == "Results", "existing names must load")
        require(!store.cells[0].name.isEmpty && !store.cells[2].name.isEmpty, "unnamed cells need visible names")
        require(!store.isDirty, "loading old notebooks must not mark them dirty")
        store.renameCell("alpha", to: "  Data import  ")
        require(store.cells[0].name == "Data import", "renaming trims leading and trailing whitespace")
        require(store.isDirty, "renaming marks notebook dirty")
        let inserted = store.addCell(after: "alpha")
        require(store.cells.map(\.id).firstIndex(of: inserted) == 1, "new cell inserted after selected cell")
        require(store.selectedID == inserted, "new cell becomes selected")
        require(!store.cells[1].name.isEmpty, "new cell has visible default name")
        store.renameCell(inserted, to: "Data import")
        let destination = root.appendingPathComponent("renamed.ipynb")
        try store.save(to: destination)
        require(!store.isDirty, "save clears dirty flag")
        let doc = try JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as! [String: Any]
        let cells = doc["cells"] as! [[String: Any]]
        let metadata = cells[0]["metadata"] as! [String: Any]
        require(metadata["pylab_cell_name"] as? String == "Data import", "name must persist in cell metadata")
        require((metadata["tags"] as? [String]) == ["preserve"], "existing cell metadata must be preserved")
        require((metadata["custom"] as? [String:Int])?["v"] == 7, "nested metadata must survive")
        require(((doc["metadata"] as? [String:Any])?["author"] as? String) == "test", "notebook metadata must survive")
        let outputs = cells[0]["outputs"] as! [[String:Any]]
        require(((outputs[0]["data"] as? [String:Any])?["text/html"] as? String) == "<b>1</b>", "original rich outputs must survive")
        let reloaded = NotebookStore()
        try reloaded.load(from: destination)
        require(reloaded.cells.map(\.id) == ["alpha",inserted,"beta","gamma"], "reopening preserves original and new IDs")
        require(reloaded.cells[0].name == "Data import" && reloaded.cells[1].name == "Data import", "duplicate tab labels must remain attached to their individual IDs")
        reloaded.renameCell("gamma", to: "   ")
        require(!reloaded.cells[3].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "blank name falls back to visible default")
        reloaded.selectedID = "beta"
        reloaded.isDirty = false
        reloaded.moveCell("gamma", to: "alpha")
        require(reloaded.cells.map(\.id) == ["gamma", "alpha", inserted, "beta"], "moving up preserves cell identities")
        require(reloaded.selectedID == "beta" && reloaded.isDirty, "reordering preserves selection and marks notebook dirty")
        let reordered = root.appendingPathComponent("reordered.ipynb")
        try reloaded.save(to: reordered)
        let savedOrder = try JSONSerialization.jsonObject(with: Data(contentsOf: reordered)) as! [String: Any]
        let savedCells = savedOrder["cells"] as! [[String: Any]]
        require(savedCells.compactMap { $0["id"] as? String } == ["gamma", "alpha", inserted, "beta"], "saved notebook preserves reordered cells")
        let again = NotebookStore(); try again.load(from: reordered)
        require(again.cells.map(\.id) == ["gamma", "alpha", inserted, "beta"], "reopening preserves reordered cells")
        reloaded.moveCell("gamma", to: "beta")
        require(reloaded.cells.map(\.id) == ["alpha", inserted, "beta", "gamma"], "moving down works")
        reloaded.selectedID = inserted
        reloaded.removeCell(inserted)
        require(reloaded.selectedID != inserted && reloaded.cells.contains { $0.id == reloaded.selectedID }, "deleting selected cell selects an existing cell")
        let remaining = reloaded.cells.map(\.id)
        remaining.forEach { reloaded.removeCell($0) }
        require(reloaded.cells.count == 1 && reloaded.selectedID == reloaded.cells[0].id, "deleting the last cell leaves a selectable cell")
        require(!reloaded.cells[0].name.isEmpty, "replacement last cell has a visible name")
        print("PASS: names, reordering, persistence, metadata, outputs, selection, and deletion")
    }
}
