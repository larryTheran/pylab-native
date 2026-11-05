import Foundation

@main
struct NotebookRobustnessChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func document(_ cells: [[String: Any]]) -> [String: Any] {
            ["nbformat": 4, "nbformat_minor": 5, "metadata": ["keep": true], "cells": cells]
        }
        func write(_ object: [String: Any], to name: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
            return url
        }
        let valid: [String: Any] = ["id": "original", "cell_type": "code", "source": "value = 42", "metadata": [:], "outputs": [], "execution_count": NSNull()]
        let input = try write(document([valid]), to: "original.ipynb")
        let store = NotebookStore()
        try store.load(from: input)
        store.cells[0].source += "\n# unsaved"
        store.markDirty()
        store.runningCellIDs = ["original"]
        store.breakpoints = ["original": [1]]
        store.executionTimes = ["original": 0.5]
        let expectedSource = store.cells[0].source
        let invalidFields: [[String: Any]] = [
            ["source": 7], ["source": ["valid", 5]], ["outputs": "discarded before fix"],
            ["metadata": ["not", "an object"]], ["execution_count": true], ["execution_count": -1],
            ["execution_count": 1.5], ["cell_type": "unknown"], ["cell_type": "markdown"]
        ]
        for (index, changes) in invalidFields.enumerated() {
            var bad = valid
            for (key, value) in changes { bad[key] = value }
            let url = try write(document([bad]), to: "malformed-\(index).ipynb")
            do { try store.load(from: url); require(false, "malformed notebook accepted: \(changes)") }
            catch {}
            require(store.cells.count == 1 && store.cells[0].source == expectedSource, "failed load changed code")
            require(store.fileURL == input && store.isDirty, "failed load changed path/dirty state")
            require(store.runningCellIDs == ["original"] && store.breakpoints["original"] == [1], "failed load changed transient state")
        }
        var duplicate = valid; duplicate["source"] = "other = 10"
        var invalidID = valid; invalidID["id"] = "bad id/with slash"
        var missingID = valid; missingID.removeValue(forKey: "id")
        let duplicateURL = try write(document([valid, duplicate, invalidID, missingID]), to: "duplicates.ipynb")
        try store.load(from: duplicateURL)
        require(store.cells.count == 4 && Set(store.cells.map(\.id)).count == 4, "cell IDs must be unique")
        require(store.cells[0].id == "original" && store.cells[1].source == "other = 10", "valid identity/content changed")
        require(store.isDirty, "repaired supplied identities must be saved")
        require(store.runningCellIDs.isEmpty && store.breakpoints.isEmpty && store.executionTimes.isEmpty, "load retained stale execution state")
        let repaired = folder.appendingPathComponent("repaired.ipynb")
        try store.save(to: repaired)
        let originalIDs = store.cells.map(\.id)
        let reloaded = NotebookStore(); try reloaded.load(from: repaired)
        require(reloaded.cells.map(\.id) == originalIDs && !reloaded.isDirty, "identity repair did not persist")
        let legacy = try write(document([missingID]), to: "legacy.ipynb")
        try reloaded.load(from: legacy)
        require(!reloaded.isDirty && !reloaded.cells[0].id.isEmpty, "normal legacy IDs should load cleanly")

        // Failed saves neither normalize live names nor change the saved path.
        try store.load(from: input)
        store.cells[0].name = "  "
        store.isDirty = false
        let missingFolder = folder.appendingPathComponent("missing/output.ipynb")
        do { try store.save(to: missingFolder); require(false, "save to absent directory succeeded") } catch {}
        require(store.cells[0].name == "  " && !store.isDirty && store.fileURL == input, "failed save mutated live document")
        let beforeEncodingFailure = try Data(contentsOf: input)
        store.cells[0].outputs = [["output_type": "display_data", "data": ["bad": Double.nan]]]
        do { try store.save(to: input); require(false, "invalid JSON should fail") } catch {}
        let afterEncodingFailure = try Data(contentsOf: input)
        require(afterEncodingFailure == beforeEncodingFailure, "encoding failure damaged saved file")
        require(store.cells[0].name == "  " && !store.isDirty, "encoding failure mutated name/dirty state")

        // External edits cannot be silently overwritten. Save As remains available.
        try store.load(from: input)
        store.cells[0].source = "local_edits = True"; store.markDirty()
        var externallyEdited = valid; externallyEdited["source"] = "outside_edits = True"
        _ = try write(document([externallyEdited]), to: "original.ipynb")
        let externalBytes = try Data(contentsOf: input)
        do { try store.save(to: input); require(false, "external edit was overwritten") }
        catch { require(error.localizedDescription.contains("Save As"), "conflict error is not actionable") }
        let afterConflict = try Data(contentsOf: input)
        require(afterConflict == externalBytes && store.isDirty && store.cells[0].source == "local_edits = True", "conflict lost a version")
        let copy = folder.appendingPathComponent("my-edits.ipynb")
        try store.save(to: copy)
        require(store.fileURL == copy && !store.isDirty, "Save As after conflict failed")
        store.cells[0].source += "\n# keep"; store.markDirty()
        try FileManager.default.removeItem(at: copy)
        do { try store.save(to: copy); require(false, "missing original should require Save As") } catch {}
        require(!FileManager.default.fileExists(atPath: copy.path) && store.isDirty, "deleted original silently recreated")

        let alias = folder.appendingPathComponent("alias.ipynb")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: input)
        let hardlink = folder.appendingPathComponent("hardlink.ipynb")
        try FileManager.default.linkItem(at: input, to: hardlink)
        let collection = NotebookCollection()
        let opened = NotebookStore(); try opened.load(from: input)
        collection.addLoaded(opened)
        require(collection.find(url: alias)?.store === opened && collection.find(url: hardlink)?.store === opened, "file aliases bypass duplicate-tab check")
        opened.cells[0].source = "saved_through_alias = True"; opened.markDirty()
        try opened.save(to: alias)
        let aliasAttributes = try FileManager.default.attributesOfItem(atPath: alias.path)
        require(aliasAttributes[.type] as? FileAttributeType == .typeSymbolicLink, "save replaced notebook symlink")
        let aliasReload = NotebookStore(); try aliasReload.load(from: input)
        require(aliasReload.cells[0].source == "saved_through_alias = True", "alias save did not update original file")

        let first = store.cells[0].id
        let second = store.addCell(after: first)
        let third = store.addCell(after: second)
        store.selectedID = first
        store.breakpoints[second] = [1]
        store.executionTimes[second] = 1
        store.runningCellIDs.insert(second)
        let provider = store.cellDragProvider(second)
        require(store.canTargetCell(third), "fixture drag did not begin")
        store.removeCell(second)
        require(store.selectedID == first, "removing another cell changed selection")
        require(store.breakpoints[second] == nil && store.executionTimes[second] == nil && !store.runningCellIDs.contains(second), "removed cell retained stale execution data")
        require(!store.canTargetCell(third), "removed cell retained active drag")
        _ = provider
        store.breakpoints[first] = [1]
        store.runningCellIDs.insert(first)
        store.executionTimes[first] = 5
        store.revealCell(first, line: 1)
        store.newNotebook()
        require(store.cells.count == 1 && store.fileURL == nil && !store.isDirty && store.runningCellIDs.isEmpty && store.breakpoints.isEmpty && store.executionTimes.isEmpty && store.revealRequest == nil, "new notebook retained old state")
        print("PASS: malformed load preservation, unique cell identities, failed/atomic saves, external conflicts, alias detection, and transient cleanup")
    }
}
