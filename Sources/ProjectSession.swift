import Foundation

/// Optional settings keep sessions written by earlier versions readable.
struct StoredProject: Codable, Equatable {
    var folder: String
    var notebooks: [String]
    var selectedNotebook: String?
    var variableMode: VariableSharingMode? = nil
    var resolvedVariableMode: VariableSharingMode { variableMode ?? .shared }
    private enum CodingKeys: String, CodingKey { case folder, notebooks, selectedNotebook, variableMode }
    init(folder: String, notebooks: [String], selectedNotebook: String?, variableMode: VariableSharingMode? = nil) {
        self.folder = folder; self.notebooks = notebooks; self.selectedNotebook = selectedNotebook; self.variableMode = variableMode
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        folder = try values.decode(String.self, forKey: .folder)
        notebooks = try values.decodeIfPresent([String].self, forKey: .notebooks) ?? []
        selectedNotebook = try values.decodeIfPresent(String.self, forKey: .selectedNotebook)
        variableMode = try? values.decode(VariableSharingMode.self, forKey: .variableMode)
    }
}
struct StoredSession: Codable, Equatable {
    var projects: [StoredProject]
    var selectedIndex: Int
}
