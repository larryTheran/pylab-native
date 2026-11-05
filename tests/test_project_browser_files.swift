import Foundation
import AppKit
import UniformTypeIdentifiers

@main struct ProjectBrowserFilesChecks {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("pylab-file-drops-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a=root.appendingPathComponent("Alpha β.ipynb"), b=root.appendingPathComponent("script.PYW"), c=root.appendingPathComponent("values.CSV")
        for url in [a,b,c] { try Data().write(to:url) }
        precondition(ProjectBrowserFiles.kind(of:root) == .folder)
        precondition(ProjectBrowserFiles.kind(of:a) == .notebook && ProjectBrowserFiles.kind(of:b) == .pythonScript && ProjectBrowserFiles.kind(of:c) == .data)
        precondition(ProjectBrowserFiles.kind(of:root.appendingPathComponent("notes.txt")) == .unsupported)
        precondition(ProjectBrowserFiles.localURL(URL(string:"https://example.com/a.ipynb")!) == nil)
        precondition(ProjectBrowserFiles.localURL(URL(string:"file://remote.example.com/a.ipynb")!) == nil)
        precondition(ProjectBrowserFiles.localURL(from:a as NSURL) == a.standardizedFileURL)
        precondition(ProjectBrowserFiles.localURL(from:a.absoluteString.data(using:.utf8)! as NSData) == a.standardizedFileURL)
        precondition(ProjectBrowserFiles.localURL(from:"/tmp/bare-path.ipynb" as NSString) == nil)
        precondition(ProjectBrowserFiles.localURL(URL(string:"file:relative.py")!) == nil)
        precondition(ProjectBrowserFiles.localURL(URL(string:"file:///tmp/file.py%00hidden")!) == nil)
        precondition(ProjectBrowserFiles.unique([a,b,a,URL(string:"https://example.com/no")!]) == [a,b])
        precondition(ProjectBrowserFiles.ancestors(of:URL(fileURLWithPath:"/a/b")).map(\.path) == ["/a","/"])
        precondition(ProjectBrowserFiles.ancestors(of:URL(fileURLWithPath:"/")).isEmpty)
        for path in [FileManager.default.temporaryDirectory.appendingPathComponent("browser-child"),
                     URL(fileURLWithPath: "nested/child", relativeTo: FileManager.default.temporaryDirectory)] {
            let parents = ProjectBrowserFiles.ancestors(of: path)
            precondition(parents.last?.path == "/")
            precondition(Set(parents.map(\.path)).count == parents.count)
            precondition(parents.count <= path.pathComponents.count + 1)
        }
        func provider(_ text:String, delay:Double=0) -> NSItemProvider {
            let provider=NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier:UTType.fileURL.identifier,visibility:.all) { completion in
                DispatchQueue.global().asyncAfter(deadline:.now()+delay) { completion(text.data(using:.utf8),nil) }
                return nil
            }
            return provider
        }
        func load(_ providers:[NSItemProvider]) -> Result<[URL],ProjectFileDropLoader.Failure> {
            var result:Result<[URL],ProjectFileDropLoader.Failure>?
            ProjectFileDropLoader.load(providers) { result=$0 }
            let deadline=Date(timeIntervalSinceNow:8)
            while result == nil && Date()<deadline { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.01)) }
            return result ?? .failure(.unreadableLocation)
        }
        let ordered=try load([provider(a.absoluteString,delay:0.08),provider(b.absoluteString,delay:0.001),provider(a.absoluteString)]).get()
        precondition(ordered == [a,b], "Provider completion must preserve dropped order and deduplicate")
        switch load([provider(a.absoluteString),provider("https://example.com/no")]) {
        case .failure(.unreadableLocation): break
        default: preconditionFailure("Unreadable/remote locations must reject the entire batch")
        }
        switch load((0..<129).map { _ in provider(a.absoluteString) }) {
        case .failure(.tooManyFiles): break
        default: preconditionFailure("Oversized batches must reject before opening a subset")
        }
        var timeoutEvents = 0
        ProjectFileDropLoader.load([provider(a.absoluteString,delay:0.15)], timeout:0.02) { result in
            timeoutEvents += 1
            guard case .failure(.timedOut) = result else { preconditionFailure("Slow provider did not time out atomically") }
        }
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.3))
        precondition(timeoutEvents == 1, "A late provider must not call completion twice or open files after timeout")
        print("PASS: local drop validation, Unicode paths, file classification, stable provider order, deduplication, atomic failure/count bounds and timeout with late callback rejection")
    }
}
