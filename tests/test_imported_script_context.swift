import Foundation
@main struct ImportedScriptContextChecks {
    static func main() throws {
        let path = "/tmp/Project with 'quote 🚀/scripts/../analysis.py"
        let cell = NotebookCell(name: "Analysis", source: "print(__file__)", original: ["metadata": [ImportedScriptContext.metadataKey: path, "tags": ["keep"]]])
        precondition(ImportedScriptContext.path(for: cell) == "/tmp/Project with 'quote 🚀/analysis.py")
        let data = try JSONSerialization.data(withJSONObject: cell.json)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let reloaded = NotebookCell(name: cell.name, source: cell.source, original: json)
        precondition(ImportedScriptContext.path(for: reloaded) == ImportedScriptContext.path(for: cell))
        precondition((json["metadata"] as? [String:Any])?["tags"] as? [String] == ["keep"])
        for invalid in ["relative.py", "https://example.com/script.py", "/tmp/no-script.txt", "/tmp/a\0.py", String(repeating: "/", count: 65537) + "a.py"] {
            let cell = NotebookCell(original: ["metadata": [ImportedScriptContext.metadataKey: invalid]])
            precondition(ImportedScriptContext.path(for: cell) == nil)
        }
        precondition(ImportedScriptContext.path(for: NotebookCell()) == nil)
        precondition(ImportedScriptContext.path(for: NotebookCell(original: ["metadata": [ImportedScriptContext.metadataKey: 42]])) == nil)
        print("PASS: imported script metadata path persistence, Unicode/quotes, normalization and malformed-path fallback")
    }
}
