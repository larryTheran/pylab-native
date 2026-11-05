import Foundation

/// Origin is notebook metadata, never a directive inserted into visible code.
/// The kernel applies it only while that imported script cell is executing.
enum ImportedScriptContext {
    static let metadataKey = "pylab_script_path"

    static func path(for cell: NotebookCell) -> String? {
        guard let metadata = cell.original["metadata"] as? [String: Any],
              let value = metadata[metadataKey] as? String else { return nil }
        return normalizedPath(value)
    }
    static func normalizedPath(_ value: String) -> String? {
        guard value.hasPrefix("/"), !value.contains("\0"), value.utf8.count <= 65536 else { return nil }
        let path = (value as NSString).standardizingPath
        guard ["py", "pyw"].contains((path as NSString).pathExtension.lowercased()) else { return nil }
        return path
    }
}
