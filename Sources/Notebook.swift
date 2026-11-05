import SwiftUI
import AppKit
import Combine
import CryptoKit
import CoreFoundation

/// A notebook cell, including its original JSON so fields we do not edit survive a round trip.
struct NotebookCell: Identifiable {
    var id: String
    var cellType: String
    var name: String
    var source: String
    var outputs: [[String: Any]]
    var executionCount: Int?
    var original: [String: Any]

    init(id: String = UUID().uuidString.lowercased(), cellType: String = "code", name: String = "Cell 1", source: String = "", outputs: [[String: Any]] = [], executionCount: Int? = nil, original: [String: Any] = [:]) {
        self.id = id; self.cellType = cellType; self.name = name; self.source = source
        self.outputs = outputs; self.executionCount = executionCount; self.original = original
    }

    var json: [String: Any] {
        var result = original
        result["id"] = id
        result["cell_type"] = cellType
        result["source"] = source
        var metadata = result["metadata"] as? [String: Any] ?? [:]
        metadata["pylab_cell_name"] = name
        result["metadata"] = metadata
        if cellType == "code" {
            result["outputs"] = outputs
            result["execution_count"] = executionCount as Any? ?? NSNull()
        } else {
            result.removeValue(forKey: "outputs")
            result.removeValue(forKey: "execution_count")
        }
        return result
    }
}

struct NotebookRevealRequest: Equatable {
    let cellID: String
    let line: Int
    let token = UUID()
}

/// Owns the in-memory notebook. Jupyter metadata and rich outputs remain in their original JSON form.
final class NotebookStore: ObservableObject {
    @Published var cells: [NotebookCell] = [NotebookCell()]
    @Published var selectedID: String?
    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published var dropTargetID: String?
    @Published var runningCellIDs = Set<String>()
    @Published var cellExecutionActivity: [String: KernelExecutionActivity] = [:]
    @Published var executionTimes: [String: Double] = [:]
    @Published var breakpoints: [String: Set<Int>] = [:]
    @Published var revealRequest: NotebookRevealRequest?

    func revealCell(_ id: String, line: Int) {
        guard cells.contains(where: { $0.id == id }) else { return }
        selectedID = id
        revealRequest = NotebookRevealRequest(cellID: id, line: max(1, line))
    }
    let dragNamespace = UUID().uuidString
    private var document: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": [:]]
    private var savedFingerprint: Data?
    // Runtime display IDs are kernel-session identities, never notebook metadata.
    var displayOutputTargets: [String: [NotebookDisplayTarget]] = [:]
    var displayFigures: [String: LiveFigure] = [:]

    init() { selectedID = cells.first?.id }

    func markDirty() { isDirty = true }
    func toggleBreakpoint(_ id: String, line: Int) {
        guard line > 0 else { return }
        var lines = breakpoints[id] ?? []
        if lines.contains(line) { lines.remove(line) } else { lines.insert(line) }
        breakpoints[id] = lines.isEmpty ? nil : lines
    }

    private static func availableName(_ reserved: Set<String>) -> String {
        var n = 1
        while reserved.contains("cell \(n)".lowercased()) { n += 1 }
        return "Cell \(n)"
    }

    func nextCellName(excluding id: String? = nil) -> String {
        let reserved = Set(cells.filter { $0.id != id }.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return Self.availableName(reserved)
    }

    func renameCell(_ id: String, to requested: String) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = trimmed.isEmpty ? nextCellName(excluding: id) : trimmed
        if cells[index].name != updated { cells[index].name = updated; isDirty = true }
    }

    @discardableResult func addCell(after id: String? = nil) -> String {
        let cell = NotebookCell(name: nextCellName())
        let anchor = id ?? selectedID
        let index = anchor.flatMap { wanted in cells.firstIndex { $0.id == wanted } }.map { $0 + 1 } ?? cells.count
        cells.insert(cell, at: index)
        selectedID = cell.id
        isDirty = true
        return cell.id
    }

