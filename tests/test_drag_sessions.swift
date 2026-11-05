import AppKit
import UniformTypeIdentifiers

@main
struct DragSessionChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func data(_ provider: NSItemProvider, type: UTType) async -> Data {
        let result: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let result else { fatalError("Drag provider did not supply its private payload") }
        return result
    }
    static func mainQueueTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @MainActor static func main() async {
        let group = NotebookCollection()
        let first = group.selectedID
        group.add(); let second = group.selectedID
        group.add(); let third = group.selectedID
        group.selectedID = second
        let original = group.tabs.map(\.id)
        let state = group.dragState
        let start = state.begin(first)
        state.hover(third)
        require(state.targetID == third && state.sourceID == first, "Local hover should expose feedback")
        require(group.tabs.map(\.id) == original && !group.isDirty, "Hover must never reorder or dirty notebooks")
        state.exit(third)
        require(state.targetID == nil, "Leaving the target should clear hover")
        require(!state.canTarget(first), "A source must not target itself")

        let foreign = TabDragState().begin(first)
        var moves = 0
        let move: (UUID, UUID) -> Void = { source, target in moves += 1; group.move(source, to: target) }
        require(!state.commit(foreign.data, to: third, move: move), "Other containers must be rejected")
        require(!state.commit(Data("invalid".utf8), to: third, move: move), "Malformed drops must be rejected")
        let replacement = state.begin(first)
        state.end(token: start.token)
        require(state.sourceID == first, "An older provider must not cancel a newer drag")
        require(!state.commit(start.data, to: third, move: move), "A replaced drag token must be rejected")
        state.end()
        require(!state.commit(replacement.data, to: third, move: move), "A canceled drag must not commit")
        require(moves == 0 && group.tabs.map(\.id) == original, "Rejected drops must leave order unchanged")
        let valid = state.begin(first)
        require(state.commit(valid.data, to: third, reduceMotion: true, move: move), "A local drop should commit")
        require(group.tabs.map(\.id) == [second, third, first] && group.selectedID == second, "Reordering must preserve selection and tab identity")
        require(state.sourceID == nil && state.targetID == nil, "Commit must clear the drag session")
        require(!state.commit(valid.data, to: second, move: move) && moves == 1, "A drop token must only commit once")

        let lifecycle = TabDragState()
        var canceledProvider: NSItemProvider? = lifecycle.provider(id: first)
        require(canceledProvider!.hasItemConformingToTypeIdentifier(tabDragType.identifier), "Tabs must use the private tab UTI")
        lifecycle.hover(third)
        withExtendedLifetime(canceledProvider) {}
        canceledProvider = nil
        await mainQueueTurn()
        require(lifecycle.sourceID == nil && lifecycle.targetID == nil, "Canceling/releasing a provider must remove feedback")

        let store = NotebookStore()
        let cellA = store.cells[0].id
        let cellB = store.addCell(after: cellA)
        let cellC = store.addCell(after: cellB)
        store.selectedID = cellB
        store.isDirty = false
        let order = store.cells.map(\.id)
        let firstProvider = store.cellDragProvider(cellA)
        let firstData = await data(firstProvider, type: cellDragType)
        let firstPayload = LocalReorderPayload.decode(firstData)!
        store.dropTargetID = cellC
        require(store.canTargetCell(cellC) && !store.canTargetCell(cellA), "Only another local cell is a destination")
        require(store.cells.map(\.id) == order && !store.isDirty, "Cell hover must not alter notebook content")
        let nextProvider = store.cellDragProvider(cellA)
        let nextData = await data(nextProvider, type: cellDragType)
        store.endCellDrag(token: firstPayload.token)
        require(store.canTargetCell(cellC), "Releasing an old cell provider must preserve the new session")
        require(!store.commitCellDrop(firstData, to: cellC), "Old cell tokens must not commit")
        let foreignStore = NotebookStore()
        require(!foreignStore.commitCellDrop(nextData, to: foreignStore.cells[0].id), "Cross-notebook cell drops must fail")
        store.endCellDrag()
        require(!store.commitCellDrop(nextData, to: cellC), "Canceled cell drops must fail")
        require(store.cells.map(\.id) == order && !store.isDirty, "Rejected cell drops must not mark the notebook dirty")
        let validProvider = store.cellDragProvider(cellA)
        let validData = await data(validProvider, type: cellDragType)
        require(store.commitCellDrop(validData, to: cellC, reduceMotion: true), "A local cell drop must commit")
        require(store.cells.map(\.id) == [cellB, cellC, cellA] && store.selectedID == cellB && store.isDirty,
                "A committed move must retain names, identity and selection, then mark dirty")
        store.isDirty = false
        require(!store.commitCellDrop(validData, to: cellB) && !store.isDirty, "Replayed cell drops must not modify content")
        withExtendedLifetime([firstProvider, nextProvider, validProvider]) {}
        print("PASS: drag namespace/token validation, canceled-provider cleanup, hover invariants, single-use commit, order and selection")
    }
}
