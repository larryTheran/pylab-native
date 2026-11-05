import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Private, in-process drag payload prevents a drop from moving cells in another notebook.
let cellDragType = UTType(exportedAs: "org.pylab.native.cell-reorder", conformingTo: .data)

struct LocalReorderPayload: Codable, Equatable {
    let namespace: String
    let token: UUID
    let sourceID: String
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data) -> LocalReorderPayload? { try? JSONDecoder().decode(Self.self, from: data) }
}

/// SwiftUI retains the provider for its native drag. Releasing it also removes
/// feedback after a canceled drag, which has no performDrop callback.
private final class LocalReorderProvider: NSItemProvider {
    var onRelease: (() -> Void)?
    deinit {
        let release = onRelease
        DispatchQueue.main.async { release?() }
    }
}

func localReorderProvider(payload: LocalReorderPayload, type: UTType,
                          onRelease: @escaping () -> Void) -> NSItemProvider {
    let provider = LocalReorderProvider()
    provider.onRelease = onRelease
    let data = payload.data
    provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
        completion(data, nil)
        return nil
    }
    return provider
}

private var activeCellDrags: [String: LocalReorderPayload] = [:]

extension NotebookStore {
    func cellDragProvider(_ id: String) -> NSItemProvider {
        guard cells.contains(where: { $0.id == id }) else { return NSItemProvider() }
        let payload = LocalReorderPayload(namespace: dragNamespace, token: UUID(), sourceID: id)
        activeCellDrags[dragNamespace] = payload
        dropTargetID = nil
        return localReorderProvider(payload: payload, type: cellDragType) { [weak self] in
            self?.endCellDrag(token: payload.token)
        }
    }

    func canTargetCell(_ targetID: String) -> Bool {
        guard let active = activeCellDrags[dragNamespace], active.sourceID != targetID else { return false }
        return cells.contains { $0.id == active.sourceID } && cells.contains { $0.id == targetID }
    }

    func commitCellDrop(_ data: Data, to targetID: String, reduceMotion: Bool = false) -> Bool {
        guard let payload = LocalReorderPayload.decode(data),
              payload.namespace == dragNamespace, activeCellDrags[dragNamespace] == payload,
              canTargetCell(targetID) else { return false }
        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) {
            moveCell(payload.sourceID, to: targetID)
            dropTargetID = nil
        }
        activeCellDrags[dragNamespace] = nil
        return true
    }

    func endCellDrag(token: UUID? = nil) {
        if let token, activeCellDrags[dragNamespace]?.token != token { return }
        activeCellDrags[dragNamespace] = nil
        dropTargetID = nil
    }

    /// Move a cell to the target's position without changing its identity or selection.
    func moveCell(_ id: String, to targetID: String) {
        guard let from = cells.firstIndex(where: { $0.id == id }),
              let to = cells.firstIndex(where: { $0.id == targetID }), from != to else { return }
        let cell = cells.remove(at: from)
        cells.insert(cell, at: to)
        isDirty = true
    }
}

struct CellDropDelegate: DropDelegate {
    let targetID: String
    @ObservedObject var store: NotebookStore
    var reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [cellDragType]) && store.canTargetCell(targetID)
    }
    func dropEntered(info: DropInfo) {
        if validateDrop(info: info) { store.dropTargetID = targetID }
    }
    func dropExited(info: DropInfo) {
        if store.dropTargetID == targetID { store.dropTargetID = nil }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let provider = info.itemProviders(for: [cellDragType]).first else { return false }
        store.dropTargetID = nil
        // Retain the provider until validation completes so cancellation cleanup
        // cannot invalidate a drop while its private payload is loading.
        provider.loadDataRepresentation(forTypeIdentifier: cellDragType.identifier) { [provider] data, _ in
            _ = provider
            DispatchQueue.main.async {
                guard let data else { store.endCellDrag(); return }
                _ = store.commitCellDrop(data, to: targetID, reduceMotion: reduceMotion)
            }
        }
        return true
    }
}
