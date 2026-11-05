import Foundation
import Darwin

struct ImportedPythonScript: Sendable {
    let title: String
    let cellName: String
    let source: String
    let sourcePath: String
}

enum PythonScriptImport {
    static let byteLimit = 4 * 1024 * 1024
    static func read(_ url: URL, limit: Int = byteLimit) throws -> ImportedPythonScript {
        func failure(_ text: String) -> NSError {
            NSError(domain: "PyLabScriptImport", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              !url.absoluteString.localizedCaseInsensitiveContains("%00"), !url.path.contains("\0"),
              ["py", "pyw"].contains(url.pathExtension.lowercased()) else {
            throw failure("Choose a local Python .py or .pyw script.")
        }
        let descriptor = url.resolvingSymlinksInPath().path.withCString { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw failure("Choose a regular Python script file. Folders, sockets, and pipes cannot be imported.")
        }
        let boundedLimit = min(byteLimit, max(1, limit))
        let data = try handle.read(upToCount: boundedLimit + 1) ?? Data()
        guard data.count <= boundedLimit else { throw failure("This script is too large to import as a notebook cell (4 MiB maximum).") }
        guard var source = String(data: data, encoding: .utf8) else {
            throw failure("This script is not UTF-8 text. Save a UTF-8 copy before importing it.")
        }
        if source.first == "\u{feff}" { source.removeFirst() }
        guard !source.contains("\0") else { throw failure("The selected file contains binary data rather than Python text.") }
        let name = url.deletingPathExtension().lastPathComponent
        return ImportedPythonScript(title: name + ".ipynb", cellName: name, source: source,
                                    sourcePath: (url.path as NSString).standardizingPath)
    }
}
