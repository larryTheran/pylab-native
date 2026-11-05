import AppKit
import UniformTypeIdentifiers

@main
struct ConsoleDockChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func mainQueueTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
    static func data(_ provider: NSItemProvider) async -> Data {
        let result: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: consoleDockDragType.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let result else { fatalError("Console provider did not supply its private payload") }
        return result
    }
    @MainActor static func main() async throws {
        let project = UUID(), otherProject = UUID()
        let state = ConsoleDockDragState()
        require(!state.isDragging && state.target == nil, "Dock feedback must begin inactive")
        var placement = ConsolePlacement.workspaceBottom
        var callbacks = 0
        let apply: (ConsolePlacement) -> Void = { placement = $0; callbacks += 1 }
        let original = state.begin(scope: project)
        state.hover(.notebookBottom, scope: otherProject)
        require(state.target == nil && !state.canDrop(scope: otherProject), "Other projects must not receive console hover")
        state.hover(.notebookBottom, scope: project)
        require(state.target == .notebookBottom && placement == .workspaceBottom && callbacks == 0,
                "Hover must preview without moving or recreating the console")
        state.exit(.windowBottom)
        require(state.target == .notebookBottom, "Leaving another zone must not clear the current destination")
        state.exit(.notebookBottom)
        require(state.target == nil, "Leaving a target must clear its feedback")
        let foreignState = ConsoleDockDragState()
        let foreign = foreignState.begin(scope: project)
        require(!state.commit(foreign.data, scope: project, placement: .windowBottom, onSelect: apply), "Another window's console must be rejected even for the same project")
        require(!state.commit(original.data, scope: otherProject, placement: .windowBottom, onSelect: apply), "Cross-project console docking must be rejected")
        require(!state.commit(Data("invalid".utf8), scope: project, placement: .windowBottom, onSelect: apply), "Malformed payloads must not change layout")
        let replacement = state.begin(scope: project)
        state.end(token: original.token)
        require(state.isDragging, "An older provider must not cancel a newer console drag")
        require(!state.commit(original.data, scope: project, placement: .windowBottom, onSelect: apply), "A replaced token must not commit")
        state.end()
        require(!state.commit(replacement.data, scope: project, placement: .windowBottom, onSelect: apply), "A canceled console drag must not commit")
        require(callbacks == 0 && placement == .workspaceBottom, "All rejected/canceled drops must preserve placement")
        let valid = state.begin(scope: project)
        require(state.commit(valid.data, scope: project, placement: .windowBottom, reduceMotion: true) { value in
            apply(value)
            require(!state.commit(valid.data, scope: project, placement: .notebookBottom, onSelect: apply), "Reentrant reuse must already be consumed")
        }, "A local drop must select its requested destination")
        require(callbacks == 1 && placement == .windowBottom && !state.isDragging && state.target == nil,
                "A valid release must apply exactly one placement and clear feedback")
        require(!state.commit(valid.data, scope: project, placement: .notebookBottom, onSelect: apply), "A completed drop must not be replayable")

        var canceledProvider: NSItemProvider? = state.provider(scope: project)
        require(canceledProvider!.hasItemConformingToTypeIdentifier(consoleDockDragType.identifier), "Console drags must use the private console UTI")
        let canceledData = await data(canceledProvider!)
        state.hover(.notebookBottom, scope: project)
        withExtendedLifetime(canceledProvider) {}
        canceledProvider = nil
        await mainQueueTurn()
        require(!state.isDragging && state.target == nil, "Releasing a canceled provider must dismiss all dock targets")
        require(!state.commit(canceledData, scope: project, placement: .notebookBottom, onSelect: apply), "Released-provider payloads must not dock")
        let saved = try JSONEncoder().encode(ConsolePlacement.workspaceBottom)
        let restored = try JSONDecoder().decode(ConsolePlacement.self, from: saved)
        require(restored == .workspaceBottom, "Placement must persist by its stable raw value")
        print("PASS: console scope/token validation, hover-only feedback, cancellation/provider cleanup, single/reentrant-safe commit and persistence")
    }
}
