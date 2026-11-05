import Foundation
import AppKit
import UniformTypeIdentifiers

enum ProjectFileKind: Equatable {
    case folder, notebook, pythonScript, data, unsupported
}

/// Accepts only local file URLs. A drop opens/imports files through the parent;
/// it never copies files, modifies the filesystem, or runs Python on its own.
enum ProjectBrowserFiles {
    static let maximumDropCount = 128
    static let supportedDataExtensions: Set<String> = ["csv", "npy", "mat", "xlsx", "xls"]
    static func kind(of url: URL) -> ProjectFileKind {
        guard localURL(url) != nil else { return .unsupported }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return .folder }
        switch url.pathExtension.lowercased() {
        case "ipynb": return .notebook
        case "py", "pyw": return .pythonScript
        case let ext where supportedDataExtensions.contains(ext): return .data
        default: return .unsupported
        }
    }
    static func localURL(_ url: URL) -> URL? {
        guard url.isFileURL, !url.absoluteString.localizedCaseInsensitiveContains("%00"), url.path.hasPrefix("/"), !url.path.contains("\0"), url.path.utf8.count <= 65536, url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
        return url.standardizedFileURL
    }
    static func localURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return localURL(url) }
        if let data = item as? Data, data.count <= 65536, let text = String(data: data, encoding: .utf8), let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) { return localURL(url) }
        if let text = item as? String, text.utf8.count <= 65536, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) { return localURL(url) }
        return nil
    }
    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { input in
            guard let url = localURL(input), seen.insert(url.path).inserted else { return nil }
            return url
        }
    }
    static func ancestors(of folder: URL) -> [URL] {
        guard let folder = localURL(folder) else { return [] }
        var result: [URL] = []
        var path = (folder.path as NSString).standardizingPath
        var visited = Set<String>()
        // Walk absolute paths. URL objects built relative to a temporary/base
        // URL can remain unequal at the filesystem root and grow '..' forever.
        while !path.isEmpty && path != "/" {
            let parent = (path as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != path, visited.insert(parent).inserted else { break }
            result.append(URL(fileURLWithPath: parent, isDirectory: true))
            path = parent
        }
        return result
    }
}

@MainActor
enum ProjectFileDropLoader {
    enum Failure: LocalizedError {
        case tooManyFiles, unreadableLocation, timedOut
        var errorDescription: String? {
            switch self {
            case .tooManyFiles: return "Drop up to 128 files at a time."
            case .unreadableLocation: return "The dropped locations could not all be read. Drop local notebook, Python, data files, or folders. No files were opened."
            case .timedOut: return "Reading the dropped file locations took too long. Try dropping them again. No files were opened."
            }
        }
    }
    static func load(_ providers: [NSItemProvider], timeout: TimeInterval = 15, completion: @escaping (Result<[URL], Failure>) -> Void) {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard providers.count <= ProjectBrowserFiles.maximumDropCount else { completion(.failure(.tooManyFiles)); return }
        guard !providers.isEmpty else { completion(.failure(.unreadableLocation)); return }
        var loaded: [URL] = []
        var finished = false
        var deadline: DispatchWorkItem?
        func finish(_ result: Result<[URL], Failure>) {
            guard !finished else { return }
            finished = true
            deadline?.cancel(); deadline = nil
            completion(result)
        }
        let timeoutItem = DispatchWorkItem { finish(.failure(.timedOut)) }
        deadline = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, timeout), execute: timeoutItem)
        // Read sequentially: concurrent provider completion can otherwise reorder
        // notebook tabs or dependent data imports relative to the user's drop.
        func next(_ index: Int) {
            guard !finished else { return }
            guard index < providers.count else { finish(.success(ProjectBrowserFiles.unique(loaded))); return }
            providers[index].loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                let url = error == nil ? ProjectBrowserFiles.localURL(from: item) : nil
                DispatchQueue.main.async {
                    guard !finished else { return }
                    guard let url else { finish(.failure(.unreadableLocation)); return }
                    loaded.append(url)
                    next(index + 1)
                }
            }
        }
        next(0)
    }
}
