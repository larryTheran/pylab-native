import SwiftUI
import Combine
import UniformTypeIdentifiers

struct NotebookTab: Identifiable {
    let id: UUID
    let store: NotebookStore
    let untitledName: String
    var title: String { store.fileURL?.lastPathComponent ?? untitledName }
}

final class NotebookCollection: ObservableObject {
    @Published var tabs: [NotebookTab] = []
    @Published var selectedID: UUID
    private var subscriptions: [UUID: AnyCancellable] = [:]
    let dragState = TabDragState()
    var dragNamespace: String { dragState.namespace }
    private var dragSubscription: AnyCancellable?

    init() {
        let id = UUID()
        selectedID = id
        append(id: id)
        dragSubscription = dragState.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    private func append(id: UUID) {
        let reserved = Set(tabs.map(\.untitledName))
        var n = 1
        while reserved.contains("Untitled \(n)") { n += 1 }
        let store = NotebookStore()
        tabs.append(NotebookTab(id: id, store: store, untitledName: "Untitled \(n)"))
        subscriptions[id] = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    var selected: NotebookTab { tabs.first(where: { $0.id == selectedID }) ?? tabs[0] }
    var isDirty: Bool { tabs.contains { $0.store.isDirty } }
    func add() { let id = UUID(); append(id: id); selectedID = id }
    func addLoaded(_ store: NotebookStore, untitledName: String? = nil) {
        // Restored sessions and explicit opens share this entry point. Keep the
        // already-open store (including unsaved edits) when paths alias a file.
        if let url = store.fileURL, let existing = find(url: url) {
            selectedID = existing.id
            return
        }
        let id = UUID()
        tabs.append(NotebookTab(id: id, store: store, untitledName: untitledName ?? "Untitled \(tabs.count + 1)"))
        subscriptions[id] = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        selectedID = id
    }
    func remove(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index); subscriptions[id] = nil
        if selectedID == id { selectedID = tabs[min(index, tabs.count - 1)].id }
    }
    func move(_ id: UUID, to target: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == id }), let to = tabs.firstIndex(where: { $0.id == target }), from != to else { return }
        tabs.insert(tabs.remove(at: from), at: to)
    }
    func step(_ id: UUID, by delta: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs.indices.contains(index + delta) else { return }
        move(id, to: tabs[index + delta].id)
    }
    func find(url: URL) -> NotebookTab? {
        tabs.first { tab in
            guard let current = tab.store.fileURL else { return false }
            return NotebookStore.refersToSameFile(current, url)
        }
    }
}

/// A tab drag has a private type, per-container namespace, and single-use token.
/// Hover state never changes tab order; only a fully validated drop can commit.
let tabDragType = UTType(exportedAs: "org.pylab.native.tab-reorder", conformingTo: .data)

final class TabDragState: ObservableObject {
    let namespace = UUID().uuidString
    @Published private(set) var sourceID: UUID?
    @Published private(set) var targetID: UUID?
    private(set) var session: LocalReorderPayload?

    @discardableResult func begin(_ id: UUID) -> LocalReorderPayload {
        let payload = LocalReorderPayload(namespace: namespace, token: UUID(), sourceID: id.uuidString)
        session = payload
        sourceID = id
        targetID = nil
        return payload
    }
    func provider(id: UUID) -> NSItemProvider {
        let payload = begin(id)
        return localReorderProvider(payload: payload, type: tabDragType) { [weak self] in
            self?.end(token: payload.token)
        }
    }
    func canTarget(_ id: UUID) -> Bool { session != nil && sourceID != nil && sourceID != id }
    func hover(_ id: UUID) {
        guard canTarget(id) else { return }
        targetID = id
    }
    func exit(_ id: UUID) { if targetID == id { targetID = nil } }
    func commit(_ data: Data, to target: UUID, reduceMotion: Bool = false, move: (UUID, UUID) -> Void) -> Bool {
        guard let payload = LocalReorderPayload.decode(data), payload.namespace == namespace,
              payload == session, let source = sourceID, payload.sourceID == source.uuidString,
              canTarget(target) else { return false }
        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { move(source, target) }
        end(token: payload.token)
        return true
    }
    func end(token: UUID? = nil) {
        if let token, session?.token != token { return }
        session = nil
        sourceID = nil
        targetID = nil
    }
}

struct TabReorderDrop: DropDelegate {
    @ObservedObject var state: TabDragState
    let target: UUID
    var reduceMotion = false
    let move: (UUID, UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [tabDragType]) && state.canTarget(target)
    }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { state.hover(target) } }
    func dropExited(info: DropInfo) { state.exit(target) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let provider = info.itemProviders(for: [tabDragType]).first else { return false }
        state.exit(target)
        provider.loadDataRepresentation(forTypeIdentifier: tabDragType.identifier) { [provider] data, _ in
            _ = provider
            DispatchQueue.main.async {
                guard let data else { state.end(); return }
                _ = state.commit(data, to: target, reduceMotion: reduceMotion, move: move)
            }
        }
        return true
    }
}
