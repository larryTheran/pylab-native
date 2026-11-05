import Foundation
import Darwin
@main struct ScriptImportChecks {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("My analysis.py")
        let marker = folder.appendingPathComponent("must-not-exist")
        let code = "from pathlib import Path\nPath(" + String(reflecting: marker.path) + ").touch()\nprint('🚀')\n"
        try Data(("\u{feff}" + code).utf8).write(to: path)
        let imported = try PythonScriptImport.read(path)
        precondition(imported.source == code && imported.title == "My analysis.ipynb" && imported.cellName == "My analysis")
        precondition(imported.sourcePath == path.standardizedFileURL.path)
        precondition(!FileManager.default.fileExists(atPath: marker.path), "Import executed source")
        let original = try Data(contentsOf: path)
        precondition(original == Data(("\u{feff}" + code).utf8), "Import changed original")
        func rejected(_ action: () throws -> Void) { do { try action(); preconditionFailure("Invalid import accepted") } catch {} }
        rejected { _ = try PythonScriptImport.read(path, limit: 4) }
        let binary = folder.appendingPathComponent("binary.py")
        try Data([0xff,0xfe,0]).write(to: binary)
        rejected { _ = try PythonScriptImport.read(binary) }
        rejected { _ = try PythonScriptImport.read(URL(string: "https://example.com/script.py")!) }
        let fifo = folder.appendingPathComponent("pipe.py")
        precondition(mkfifo(fifo.path, 0o600) == 0)
        rejected { _ = try PythonScriptImport.read(fifo) }
        let alias = folder.appendingPathComponent("alias.py")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: path)
        let aliased = try PythonScriptImport.read(alias)
        precondition(aliased.source == code && aliased.title == "alias.ipynb")
        rejected { _ = try PythonScriptImport.read(URL(string: "file://remotehost/tmp/script.py")!) }
        let empty = folder.appendingPathComponent("empty.pyw")
        try Data().write(to: empty)
        let emptyImport = try PythonScriptImport.read(empty)
        precondition(emptyImport.source.isEmpty)
        print("PASS: script import preserves UTF-8/BOM text and original file, never executes, rejects oversized/binary/remote/special files and supports symlinks")
    }
}
