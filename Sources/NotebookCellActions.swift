import Foundation

extension NotebookStore {
    /// A copy starts as an unexecuted cell, with its own identity and namespace.
    @discardableResult
    func duplicateCell(_ id: String) -> String? {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = cells[index]
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? nextCellName() : trimmed
        let reserved = Set(cells.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var name = base + " copy"
        var number = 2
        while reserved.contains(name.lowercased()) {
            name = base + " copy " + String(number)
            number += 1
        }
        repeat { copy.id = UUID().uuidString.lowercased() }
        while cells.contains(where: { $0.id == copy.id })
        copy.name = name
        copy.outputs = []
        copy.executionCount = nil
        cells.insert(copy, at: index + 1)
        selectedID = copy.id
        revealRequest = nil
        endCellDrag()
        isDirty = true
        return copy.id
    }
}
