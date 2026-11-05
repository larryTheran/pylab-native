import Foundation

@main struct CellActionChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func json(_ cell: NotebookCell) throws -> Data {
        try JSONSerialization.data(withJSONObject: cell.json, options: [.sortedKeys])
    }
    static func main() throws {
        let store = NotebookStore()
        let output: [String: Any] = ["output_type": "stream", "name": "stdout", "text": "executed\n"]
        let original = NotebookCell(id: "alpha", cellType: "code", name: "  Analyze  ", source: "x = 42\nprint(x)",
            outputs: [output], executionCount: 7,
            original: ["metadata": ["pylab_cell_name": "old", "tags": ["keep"], "custom": ["value": 9]], "extra": ["keep": true]])
        store.cells = [original, NotebookCell(id: "collision", name: "ANALYZE COPY"), NotebookCell(id: "tail", name: "Tail")]
        store.selectedID = "tail"
        store.breakpoints["alpha"] = [1]
        store.executionTimes["alpha"] = 0.75
        store.runningCellIDs.insert("alpha")
        store.revealCell("alpha", line: 2)
        store.isDirty = false
        let before = try json(original)
        guard let first = store.duplicateCell("alpha") else { fatalError("Could not duplicate cell") }
        require(store.cells.map(\.id) == ["alpha", first, "collision", "tail"], "copy inserts after clicked cell")
        let copy = store.cells[1]
        require(first != "alpha" && copy.name == "Analyze copy 2", "fresh identity and case-insensitive unique name")
        require(copy.source == original.source && copy.cellType == original.cellType, "source and kind copied")
        require(copy.outputs.isEmpty && copy.executionCount == nil, "copy must be unexecuted")
        require(store.breakpoints[first] == nil && store.executionTimes[first] == nil && !store.runningCellIDs.contains(first), "runtime state is not copied")
        require(store.runningCellIDs.contains("alpha") && store.breakpoints["alpha"] == [1] && store.executionTimes["alpha"] == 0.75, "running original state retained")
        require(store.selectedID == first && store.isDirty && store.revealRequest == nil, "copy selected and old reveal cleared")
        let after = try json(store.cells[0])
        require(after == before, "original cell is unchanged")
        let metadata = copy.json["metadata"] as? [String: Any]
        require(metadata?["tags"] as? [String] == ["keep"] && (metadata?["custom"] as? [String: Int])?["value"] == 9, "custom metadata retained")
        guard let second = store.duplicateCell("alpha") else { fatalError("Second duplication failed") }
        require(store.cells[1].id == second && store.cells[1].name == "Analyze copy 3" && second != first, "repeated copies remain unique and adjacent")
        let markdown = NotebookCell(id: "markdown", cellType: "markdown", name: "Notes", source: "![image](attachment:plot.png)",
            original: ["metadata": ["custom": true], "attachments": ["plot.png": ["image/png": "example"]]])
        store.cells.append(markdown)
        guard let markdownID = store.duplicateCell("markdown"), let markdownCopy = store.cells.first(where: { $0.id == markdownID }) else { fatalError("Markdown copy failed") }
        require(markdownCopy.cellType == "markdown" && markdownCopy.source == markdown.source, "markdown kind and source retained")
        require(((markdownCopy.json["attachments"] as? [String: Any])?["plot.png"] as? [String: String])?["image/png"] == "example", "markdown attachment retained")
        store.cells.append(NotebookCell(id: "blank-name", cellType: "raw", name: " ", source: "raw source"))
        guard let rawID = store.duplicateCell("blank-name"), let rawCopy = store.cells.first(where: { $0.id == rawID }) else { fatalError("Raw copy failed") }
        require(rawCopy.name == "Cell 1 copy" && rawCopy.cellType == "raw" && rawCopy.source == "raw source", "blank name gets visible fallback and raw source survives")
        store.isDirty = false
        let ids = store.cells.map(\.id), selection = store.selectedID
        require(store.duplicateCell("missing") == nil && store.cells.map(\.id) == ids && store.selectedID == selection && !store.isDirty, "unknown cell is no-op")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-cell-actions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("copies.ipynb")
        try store.save(to: url)
        let restored = NotebookStore()
        try restored.load(from: url)
        require(restored.cells.map(\.id) == store.cells.map(\.id) && restored.cells.first(where: { $0.id == first })?.name == "Analyze copy 2", "save/reopen retains copied IDs/names")
        require(restored.cells.first(where: { $0.id == first })?.outputs.isEmpty == true && restored.cells.first(where: { $0.id == first })?.executionCount == nil, "unexecuted state survives save/reopen")
        restored.selectedID = first
        restored.removeCell("tail")
        require(restored.selectedID == first, "deleting another cell preserves selection")
        for id in restored.cells.map(\.id) { restored.removeCell(id) }
        require(restored.cells.count == 1 && restored.selectedID == restored.cells[0].id && restored.cells[0].source.isEmpty, "deleting last cell keeps a selectable blank cell")
        print("PASS: duplicate source/type/metadata/attachments, fresh IDs/names, runtime isolation, save/reopen, and safe deletion selection")
    }
}
