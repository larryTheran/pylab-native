import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ConsolePlacement: String, CaseIterable, Codable, Identifiable {
    case workspaceBottom
    case notebookBottom
    case windowBottom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workspaceBottom: return "Below Workspace"
        case .notebookBottom: return "Below Notebook"
        case .windowBottom: return "Across Bottom"
        }
    }
    var symbol: String {
        switch self {
        case .workspaceBottom: return "rectangle.rightthird.inset.filled"
        case .notebookBottom: return "rectangle.bottomthird.inset.filled"
        case .windowBottom: return "rectangle.bottomhalf.inset.filled"
        }
    }
    var detail: String {
        switch self {
        case .workspaceBottom: return "Keep code tall and place commands under variables"
        case .notebookBottom: return "Place commands directly beneath the notebook"
        case .windowBottom: return "Use the full notebook and workspace width"
        }
    }
}

let consoleDockDragType = UTType(exportedAs: "org.pylab.native.console-dock", conformingTo: .data)

/// One live console may dock only within its own project. Hover previews never
/// alter the layout, so cancellation keeps both placement and console state.
final class ConsoleDockDragState: ObservableObject {
    let namespace = UUID().uuidString
    @Published private(set) var isDragging = false
    @Published private(set) var target: ConsolePlacement?
    private(set) var session: LocalReorderPayload?
    private(set) var scope: UUID?

    @discardableResult func begin(scope: UUID) -> LocalReorderPayload {
        let payload = LocalReorderPayload(namespace: namespace, token: UUID(), sourceID: scope.uuidString)
        session = payload; self.scope = scope; target = nil; isDragging = true
        return payload
    }
    func provider(scope: UUID) -> NSItemProvider {
        let payload = begin(scope: scope)
        return localReorderProvider(payload: payload, type: consoleDockDragType) { [weak self] in
            self?.end(token: payload.token)
        }
    }
    func canDrop(scope: UUID) -> Bool { isDragging && session != nil && self.scope == scope }
    func hover(_ placement: ConsolePlacement, scope: UUID) {
        guard canDrop(scope: scope) else { return }
        target = placement
    }
    func exit(_ placement: ConsolePlacement) { if target == placement { target = nil } }
    @discardableResult func commit(_ data: Data, scope: UUID, placement: ConsolePlacement,
                                    reduceMotion: Bool = false, onSelect: (ConsolePlacement) -> Void) -> Bool {
        guard canDrop(scope: scope), let payload = LocalReorderPayload.decode(data),
              payload == session, payload.namespace == namespace, payload.sourceID == scope.uuidString else { return false }
        // Consume the session before invoking the layout action. A reentrant or
        // replayed drop therefore cannot apply placement a second time.
        end(token: payload.token)
        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { onSelect(placement) }
        return true
    }
    func end(token: UUID? = nil) {
        if let token, session?.token != token { return }
        isDragging = false; target = nil; session = nil; scope = nil
    }
}

private struct ConsoleDockDropDelegate: DropDelegate {
    @ObservedObject var state: ConsoleDockDragState
    let scope: UUID
    let placement: ConsolePlacement
    let reduceMotion: Bool
    let onSelect: (ConsolePlacement) -> Void
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [consoleDockDragType]) && state.canDrop(scope: scope)
    }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { state.hover(placement, scope: scope) } }
    func dropExited(info: DropInfo) { state.exit(placement) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let provider = info.itemProviders(for: [consoleDockDragType]).first else { return false }
        state.exit(placement)
        provider.loadDataRepresentation(forTypeIdentifier: consoleDockDragType.identifier) { [provider] data, _ in
            _ = provider
            DispatchQueue.main.async {
                guard let data else { state.end(); return }
                _ = state.commit(data, scope: scope, placement: placement, reduceMotion: reduceMotion, onSelect: onSelect)
            }
        }
        return true
    }
}

struct ConsoleDockDragPreview: View {
    var body: some View {
        Label("Move Console", systemImage: "terminal")
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .glassEffect(.regular, in: Capsule())
            .frame(width: 190, height: 46)
    }
}

/// App layout supplies the three destination regions; each card only previews
/// its own target and applies placement after a validated local drop.
struct ConsoleDockZoneView: View {
    let placement: ConsolePlacement
    let currentPlacement: ConsolePlacement
    @ObservedObject var state: ConsoleDockDragState
    let scope: UUID
    let onSelect: (ConsolePlacement) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var targeted: Bool { state.target == placement && state.canDrop(scope: scope) }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: placement.symbol).font(.system(size: 22, weight: .medium))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(placement.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(targeted ? "Release to place console" : (currentPlacement == placement ? "Current position" : placement.detail))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if targeted { Image(systemName: "arrow.down.to.line.compact").foregroundStyle(Color.accentColor) }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(targeted ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.16), lineWidth: targeted ? 1.5 : 0.8))
        .magneticDropFeedback(isTargeted: targeted, cornerRadius: 14, movesContent: false)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onDrop(of: [consoleDockDragType], delegate: ConsoleDockDropDelegate(state: state, scope: scope, placement: placement, reduceMotion: reduceMotion, onSelect: onSelect))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Move console " + placement.title.lowercased())
        .accessibilityHint("Choose a position from the console menu when using the keyboard")
    }
}
