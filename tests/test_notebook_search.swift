import Foundation
@main struct SearchChecks {
    static func main() {
        let a = UUID(), b = UUID()
        let docs = [NotebookSearchDocument(id: a, title: "A", cells: [
            NotebookSearchCell(id: "same", name: "Import Data", source: "import numpy as np\nvalues = np.arange(5)\nprint(values)"),
            NotebookSearchCell(id: "empty", name: "Results", source: "")]),
            NotebookSearchDocument(id: b, title: "B", cells: [NotebookSearchCell(id: "same", name: "Plot", source: "α = 2\nVALUES = α\n")])]
        let all = NotebookSearchIndex.search(docs, query: "")
        precondition(all.results.count == 3 && Set(all.results.map(\.id)).count == 3)
        let values = NotebookSearchIndex.search(docs, query: "values")
        precondition(values.results.map(\.line) == [2,3,2])
        precondition(values.results.last?.notebookID == b)
        precondition(NotebookSearchIndex.search(docs, query: "values", caseSensitive: true).results.count == 2)
        precondition(NotebookSearchIndex.search(docs, query: "Import Data").results.first?.cellID == "same")
        precondition(NotebookSearchIndex.search(docs, query: "α").results.map(\.line) == [1,2])
        let limited = NotebookSearchIndex.search(docs, query: "values", limit: 2)
        precondition(limited.results.count == 2 && limited.truncated)
        precondition(!NotebookSearchIndex.search(docs, query: "unmatched").truncated)
        precondition(NotebookSearchIndex.search(docs, query: "values", limit: 3).truncated == false)
        precondition(NotebookSearchIndex.search(docs, query: "", limit: 0).truncated)
        print("PASS: notebook search names, source lines, Unicode, case, identity, and bounds")
    }
}
