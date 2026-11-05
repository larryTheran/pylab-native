import SwiftUI
import AppKit

/// Two presentations of the same notebook store; switching never duplicates a cell.
struct NotebookPresentationView: View {
    @ObservedObject var store: NotebookStore
    let onRun: (String, String) -> Void
    let onComplete: (String, Int, @escaping ([String], NSRange) -> Void) -> Void
    var onRunSelection: ((String, String) -> Void)? = nil
    var onInterrupt: () -> Void = {}
    @AppStorage("notebookTabbedView") private var tabbed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cellGlassNamespace
    @Namespace private var cellSelectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if tabbed {
                    tabStrip.frame(maxWidth: .infinity)
                } else {
                    Text("Cells").font(.subheadline.weight(.semibold))
                        .padding(.leading, 12)
                    Spacer(minLength: 8)
                }
                Picker("Cell layout", selection: $tabbed) {
                    Text("All Cells").tag(false)
                    Text("Cell Tabs").tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .frame(width: 170)
                .fixedSize()
                .padding(.trailing, 12)
                .help("Show all cells or one named cell at a time")
                .accessibilityLabel("Cell layout")
            }
            .frame(minHeight: 44)
            .background(.bar)
            Divider()
            NotebookView(store: store, onRun: onRun, onComplete: onComplete,
                onRunSelection: onRunSelection, singleCell: tabbed, onInterrupt: onInterrupt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayName(_ cell: NotebookCell) -> String {
        let name = cell.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Cell" : name
    }

    private func executionPhase(for id: String) -> KernelExecutionPhase? {
        store.cellExecutionActivity[id]?.phase ?? (store.runningCellIDs.contains(id) ? .running : nil)
    }

    @ViewBuilder private func selectionBackground(for id: String) -> some View {
        if store.selectedID == id {
            if reduceMotion {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18))
                    .matchedGeometryEffect(id: "selected-cell", in: cellSelectionNamespace)
            }
        }
    }
    private func cellHelp(_ cell: NotebookCell, phase: KernelExecutionPhase?) -> String {
        if let phase { return ExecutionIndicator.label(for: phase) + " · " + displayName(cell) }
        return "Drag to reorder · " + displayName(cell)
    }
    private func cellTab(_ cell: NotebookCell) -> some View {
        let phase = executionPhase(for: cell.id)
        return Button {
            store.selectedID = cell.id
        } label: {
            HStack(spacing: 6) {
                if let phase = phase {
                    ExecutionIndicator(phase: phase, compact: true)
                } else {
                    Image(systemName: cell.cellType == "code" ? "chevron.left.forwardslash.chevron.right" : "text.alignleft")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(displayName(cell))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background { selectionBackground(for: cell.id) }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                store.dropTargetID == cell.id ? Color.accentColor : (store.selectedID == cell.id ? Color.accentColor.opacity(0.45) : .clear),
                lineWidth: 0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
        .glassEffectID(cell.id, in: cellGlassNamespace)
        .magneticDropFeedback(isTargeted: store.dropTargetID == cell.id, cornerRadius: 8)
        .onDrag { store.cellDragProvider(cell.id) }
        .onDrop(of: [cellDragType], delegate: CellDropDelegate(targetID: cell.id, store: store, reduceMotion: reduceMotion))
        .contextMenu {
            CellContextMenu(onDuplicate: {
                NSApp.keyWindow?.makeFirstResponder(nil)
                withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) {
                    if let copyID = store.duplicateCell(cell.id) { store.revealCell(copyID, line: 1) }
                }
            }, onDelete: {
                NSApp.keyWindow?.makeFirstResponder(nil)
                guard !store.runningCellIDs.contains(cell.id) else { return }
                withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { store.removeCell(cell.id) }
            }, deleteEnabled: !store.runningCellIDs.contains(cell.id))
        }
        .help(cellHelp(cell, phase: phase))
        .accessibilityLabel("Cell tab: \(displayName(cell))")
        .accessibilityValue(phase.map { ExecutionIndicator.label(for: $0) } ?? "Idle")
        .accessibilityAddTraits(store.selectedID == cell.id ? [.isSelected] : [])
        .id(cell.id)
    }

    private var tabStrip: some View {
        ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(store.cells) { cell in
                            cellTab(cell)
                        }
                        Button {
                            store.addCell(after: store.selectedID)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .help("Add cell")
                        .accessibilityLabel("Add cell")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: store.cells.map(\.id))
                    .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: store.selectedID)
                    }
                }
                .scrollIndicators(.automatic, axes: .horizontal)
                .onAppear {
                    if let selectedID = store.selectedID {
                        DispatchQueue.main.async { proxy.scrollTo(selectedID, anchor: .center) }
                    }
                }
                .onChange(of: store.selectedID) { _, selectedID in
                    if let selectedID {
                        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { proxy.scrollTo(selectedID, anchor: .center) }
                    }
                }
        }
    }
}
