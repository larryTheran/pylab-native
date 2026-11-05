import Foundation
@main struct ProjectSessionChecks {
    static func main() throws {
        let legacy = Data(#"{"projects":[{"folder":"/tmp/project","notebooks":["/tmp/a.ipynb"],"selectedNotebook":"/tmp/a.ipynb"}],"selectedIndex":0}"#.utf8)
        let old = try JSONDecoder().decode(StoredSession.self, from: legacy)
        precondition(old.projects[0].resolvedVariableMode == .shared)
        let current = StoredSession(projects: [
            StoredProject(folder: "/tmp/A", notebooks: ["/tmp/A/work.ipynb"], selectedNotebook: nil, variableMode: .independent),
            StoredProject(folder: "/tmp/B", notebooks: [], selectedNotebook: nil, variableMode: .shared)], selectedIndex: 1)
        let data = try JSONEncoder().encode(current)
        let restored = try JSONDecoder().decode(StoredSession.self, from: data)
        precondition(restored == current && restored.projects[0].resolvedVariableMode == .independent && restored.projects[1].resolvedVariableMode == .shared)
        let future = Data(#"{"projects":[{"folder":"/tmp/project","notebooks":[],"variableMode":"future-mode"}],"selectedIndex":0}"#.utf8)
        let fallback = try JSONDecoder().decode(StoredSession.self, from: future)
        precondition(fallback.projects.count == 1 && fallback.projects[0].resolvedVariableMode == .shared)
        print("PASS: legacy shared default, per-project independent/shared restore and future-mode fallback")
    }
}
