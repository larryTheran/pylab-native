import Foundation

struct NotebookSearchCell {
    let id: String
    let name: String
    let source: String
}

struct NotebookSearchDocument {
    let id: UUID
    let title: String
    let cells: [NotebookSearchCell]
}

struct NotebookSearchResult: Identifiable, Equatable {
    let notebookID: UUID
    let notebookTitle: String
    let cellID: String
    let cellName: String
    let line: Int
    let preview: String
    var id: String { notebookID.uuidString + "|" + cellID + "|" + String(line) }
}

struct NotebookSearchPage {
    let results: [NotebookSearchResult]
    let truncated: Bool
}

enum NotebookSearchIndex {
    static func search(_ documents: [NotebookSearchDocument], query: String,
                       caseSensitive: Bool = false, limit: Int = 200) -> NotebookSearchPage {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var results: [NotebookSearchResult] = []
        let limit = max(0, limit)
        for document in documents {
            for cell in document.cells {
                let lines = cell.source.components(separatedBy: "\n")
                let nameMatches = !query.isEmpty && cell.name.range(of: query, options: options) != nil
                var matched = false
                for (offset, text) in lines.enumerated() {
                    let hit = query.isEmpty ? offset == 0 : text.range(of: query, options: options) != nil
                    guard hit else { continue }
                    guard results.count < limit else { return NotebookSearchPage(results: results, truncated: true) }
                    let preview = query.isEmpty ? (lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "Empty cell") : text
                    results.append(NotebookSearchResult(notebookID: document.id, notebookTitle: document.title,
                        cellID: cell.id, cellName: cell.name, line: offset + 1, preview: String(preview.prefix(300))))
                    matched = true
                }
                if nameMatches && !matched {
                    guard results.count < limit else { return NotebookSearchPage(results: results, truncated: true) }
                    results.append(NotebookSearchResult(notebookID: document.id, notebookTitle: document.title,
                        cellID: cell.id, cellName: cell.name, line: 1, preview: String((lines.first ?? "Empty cell").prefix(300))))
                }
            }
        }
        return NotebookSearchPage(results: results, truncated: false)
    }
}
