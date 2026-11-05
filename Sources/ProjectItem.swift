import Foundation

struct ProjectItem: Identifiable, Hashable {
    var url: URL
    var id: String { url.path }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