    func removeCell(_ id: String) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        removeLiveDisplays(for: id)
        cells.remove(at: index)
        breakpoints[id] = nil
        executionTimes[id] = nil
        runningCellIDs.remove(id)
        cellExecutionActivity[id] = nil
        if revealRequest?.cellID == id { revealRequest = nil }
        endCellDrag()
        if cells.isEmpty { cells.append(NotebookCell()) }
        if selectedID == id || !cells.contains(where: { $0.id == selectedID }) {
            selectedID = cells[min(index, cells.count - 1)].id
        }
        isDirty = true
    }

    private func resetTransientState() {
        resetLiveDisplays()
        endCellDrag()
        runningCellIDs.removeAll()
        cellExecutionActivity.removeAll()
        executionTimes.removeAll()
        breakpoints.removeAll()
        revealRequest = nil
    }

    func newNotebook() {
        resetTransientState()
        document = ["nbformat": 4, "nbformat_minor": 5, "metadata": [:]]
        savedFingerprint = nil
        cells = [NotebookCell()]; selectedID = cells.first?.id; fileURL = nil; isDirty = false
    }

    /// Standardized paths alone do not identify symlink aliases of an open file.
    static func refersToSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        if lhs.standardizedFileURL.resolvingSymlinksInPath() == rhs.standardizedFileURL.resolvingSymlinksInPath() { return true }
        if let left = try? lhs.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject,
           let right = try? rhs.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject {
            return left.isEqual(right)
        }
        return false
    }

    private static func invalidNotebook(_ detail: String) -> NSError {
        NSError(domain: "PyLabNotebook", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "The notebook could not be opened: " + detail + " The current notebook was kept unchanged."])
    }

    private static func validCellID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private static func validExecutionCount(_ value: Any) -> Bool {
        if value is NSNull { return true }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let count = value as? Int, count >= 0 else { return false }
        return number.doubleValue == Double(count)
    }

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["nbformat"] as? Int, version == 4,
              let inputCells = object["cells"] as? [[String: Any]] else {
            throw Self.invalidNotebook("expected Jupyter version 4 with a cells array.")
        }
        if let metadata = object["metadata"], !(metadata is [String: Any]) {
            throw Self.invalidNotebook("notebook metadata must be an object.")
        }
        // Reject malformed editable fields before mutating this store. Converting
        // them to empty text or outputs would silently destroy their data on save.
        for (index, item) in inputCells.enumerated() {
            let label = "cell \(index + 1)"
            guard let kind = item["cell_type"] as? String, ["code", "markdown", "raw"].contains(kind) else {
                throw Self.invalidNotebook(label + " has an unsupported or missing cell type.")
            }
            guard item["source"] is String || item["source"] is [String] else {
                throw Self.invalidNotebook(label + " source must be text or an array of text lines.")
            }
            if let metadata = item["metadata"], !(metadata is [String: Any]) {
                throw Self.invalidNotebook(label + " metadata must be an object.")
            }
            if let outputs = item["outputs"], !(outputs is [[String: Any]]) {
                throw Self.invalidNotebook(label + " outputs must be an array of objects.")
            }
            if let count = item["execution_count"], !Self.validExecutionCount(count) {
                throw Self.invalidNotebook(label + " execution count must be a nonnegative integer or null.")
            }
            if kind != "code", item["outputs"] != nil || item["execution_count"] != nil {
                throw Self.invalidNotebook(label + " contains code outputs but is not a code cell.")
            }
        }
        // Reserve explicit names and IDs first, including IDs that occur later.
        var reserved = Set(inputCells.compactMap { item -> String? in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let value = (metadata["pylab_cell_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value.lowercased()
        })
        var reservedIDs = Set(inputCells.compactMap { $0["id"] as? String }.filter(Self.validCellID))
        var assignedIDs = Set<String>()
        var repairedSuppliedID = false
        let loaded = inputCells.map { item -> NotebookCell in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            var name = (metadata["pylab_cell_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                name = Self.availableName(reserved)
                reserved.insert(name.lowercased())
            }
            var id = item["id"] as? String ?? ""
            if !Self.validCellID(id) || assignedIDs.contains(id) {
                // Missing IDs are normal in older v4 notebooks. Invalid supplied
                // or duplicate IDs need repair so SwiftUI cannot alias editors.
                if item["id"] != nil { repairedSuppliedID = true }
                repeat { id = UUID().uuidString.lowercased() } while reservedIDs.contains(id)
                reservedIDs.insert(id)
            }
            assignedIDs.insert(id)
            return NotebookCell(id: id, cellType: item["cell_type"] as! String, name: name, source: Self.text(item["source"]),
                outputs: item["outputs"] as? [[String: Any]] ?? [],
                executionCount: item["execution_count"] as? Int, original: item)
        }
        resetTransientState()
        document = object
        savedFingerprint = Data(SHA256.hash(data: data))
        cells = loaded.isEmpty ? [NotebookCell()] : loaded
        selectedID = cells.first?.id; fileURL = url; isDirty = repairedSuppliedID
    }

    func save(to url: URL) throws {
        // Build a snapshot first. Failed encoding/writes must leave the source,
        // names, saved path, and dirty state unchanged.
        var snapshot = cells
        var reserved = Set(snapshot.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        for index in snapshot.indices {
            let trimmed = snapshot[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                snapshot[index].name = Self.availableName(reserved)
                reserved.insert(snapshot[index].name.lowercased())
            } else { snapshot[index].name = trimmed }
        }
        var result = document
        result["cells"] = snapshot.map(\.json)
        result["nbformat"] = 4
        if result["nbformat_minor"] == nil { result["nbformat_minor"] = 5 }
        if result["metadata"] == nil { result["metadata"] = [:] }
        // Foundation raises an Objective-C exception for values such as NaN;
        // Swift's `try` cannot catch it. Validate before invoking the writer.
        guard JSONSerialization.isValidJSONObject(result) else {
            throw NSError(domain: "PyLabNotebook", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "This notebook contains a value that cannot be saved as JSON. No file was changed. Clear the affected output or correct the value, then save again."])
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        if let fileURL, let savedFingerprint, Self.refersToSameFile(fileURL, url) {
            let current = try? Data(contentsOf: url)
            guard let current, Data(SHA256.hash(data: current)) == savedFingerprint else {
                throw NSError(domain: "PyLabNotebook", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "This notebook changed, moved, or became unavailable outside PyLab. The file was not overwritten. Use Save As to keep your edits in another file, or reopen the notebook to read its latest version."])
            }
        }
        // Preserve a notebook symlink instead of atomically replacing the link
        // itself with a new regular file.
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
        document = result
        savedFingerprint = Data(SHA256.hash(data: data))
        cells = snapshot
        fileURL = url; isDirty = false
    }

    static func text(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let lines = value as? [String] { return lines.joined() }
        return ""
    }

    func clearOutputs(_ id: String) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        removeLiveDisplays(for: id)
        cells[index].outputs = []; cells[index].executionCount = nil; isDirty = true
    }

    func clearDisplayOutputs(_ id: String) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        removeLiveDisplays(for: id)
        cells[index].outputs = []; isDirty = true
    }

    func appendOutput(_ id: String, output: [String: Any]) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        cells[index].outputs.append(output); isDirty = true
    }

    func setExecutionCount(_ id: String, count: Int?) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        cells[index].executionCount = count; isDirty = true
    }
}

