import Foundation

/// Scope is a project kernel setting. Changing it starts a fresh session rather
/// than silently combining values that happen to have the same Python name.
enum VariableSharingMode: String, Codable, CaseIterable, Identifiable {
    case shared
    case independent

    var id: String { rawValue }
    var title: String { self == .shared ? "Shared Variables" : "Independent Cells" }
    var symbol: String { self == .shared ? "link" : "square.stack.3d.up" }
    var explanation: String {
        self == .shared
            ? "All cells and the console use one project workspace."
            : "Each cell keeps its own variables. The console uses the selected cell."
    }
}