struct NotebookView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: NotebookStore
    let onRun: (String, String) -> Void
    let onComplete: (String, Int, @escaping ([String], NSRange) -> Void) -> Void
    var onRunSelection: ((String, String) -> Void)? = nil
    var singleCell = false
    var editorPreferences: EditorPreferences = .shared
    var onInterrupt: () -> Void = {}

    var body: some View {
        GeometryReader { geometry in
            let layout = NotebookLayout(viewport: geometry.size, singleCell: singleCell)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach($store.cells) { $cell in
                            if !singleCell || store.selectedID == cell.id {
                                NotebookCellView(cell: $cell, layout: layout,
                                    selected: store.selectedID == cell.id,
                                    isRunning: store.runningCellIDs.contains(cell.id), activity: store.cellExecutionActivity[cell.id], elapsed: store.executionTimes[cell.id],
                                    liveFigures: store.liveFigures(for: cell.id),
                                    onSelect: { store.selectedID = cell.id },
                                    onChange: { store.markDirty(); store.breakpoints[cell.id] = nil },
                                    breakpoints: store.breakpoints[cell.id] ?? [],
                                    onToggleBreakpoint: { line in store.toggleBreakpoint(cell.id, line: line) },
                                    onComplete: onComplete,
                                    onRunSelection: onRunSelection.map { action in { text in store.selectedID = cell.id; action(cell.id, text) } },
                                    revealRequest: store.revealRequest,
                                    dragProvider: { store.cellDragProvider(cell.id) },
                                    onRename: { store.renameCell(cell.id, to: $0) },
                                    onRun: { store.selectedID = cell.id; onRun(cell.id, cell.source) },
                                    onAdd: {
                                        let newID = withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { store.addCell(after: cell.id) }
                                        DispatchQueue.main.async { withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { proxy.scrollTo(newID, anchor: .center) } }
                                    },
                                    editorPreferences: editorPreferences, onInterrupt: onInterrupt,
                                    onDuplicate: {
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) {
                                            if let newID = store.duplicateCell(cell.id) { store.revealCell(newID, line: 1) }
                                        }
                                    },
                                    onRemove: {
                                        guard !store.runningCellIDs.contains(cell.id) else { return }
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { store.removeCell(cell.id) }
                                    })
                                .id(cell.id)
                                .transition(.opacity)
                                .magneticDropFeedback(isTargeted: store.dropTargetID == cell.id, cornerRadius: 16, movesContent: false)
                                .onDrop(of: [cellDragType], delegate: CellDropDelegate(targetID: cell.id, store: store, reduceMotion: reduceMotion))
                            }
                        }
                        if !singleCell {
                            Button {
                                let id = withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { store.addCell() }
                                DispatchQueue.main.async { withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .center) } }
                            } label: {
                                Label("Add cell", systemImage: "plus")
                            }.buttonStyle(.bordered).padding(.vertical, 8)
                        }
                    }
                    .padding(layout.outerPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: singleCell)
                }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
                .onChange(of: store.revealRequest) { _, request in
                    if let request { proxy.scrollTo(request.cellID, anchor: .top) }
                }
                .onChange(of: singleCell) { _, _ in
                    guard let selectedID = store.selectedID else { return }
                    // Wait until the newly visible cells have been laid out so
                    // expanding the list keeps the focused cell in view.
                    DispatchQueue.main.async {
                        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(selectedID, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}

/// Convenience for callers that always want the focused presentation.
/// The interactive layout picker uses NotebookView's singleCell value directly
/// so the selected AppKit editor retains its identity during expansion.
struct NotebookSingleCellView: View {
    @ObservedObject var store: NotebookStore
    let onRun: (String, String) -> Void
    let onComplete: (String, Int, @escaping ([String], NSRange) -> Void) -> Void
    var onRunSelection: ((String, String) -> Void)? = nil
    var editorPreferences: EditorPreferences = .shared
    var onInterrupt: () -> Void = {}

    var body: some View {
        NotebookView(store: store, onRun: onRun, onComplete: onComplete,
            onRunSelection: onRunSelection, singleCell: true, editorPreferences: editorPreferences, onInterrupt: onInterrupt)
    }
}

private struct NotebookCellView: View {
    @Binding var cell: NotebookCell
    let layout: NotebookLayout
    let selected: Bool
    let isRunning: Bool
    let activity: KernelExecutionActivity?
    let elapsed: Double?
    let liveFigures: [Int: LiveFigure]
    let onSelect: () -> Void
    let onChange: () -> Void
    let breakpoints: Set<Int>
    let onToggleBreakpoint: (Int) -> Void
    let onComplete: (String, Int, @escaping ([String], NSRange) -> Void) -> Void
    let onRunSelection: ((String) -> Void)?
    let revealRequest: NotebookRevealRequest?
    let dragProvider: () -> NSItemProvider
    let onRename: (String) -> Void
    let onRun: () -> Void
    let onAdd: () -> Void
    let editorPreferences: EditorPreferences
    let onInterrupt: () -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealLine: Int?
    @State private var headerHeight: CGFloat = 30
    @State private var outputsCollapsed = false
    @State private var outputFraction = NotebookLayout.defaultOutputFraction
    @State private var outputDragStart: (fraction: CGFloat, extent: CGFloat)?

    private var executionPhase: KernelExecutionPhase? { activity?.phase ?? (isRunning ? .running : nil) }
    private var isExecuting: Bool { executionPhase == .running || executionPhase == .waitingForInput }
    private var hasOutputs: Bool {
        (cell.cellType == "markdown" && !cell.source.isEmpty) || (cell.cellType == "code" && !cell.outputs.isEmpty)
    }

    var body: some View {
        let sizing = layout.sizing(lineCount: cell.source.split(separator: "\n", omittingEmptySubsequences: false).count,
            headerHeight: headerHeight, hasOutputs: hasOutputs, outputsCollapsed: outputsCollapsed, outputFraction: outputFraction)
        VStack(alignment: .leading, spacing: 10) {
            header
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CellHeaderHeightKey.self, value: geometry.size.height)
                })
            NativeCellEditor(text: $cell.source, isPython: cell.cellType == "code", revealLine: $revealLine, onFocus: onSelect, onRun: onRun, onChange: onChange, breakpoints: breakpoints, onToggleBreakpoint: onToggleBreakpoint, onComplete: onComplete, onRunSelection: onRunSelection,
                onDuplicate: onDuplicate, onDelete: onRemove, deleteEnabled: !isRunning, preferences: editorPreferences)
                .frame(maxWidth: .infinity)
                .frame(height: sizing.editorHeight)
                .background(.background.opacity(0.36), in: RoundedRectangle(cornerRadius: 10))
            if hasOutputs { outputSection(sizing: sizing) }
        }
        .padding(layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: layout.minimumCardHeight, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isExecuting ? Color.orange.opacity(0.85) : selected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.09), lineWidth: isExecuting ? 1.6 : selected ? 1.3 : 0.7)
                .animation(LiquidMotion.feedback(reduceMotion: reduceMotion), value: selected)
        }
        .onPreferenceChange(CellHeaderHeightKey.self) { if abs(headerHeight - $0) > 0.5 { headerHeight = $0 } }
        .onChange(of: hasOutputs) { _, _ in outputDragStart = nil }
        .onChange(of: outputsCollapsed) { _, _ in outputDragStart = nil }
        .onChange(of: layout.singleCell) { _, _ in outputDragStart = nil }
        .onTapGesture { onSelect() }
        .contextMenu { CellContextMenu(onDuplicate: onDuplicate, onDelete: onRemove, deleteEnabled: !isRunning) }
        .onAppear { if let request = revealRequest, request.cellID == cell.id { revealLine = request.line } }
        .onChange(of: revealRequest) { _, request in
            if let request, request.cellID == cell.id { revealLine = request.line }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                dragHandle
                nameField.frame(minWidth: 90, idealWidth: 150, maxWidth: 190)
                executionLabel
                typePicker
                Spacer(minLength: 4)
                runStatus
                cellActions(compact: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    dragHandle
                    nameField.frame(minWidth: 55, maxWidth: .infinity)
                    cellActions(compact: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        executionLabel
                        typePicker
                        Spacer(minLength: 0)
                        runStatus
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) { executionLabel; typePicker; Spacer(minLength: 0) }
                        runStatus
                    }
                }
            }
        }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .padding(5)
            .contentShape(Rectangle())
            .onDrag(dragProvider)
            .help("Drag to reorder this cell")
            .accessibilityLabel("Drag to reorder cell")
    }
    private var nameField: some View {
        TextField("Cell name", text: Binding(get: { cell.name }, set: { value in if cell.name != value { cell.name = value; onChange() } }))
            .textFieldStyle(.roundedBorder)
            .font(.callout.weight(.medium))
            .focused($nameFocused)
            .accessibilityLabel("Cell name")
            .help("Name this cell")
            .onSubmit { onRename(cell.name) }
            .onChange(of: nameFocused) { _, focused in if focused { onSelect() } else { onRename(cell.name) } }
    }
    private var executionLabel: some View {
        Text(cell.cellType == "code" ? (isExecuting ? "In [*]" : "In [\(cell.executionCount.map(String.init) ?? " ")]") : "TEXT")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
    private var typePicker: some View {
        Picker("Cell type", selection: $cell.cellType) {
            Text("Code").tag("code"); Text("Markdown").tag("markdown"); Text("Raw").tag("raw")
        }.labelsHidden().frame(width: 112).disabled(isRunning || activity != nil).onChange(of: cell.cellType) { _, _ in onChange() }
    }
    @ViewBuilder private var runStatus: some View {
        if let executionPhase {
            ExecutionIndicator(phase: executionPhase, startedAt: activity?.startedAt)
        } else if let elapsed {
            Text(String(format: "Last run %.2f s", elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }
    private func cellActions(compact: Bool) -> some View {
        HStack(spacing: 7) {
            if isExecuting {
                Button(action: onInterrupt) { Label("Stop", systemImage: "stop.fill").labelStyle(compact ? AnyCellLabelStyle.icon : AnyCellLabelStyle.titleAndIcon) }
                    .buttonStyle(.bordered).tint(.red).controlSize(.small)
                    .help("Interrupt running code in this project's kernel")
                    .accessibilityLabel("Stop running cell")
            } else {
                Button(action: onRun) { Label("Run", systemImage: "play.fill").labelStyle(compact ? AnyCellLabelStyle.icon : AnyCellLabelStyle.titleAndIcon) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(isRunning || activity != nil)
                    .help(executionPhase == .queued ? "This cell is queued" : "Run cell · Shift-Return")
                    .accessibilityLabel("Run cell")
            }
            Button(action: onAdd) { Image(systemName: "plus") }.help("Add cell below").accessibilityLabel("Add cell below")
            Button(action: onRemove) { Image(systemName: "trash") }.help(isRunning ? "Wait for this cell to finish before deleting it" : "Remove cell").accessibilityLabel("Remove cell").disabled(isRunning)
        }.controlSize(.small).fixedSize()
    }
    private func outputSection(sizing: NotebookCellSizing) -> some View {
        VStack(spacing: 0) {
            if layout.singleCell && !outputsCollapsed { outputResizeHandle(sizing: sizing) }
            CellOutputPane(outputs: cell.cellType == "code" ? cell.outputs : [],
                markdown: cell.cellType == "markdown" ? cell.source : nil, cellName: cell.name,
                contentHeight: sizing.outputContentHeight, collapsed: $outputsCollapsed, liveFigures: liveFigures,
                onGoToLine: { line in revealLine = line })
            if !layout.singleCell && !outputsCollapsed { outputResizeHandle(sizing: sizing) }
        }
    }
    private func outputResizeHandle(sizing: NotebookCellSizing) -> some View {
        PaneResizeHandle(vertical: false, label: layout.singleCell ? "Resize code and output" : "Resize output area")
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if outputDragStart == nil { outputDragStart = (sizing.outputPaneHeight / sizing.resizeExtent, sizing.resizeExtent) }
                    guard let start = outputDragStart else { return }
                    let direction: CGFloat = layout.singleCell ? -1 : 1
                    outputFraction = NotebookLayout.clampedOutputFraction(start.fraction + direction * value.translation.height / start.extent)
                }
                .onEnded { _ in outputDragStart = nil })
            .accessibilityValue("\(Int(sizing.outputPaneHeight / sizing.resizeExtent * 100)) percent output")
            .accessibilityAdjustableAction { direction in
                withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) {
                    let current = sizing.outputPaneHeight / sizing.resizeExtent
                    switch direction {
                    case .increment: outputFraction = NotebookLayout.clampedOutputFraction(current + 0.05)
                    case .decrement: outputFraction = NotebookLayout.clampedOutputFraction(current - 0.05)
                    @unknown default: break
                    }
                }
            }
            .contextMenu {
                Button("More Space for Code") { setOutputFraction(0.20) }
                Button("Default Split") { setOutputFraction(NotebookLayout.defaultOutputFraction) }
                Button("More Space for Output") { setOutputFraction(0.48) }
            }
    }
    private func setOutputFraction(_ fraction: CGFloat) {
        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { outputFraction = fraction }
    }

}

private enum AnyCellLabelStyle: LabelStyle {
    case icon, titleAndIcon
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            if self == .titleAndIcon { configuration.title }
        }
    }
}
private struct CellHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct NativeCellEditor: NSViewRepresentable {
    @Binding var text: String
    let isPython: Bool
    @Binding var revealLine: Int?
    @Environment(\.colorScheme) private var colorScheme
    let onFocus: () -> Void
    let onRun: () -> Void
    let onChange: () -> Void
    let breakpoints: Set<Int>
    let onToggleBreakpoint: (Int) -> Void
    let onComplete: (String, Int, @escaping ([String], NSRange) -> Void) -> Void
    let onRunSelection: ((String) -> Void)?
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let deleteEnabled: Bool
    @ObservedObject var preferences: EditorPreferences

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        // Native subviews must not paint outside the SwiftUI cell when nested scroll views move.
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        let editor = CellTextView()
        editor.isRichText = false; editor.allowsUndo = true; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.font = .monospacedSystemFont(ofSize: preferences.fontSize, weight: .regular)
        editor.isPython = isPython
        editor.showIndentGuides = isPython && preferences.showsIndentGuides
        editor.textColor = .textColor; editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onRun = { context.coordinator.parent.onRun() }
        editor.onDuplicateCell = { context.coordinator.parent.onDuplicate() }
        editor.onDeleteCell = { context.coordinator.parent.onDelete() }
        editor.canDeleteCell = { context.coordinator.parent.deleteEnabled }
        editor.onRunSelection = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }; coordinator?.runSelection(editor)
        }
        editor.canRunSelection = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor, let coordinator else { return false }
            return coordinator.parent.isPython && coordinator.parent.onRunSelection != nil && editor.selectedRange().length > 0
        }
        editor.onEditingCommand = { [weak editor, weak coordinator = context.coordinator] command in
            guard let editor else { return false }; return coordinator?.edit(command, editor: editor) ?? false
        }
        editor.onComplete = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }; coordinator?.showCompletions(editor)
        }
        editor.onFocus = { context.coordinator.parent.onFocus() }
        editor.onAppearanceChanged = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.textColor = .textColor
            editor.insertionPointColor = .textColor
            editor.needsDisplay = true
            editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            coordinator?.scheduleHighlight(editor, immediately: true)
        }
        scroll.documentView = editor
        let ruler = CodeRulerView(scrollView: scroll, orientation: .verticalRuler)
        ruler.clientView = editor
        ruler.ruleThickness = 50
        ruler.wantsLayer = true
        ruler.layer?.masksToBounds = true
        ruler.editorCoordinator = context.coordinator
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = isPython && preferences.showsLineNumbers
        context.coordinator.appliedStyle = preferences.style
        context.coordinator.source = text
        editor.string = text
        context.coordinator.scheduleHighlight(editor, immediately: true)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? CellTextView else { return }
        let styleChanged = context.coordinator.applyPreferences(editor, scroll: scroll)
        editor.isPython = isPython
        editor.showIndentGuides = isPython && preferences.showsIndentGuides
        if !isPython && !context.coordinator.folded.isEmpty {
            context.coordinator.folded.removeAll()
            context.coordinator.render(editor)
        }
        let textChanged = context.coordinator.source != text
        if textChanged {
            context.coordinator.source = text
            context.coordinator.folded.removeAll()
            context.coordinator.render(editor)
        }
        if let ruler = scroll.verticalRulerView {
            ruler.ruleThickness = ruler.requiredThickness
            ruler.needsDisplay = true
        }
        if let line = revealLine {
            if !context.coordinator.folded.isEmpty { context.coordinator.folded.removeAll(); context.coordinator.render(editor) }
            let source = editor.string as NSString
            var position = 0, current = 1
            while current < line && position < source.length {
                position = NSMaxRange(source.lineRange(for: NSRange(location: position, length: 0))); current += 1
            }
            editor.setSelectedRange(NSRange(location: min(position, source.length), length: 0))
            editor.scrollRangeToVisible(editor.selectedRange())
            editor.window?.makeFirstResponder(editor)
            DispatchQueue.main.async { if self.revealLine == line { self.revealLine = nil } }
        }
        context.coordinator.scheduleHighlight(editor, immediately: textChanged || styleChanged)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeCellEditor
        private var pendingHighlight: DispatchWorkItem?
        var appliedStyle: EditorStyle?
        private var applyingStyle = false
        @discardableResult func applyPreferences(_ editor: CellTextView, scroll: NSScrollView) -> Bool {
            let style = parent.preferences.style
            let changed = style != appliedStyle
            let showRuler = parent.isPython && style.showsLineNumbers
            if scroll.rulersVisible != showRuler { scroll.rulersVisible = showRuler }
            guard changed else { return false }
            if appliedStyle?.fontSize != style.fontSize {
                let selection = editor.selectedRanges
                let undo = editor.undoManager
                let wasEnabled = undo?.isUndoRegistrationEnabled == true
                if wasEnabled { undo?.disableUndoRegistration() }
                applyingStyle = true
                editor.font = .monospacedSystemFont(ofSize: style.fontSize, weight: .regular)
                editor.typingAttributes[.font] = editor.font
                applyingStyle = false
                if wasEnabled { undo?.enableUndoRegistration() }
                if editor.selectedRanges != selection { editor.selectedRanges = selection }
                editor.enclosingScrollView?.needsLayout = true
            }
            appliedStyle = style
            editor.needsDisplay = true
            scroll.verticalRulerView?.needsDisplay = true
            return true
        }
        var source = "" {
            didSet {
                regions = PythonFolding.regions(in: source)
                let text = source as NSString
                lineStarts = [0]
                if text.length > 0 {
                    for index in 0..<text.length where text.character(at: index) == 10 { lineStarts.append(index + 1) }
                }
            }
        }
        private var regions: [PythonFoldRegion] = []
        private var lineStarts: [Int] = [0]
        var sourceLineCount: Int { lineStarts.count }
        var folded = Set<Int>()
        private struct Replacement { let display: NSRange; let original: NSRange }
        private var replacements: [Replacement] = []
        init(_ parent: NativeCellEditor) { self.parent = parent }

        func sourceLocation(_ displayLocation: Int) -> Int {
            var offset = 0
            for item in replacements {
                if displayLocation < item.display.location { break }
                if displayLocation < NSMaxRange(item.display) { return item.original.location }
                offset += item.original.length - item.display.length
            }
            return min((source as NSString).length, max(0, displayLocation + offset))
        }
        func lineNumber(_ displayLocation: Int) -> Int {
            let location = sourceLocation(displayLocation)
            var low = 0, high = lineStarts.count
            while low < high {
                let middle = (low + high) / 2
                if lineStarts[middle] <= location { low = middle + 1 } else { high = middle }
            }
            return max(1, low)
        }
        func region(at displayLocation: Int) -> PythonFoldRegion? {
            let original = sourceLocation(displayLocation)
            let header = (source as NSString).lineRange(for: NSRange(location: min(original, (source as NSString).length), length: 0)).location
            return regions.first { $0.header == header }
        }
        func toggleFold(at displayLocation: Int, editor: CellTextView) {
            guard let region = region(at: displayLocation) else { return }
            if folded.contains(region.header) { folded.remove(region.header) } else { folded.insert(region.header) }
            render(editor)
            scheduleHighlight(editor, immediately: true)
        }
        func render(_ editor: CellTextView) {
            let sourceText = source as NSString
            let regions = regions.filter { folded.contains($0.header) }.sorted { $0.body.location < $1.body.location }
            let result = NSMutableString(string: "")
            replacements = []
            var cursor = 0
            for region in regions where region.body.location >= cursor {
                result.append(sourceText.substring(with: NSRange(location: cursor, length: region.body.location - cursor)))
                let displayStart = result.length
                let headerRange = sourceText.lineRange(for: NSRange(location: region.header, length: 0))
                let header = sourceText.substring(with: headerRange)
                let indent = String(header.prefix { $0 == " " || $0 == "\t" })
                let marker = indent + "    ⋯\n"
                result.append(marker)
                replacements.append(Replacement(display: NSRange(location: displayStart, length: (marker as NSString).length), original: region.body))
                cursor = NSMaxRange(region.body)
            }
            result.append(sourceText.substring(from: cursor))
            editor.string = result as String
            editor.needsDisplay = true
            editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
        func runSelection(_ editor: CellTextView) {
            guard parent.isPython, let action = parent.onRunSelection, editor.selectedRange().length > 0 else {
                parent.onRun(); return
            }
            let selected = editor.selectedRange()
            let start = sourceLocation(selected.location), end = sourceLocation(NSMaxRange(selected))
            guard end > start else { return }
            let code = PythonEditing.executableSelection((source as NSString).substring(with: NSRange(location: start, length: end - start)))
            if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { action(code) }
        }
        func edit(_ command: PythonEditing.Command, editor: CellTextView) -> Bool {
            guard parent.isPython, !editor.hasMarkedText() else { return false }
            var selected = editor.selectedRange()
            if !folded.isEmpty {
                let start = sourceLocation(selected.location), end = sourceLocation(NSMaxRange(selected))
                folded.removeAll(); render(editor)
                selected = NSRange(location: start, length: max(0, end - start))
                editor.setSelectedRange(selected)
            }
            guard let edit = PythonEditing.edit(command, in: source, selection: selected) else { return true }
            editor.insertText(edit.text, replacementRange: edit.range)
            editor.setSelectedRange(edit.selection)
            editor.scrollRangeToVisible(edit.selection)
            return true
        }
        private var completionRange = NSRange(location: 0, length: 0)
        private var completionSnapshot = ""
        private weak var completionEditor: CellTextView?
        func showCompletions(_ editor: CellTextView) {
            guard parent.isPython, folded.isEmpty, !editor.hasMarkedText(), editor.selectedRange().length == 0 else { return }
            let code = source, cursor = editor.selectedRange().location
            parent.onComplete(code, cursor) { [weak self, weak editor] matches, range in
                guard let self, let editor, self.source == code, editor.selectedRange().location == cursor,
                      !matches.isEmpty, NSMaxRange(range) <= (code as NSString).length,
                      let window = editor.window else { return }
                self.completionRange = range; self.completionSnapshot = code; self.completionEditor = editor
                let menu = NSMenu(title: "Completions")
                for value in matches.prefix(50) {
                    let item = NSMenuItem(title: value, action: #selector(self.insertCompletion(_:)), keyEquivalent: "")
                    item.target = self; item.representedObject = value; menu.addItem(item)
                }
                let screenRect = editor.firstRect(forCharacterRange: NSRange(location: cursor, length: 0), actualRange: nil)
                let localPoint = editor.convert(window.convertPoint(fromScreen: screenRect.origin), from: nil)
                menu.popUp(positioning: nil, at: NSPoint(x: localPoint.x, y: localPoint.y + screenRect.height), in: editor)
            }
        }
        @objc private func insertCompletion(_ sender: NSMenuItem) {
            guard let value = sender.representedObject as? String, let editor = completionEditor,
                  source == completionSnapshot, NSMaxRange(completionRange) <= (source as NSString).length else { return }
            editor.insertText(value, replacementRange: completionRange)
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !folded.isEmpty, let replacementString, let editor = textView as? CellTextView else { return true }
            let touchesHidden = replacements.contains { item in
                if affectedCharRange.length == 0 { return affectedCharRange.location >= item.display.location && affectedCharRange.location < NSMaxRange(item.display) }
                return NSIntersectionRange(affectedCharRange, item.display).length > 0
            }
            let start = sourceLocation(affectedCharRange.location)
            let end = sourceLocation(NSMaxRange(affectedCharRange))
            folded.removeAll()
            render(editor)
            if touchesHidden {
                editor.setSelectedRange(NSRange(location: start, length: 0))
                NSSound.beep()
            } else {
                editor.insertText(replacementString, replacementRange: NSRange(location: start, length: max(0, end - start)))
            }
            scheduleHighlight(editor, immediately: true)
            return false
        }
        func textDidChange(_ notification: Notification) {
            guard !applyingStyle else { return }
            guard let editor = notification.object as? CellTextView else { return }
            source = editor.string
            if parent.text != source {
                parent.text = source
                parent.onChange()
            }
            editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            editor.needsDisplay = true
            scheduleHighlight(editor)
        }
        func scheduleHighlight(_ editor: CellTextView, immediately: Bool = false) {
            pendingHighlight?.cancel()
            let task = DispatchWorkItem { [weak self, weak editor] in
                guard let self, let editor else { return }
                if editor.hasMarkedText() { self.scheduleHighlight(editor); return }
                self.highlight(editor)
            }
            pendingHighlight = task
            DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.12), execute: task)
        }
        private func highlight(_ editor: CellTextView) {
            guard let layout = editor.layoutManager else { return }
            let text = editor.string
            let full = NSRange(location: 0, length: (text as NSString).length)
            guard full.length > 0 else { return }
            // Layout-manager temporary attributes do not modify document text, create
            // undo entries, move the cursor, or trigger an unsaved-document change.
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            guard parent.isPython else { return }
            let dark = editor.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            for token in PythonSyntax.tokens(in: text) {
                layout.addTemporaryAttribute(.foregroundColor, value: parent.preferences.palette.color(token.kind, dark: dark), forCharacterRange: token.range)
            }
        }

    }
}

/// The window menu can receive Command-Return before AppKit asks the text view.
/// Route that command through the focused editor's own source mapping first.
@MainActor
func runFocusedCodeSelection() -> Bool {
    guard let editor = NSApp.keyWindow?.firstResponder as? CellTextView,
          editor.canRunSelection?() == true else { return false }
    editor.onRunSelection?()
    return true
}

private final class CellTextView: NSTextView {
    var onRun: (() -> Void)?
    var onDuplicateCell: (() -> Void)?
    var onDeleteCell: (() -> Void)?
    var canDeleteCell: (() -> Bool)?
    var onRunSelection: (() -> Void)?
    var canRunSelection: (() -> Bool)?
    var onEditingCommand: ((PythonEditing.Command) -> Bool)?
    var onComplete: (() -> Void)?
    var onFocus: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?
    var isPython = true
    var showIndentGuides = true

    /// One entry per visual line, in the text view's coordinate system.
    func visibleLineFragments() -> [(NSRange, NSRect)] {
        guard let layoutManager, let textContainer else { return [] }
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        var lines: [(NSRange, NSRect)] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, range, _ in
            let chars = layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            lines.append((chars, used.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)))
        }
        return lines
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showIndentGuides, let font else { return }
        let source = string as NSString
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        NSColor.secondaryLabelColor.withAlphaComponent(0.23).setStroke()
        let path = NSBezierPath(); path.lineWidth = 0.6
        for (range, rect) in visibleLineFragments() where range.location < source.length {
            let line = source.lineRange(for: NSRange(location: range.location, length: 0))
            guard line.location == range.location else { continue }
            var count = 0, position = line.location
            while position < NSMaxRange(line) {
                let c = source.character(at: position)
                if c == 32 { count += 1 } else if c == 9 { count += 4 - count % 4 } else { break }
                position += 1
            }
            if count >= 4 {
                for column in stride(from: 4, through: count, by: 4) {
                    let x = textContainerOrigin.x + 5 + CGFloat(column - 1) * spaceWidth
                    path.move(to: NSPoint(x: x, y: rect.minY)); path.line(to: NSPoint(x: x, y: rect.maxY))
                }
            }
        }
        path.stroke()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocus?() }
        redrawGutter()
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        redrawGutter()
        return result
    }
    private func redrawGutter() {
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        DispatchQueue.main.async { [weak self] in
            self?.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 36 || event.keyCode == 76) && flags == .command {
            onRunSelection?(); return true
        }
        if event.charactersIgnoringModifiers == "/" && flags == .command {
            return onEditingCommand?(.toggleComment) ?? false
        }
        return false
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if handleShortcut(event) { return }
        if event.keyCode == 49 && event.modifierFlags.contains(.control) { onComplete?(); return }
        if (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.shift) {
            onRun?(); return
        }
        super.keyDown(with: event)
    }
    override func insertNewline(_ sender: Any?) {
        if onEditingCommand?(.newline) != true { super.insertNewline(sender) }
    }
    override func insertTab(_ sender: Any?) {
        if onEditingCommand?(.indent) != true { super.insertTab(sender) }
    }
    override func insertBacktab(_ sender: Any?) {
        if onEditingCommand?(.outdent) != true { super.insertBacktab(sender) }
    }
    @objc private func duplicateCurrentCell(_ sender: Any?) { onDuplicateCell?() }
    @objc private func deleteCurrentCell(_ sender: Any?) {
        guard canDeleteCell?() == true else { return }
        onDeleteCell?()
    }
    @objc private func runSelectedCode(_ sender: Any?) { onRunSelection?() }
    @objc private func toggleSelectedComments(_ sender: Any?) { _ = onEditingCommand?(.toggleComment) }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        // NSTextView can reuse its editing menu. Replace only PyLab entries so
        // repeated right-clicks preserve standard Copy/Paste without duplicates.
        for item in menu.items where item.identifier?.rawValue.hasPrefix("pylab.editor.") == true { menu.removeItem(item) }
        let duplicate = NSMenuItem(title: "Duplicate Cell", action: #selector(duplicateCurrentCell(_:)), keyEquivalent: "")
        duplicate.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        duplicate.target = self
        let delete = NSMenuItem(title: "Delete Cell", action: #selector(deleteCurrentCell(_:)), keyEquivalent: "")
        delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        delete.target = self; delete.isEnabled = canDeleteCell?() ?? false
        let run = NSMenuItem(title: "Run Selection", action: #selector(runSelectedCode(_:)), keyEquivalent: "")
        run.target = self; run.isEnabled = canRunSelection?() ?? false
        let comment = NSMenuItem(title: "Toggle Line Comment", action: #selector(toggleSelectedComments(_:)), keyEquivalent: "")
        comment.target = self
        let entries = [duplicate, delete, NSMenuItem.separator(), run, comment, NSMenuItem.separator()]
        for (index, item) in entries.enumerated() {
            item.identifier = NSUserInterfaceItemIdentifier("pylab.editor." + String(index))
            menu.insertItem(item, at: index)
        }
        return menu
    }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(duplicateCurrentCell(_:)) { return onDuplicateCell != nil }
        if menuItem.action == #selector(deleteCurrentCell(_:)) { return canDeleteCell?() ?? false }
        if menuItem.action == #selector(runSelectedCode(_:)) { return canRunSelection?() ?? false }
        if menuItem.action == #selector(toggleSelectedComments(_:)) { return isPython }
        return super.validateMenuItem(menuItem)
    }
}


private final class CodeRulerView: NSRulerView {
    weak var editorCoordinator: NativeCellEditor.Coordinator?
    private var scrollObservers: [NSObjectProtocol] = []
    deinit { scrollObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshScrollObservers()
        needsDisplay = true
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        DispatchQueue.main.async { [weak self] in self?.refreshScrollObservers() }
    }
    private func refreshScrollObservers() {
        scrollObservers.forEach { NotificationCenter.default.removeObserver($0) }
        scrollObservers.removeAll()
        // The editor can move inside both its own clip view and the notebook's
        // outer scroll view. Redraw after either viewport moves.
        var ancestor: NSView? = self
        while let view = ancestor {
            if let clip = view as? NSClipView {
                clip.postsBoundsChangedNotifications = true
                scrollObservers.append(NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self] _ in self?.needsDisplay = true })
            }
            ancestor = view.superview
        }
        if let clip = scrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObservers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in self?.needsDisplay = true })
        }
        needsDisplay = true
    }
    override var isFlipped: Bool { true }
    override var requiredThickness: CGFloat {
        guard let editor = clientView as? CellTextView else { return 50 }
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, (editor.font?.pointSize ?? 13) - 2), weight: .regular)
        let digits = max(3, String(editorCoordinator?.sourceLineCount ?? 1).count)
        return max(50, ceil(("0" as NSString).size(withAttributes: [.font: font]).width * CGFloat(digits)) + 30)
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor = clientView as? CellTextView, let coordinator = editorCoordinator else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // AppKit rulers can be asked to redraw for offscreen document lines. Clip
        // explicitly to the editor viewport, including when the cell itself scrolls.
        guard let clipView = scrollView?.contentView else { return }
        let viewport = convert(clipView.bounds, from: clipView)
        let verticalViewport = NSRect(x: bounds.minX, y: viewport.minY, width: bounds.width, height: viewport.height)
        let drawingBounds = bounds.intersection(verticalViewport)
        guard !drawingBounds.isNull, !drawingBounds.isEmpty else { return }
        NSBezierPath(rect: drawingBounds).addClip()
        let background = editor.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)
        background.setFill(); bounds.fill()
        let style = NSMutableParagraphStyle(); style.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: max(9, (editor.font?.pointSize ?? 13) - 2), weight: .regular), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style]
        for (range, lineRect) in editor.visibleLineFragments() {
            let text = editor.string as NSString
            guard range.location <= text.length else { continue }
            let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
            guard range.location == lineStart else { continue }
            let y = convert(lineRect.origin, from: editor).y
            guard y + lineRect.height >= drawingBounds.minY && y <= drawingBounds.maxY else { continue }
            let lineNumber = coordinator.lineNumber(range.location)
            if coordinator.parent.breakpoints.contains(lineNumber) {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: NSRect(x: 1, y: y + max(0, (lineRect.height - 7) / 2), width: 7, height: 7)).fill()
            }
            let number = String(lineNumber) as NSString
            number.draw(in: NSRect(x: 8, y: y, width: max(0, bounds.width - 30), height: lineRect.height), withAttributes: attributes)
            if let region = coordinator.region(at: range.location) {
                let symbol = coordinator.folded.contains(region.header) ? "▸" : "▾"
                (symbol as NSString).draw(in: NSRect(x: bounds.width - 18, y: y - 1, width: 15, height: lineRect.height + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let editor = clientView as? CellTextView, let coordinator = editorCoordinator else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let clipView = scrollView?.contentView else { return }
        let viewport = convert(clipView.bounds, from: clipView)
        guard point.y >= viewport.minY && point.y <= viewport.maxY else { return }
        let editorPoint = editor.convert(point, from: self)
        if let (range, _) = editor.visibleLineFragments().first(where: { editorPoint.y >= $0.1.minY && editorPoint.y <= $0.1.maxY }) {
            if point.x >= bounds.width - 22 { coordinator.toggleFold(at: range.location, editor: editor) }
            else { coordinator.parent.onToggleBreakpoint(coordinator.lineNumber(range.location)); needsDisplay = true }
        }
    }
}
