import SwiftUI

/// Compact variable table grouped by the cell that last assigned each value.
struct WorkspacePane: View {
    let variables: [WorkspaceVariable]
    let cellNames: [String: String]
    let cellOrder: [String]
    let onRefresh: () -> Void
    let onOpen: (WorkspaceVariable) -> Void
    let onSave: (WorkspaceVariable) -> Void
    let onPlot: (WorkspaceVariable) -> Void
    let onInspect: (WorkspaceVariable, @escaping (VariableStatistics?, String?) -> Void) -> Void
    let onRename: (WorkspaceVariable, String, @escaping (String?) -> Void) -> Void
    let onDelete: (WorkspaceVariable, @escaping (String?) -> Void) -> Void
    var actionsEnabled = true
    var variableMode: VariableSharingMode = .shared
    var onVariableModeChange: (VariableSharingMode) -> Void = { _ in }
    var modeChangeEnabled = true
    @State private var search = ""
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\WorkspaceVariable.name)]
    @StateObject private var inspection = WorkspaceInspectionModel()
    @State private var showInspection = false
    @State private var renameTarget: WorkspaceVariable?
    @State private var renamedName = ""
    @State private var deleteTarget: WorkspaceVariable?
    @State private var actionError: String?
    @State private var actionPending = false

    private struct Group: Identifiable {
        let id: String
        let title: String
        var rows: [WorkspaceVariable]
    }

    private func origin(_ variable: WorkspaceVariable) -> (id: String, title: String) {
        guard let id = variable.scopeID ?? variable.originID else { return ("untracked", "Other / untracked") }
        if id == "internal:console" { return ("console", "Console") }
        guard let name = cellNames[id] else { return ("deleted:" + id, "Other / deleted cell") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ("cell:" + id, trimmed.isEmpty ? "Untitled Cell" : trimmed)
    }

    private var filtered: [WorkspaceVariable] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = query.isEmpty ? variables : variables.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.type.localizedCaseInsensitiveContains(query) ||
            $0.value.localizedCaseInsensitiveContains(query) ||
            $0.shape.localizedCaseInsensitiveContains(query) ||
            origin($0).title.localizedCaseInsensitiveContains(query)
        }
        return rows.sorted(using: sortOrder)
    }

    private var groups: [Group] {
        var grouped: [String: Group] = [:]
        for variable in filtered {
            let source = origin(variable)
            if grouped[source.id] == nil { grouped[source.id] = Group(id: source.id, title: source.title, rows: []) }
            grouped[source.id]?.rows.append(variable)
        }
        var order: [String: Int] = [:]
        for (index, id) in cellOrder.enumerated() where order["cell:" + id] == nil {
            order["cell:" + id] = index
        }
        order["console"] = cellOrder.count
        order["deleted"] = cellOrder.count + 1
        order["untracked"] = cellOrder.count + 2
        return grouped.values.sorted {
            let left = order[$0.id, default: Int.max], right = order[$1.id, default: Int.max]
            return left == right ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : left < right
        }
    }

    private func displaySize(_ variable: WorkspaceVariable) -> String {
        guard !variable.shape.isEmpty else { return "—" }
        let shape = variable.shape.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        let dims = shape.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return dims.isEmpty ? variable.shape : dims.joined(separator: " × ")
    }

    private func displayValue(_ variable: WorkspaceVariable) -> String {
        if variable.editable && (variable.value.isEmpty || variable.value == "<table>") {
            return "\(displaySize(variable)) \(variable.type)"
        }
        return variable.value
    }

    private func openSelected() {
        if let selection, let variable = filtered.first(where: { $0.id == selection }), variable.editable {
            onOpen(variable)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                workspaceHeader(compact: false)
                workspaceHeader(compact: true)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search workspace", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Clear search")
                }
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10).padding(.bottom, 8)

            if variables.isEmpty {
                ContentUnavailableView("Workspace is empty", systemImage: "tablecells", description: Text("Run a cell or command to see variables."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(of: WorkspaceVariable.self, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { variable in
                        HStack(spacing: 4) {
                            Image(systemName: variable.editable ? "tablecells" : "number.square")
                                .font(.system(size: 10))
                                .foregroundStyle(variable.editable ? Color.accentColor : Color.secondary)
                            Text(variable.name).lineLimit(1)
                        }
                        .font(.system(size: 11)).help(variable.name)
                    }.width(min: 65, ideal: 100)
                    TableColumn("Value", value: \.value) { variable in
                        Text(displayValue(variable)).font(.system(size: 11)).lineLimit(1)
                            .help(displayValue(variable))
                    }.width(min: 65, ideal: 100)
                    TableColumn("Size", value: \.shape) { variable in
                        Text(displaySize(variable)).font(.system(size: 11)).lineLimit(1)
                            .help(variable.shape)
                    }.width(min: 45, ideal: 65)
                    TableColumn("Class", value: \.type) { variable in
                        Text(variable.type).font(.system(size: 11)).lineLimit(1)
                            .help(variable.type)
                    }.width(min: 48, ideal: 65)
                } rows: {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.rows) { variable in TableRow(variable) }
                        }
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let variable = variables.first(where: { $0.id == id }) {
                        if variable.editable { Button("Open Variable") { onOpen(variable) } }
                        if variable.savable { Button("Save As…") { onSave(variable) } }
                        if variable.plottable { Button("Plot") { onPlot(variable) } }
                        Divider()
                        Button("Inspect Statistics…") { inspect(variable) }.disabled(!actionsEnabled || actionPending)
                        Button("Rename…") { renamedName = variable.name; renameTarget = variable }.disabled(!actionsEnabled || actionPending)
                        Button("Delete Variable…", role: .destructive) { deleteTarget = variable }.disabled(!actionsEnabled || actionPending)
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let variable = variables.first(where: { $0.id == id }), variable.editable {
                        onOpen(variable)
                    }
                }
                .accessibilityLabel("Workspace variables")
            }
            Divider()
            HStack(spacing: 5) {
                Text("\(variables.count) variables")
                Spacer()
                if let selected = variables.first(where: { $0.id == selection }), selected.editable {
                    Button("Open") { openSelected() }.buttonStyle(.link)
                        .help("Open the selected variable editor")
                } else {
                    Text("Right-click for actions")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(minWidth: 235, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showInspection) {
            VariableStatisticsView(model: inspection)
        }
        .alert("Rename Variable", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }), presenting: renameTarget) { target in
            TextField("Python variable name", text: $renamedName)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                let newName = renamedName.trimmingCharacters(in: .whitespacesAndNewlines)
                actionPending = true
                onRename(target, newName) { error in
                    actionPending = false
                    if let error { actionError = error } else { selection = nil }
                }
                renameTarget = nil
            }
        } message: { _ in Text("This changes the live workspace name. Update references in your code yourself; notebook code is unchanged.") }
        .alert("Delete \(deleteTarget?.name ?? "variable")?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { target in
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete Variable", role: .destructive) {
                actionPending = true
                onDelete(target) { error in
                    actionPending = false
                    if let error { actionError = error }
                    else if selection == target.id { selection = nil }
                }
                deleteTarget = nil
            }
        } message: { _ in Text("This removes the name from the live Python workspace. Other references to the same value remain. Run your code again to recreate it.") }
        .alert("Workspace", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }), presenting: actionError) { _ in
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text($0) }
    }

    private func workspaceHeader(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Workspace").font(.headline).fixedSize()
            Spacer(minLength: 4)
            variableSharingMenu(compact: compact)
            Text("\(filtered.count) of \(variables.count)")
                .font(.caption).foregroundStyle(.secondary).fixedSize()
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.glass).controlSize(.small)
                .help("Refresh workspace").accessibilityLabel("Refresh workspace")
        }
    }

    private func variableSharingMenu(compact: Bool) -> some View {
        Menu {
            ForEach(VariableSharingMode.allCases) { mode in
                Button { onVariableModeChange(mode) } label: {
                    Label(mode.title, systemImage: mode == variableMode ? "checkmark" : (mode == .shared ? "link" : "square.stack.3d.up"))
                }
            }
            Divider()
            Text(variableMode == .shared ? "Cells use one shared workspace" : "Each cell keeps its own variables")
        } label: {
            if compact {
                Image(systemName: variableMode.symbol)
            } else {
                Label(variableMode == .shared ? "Shared" : "Independent", systemImage: variableMode.symbol)
            }
        }
        .menuStyle(.borderlessButton)
        .font(.caption).fixedSize()
        .disabled(!modeChangeEnabled || actionPending)
        .accessibilityLabel("Variable sharing")
        .accessibilityValue(variableMode.title)
        .help("Choose Shared Variables for one workspace, or Independent Cells for separate cell variables. Changing modes restarts Python after confirmation.")
    }

    private func inspect(_ variable: WorkspaceVariable) {
        let source = variable.scopeID.map { cellNames[$0] ?? ($0 == "internal:console" ? "Console" : "Other cell") }
        let token = inspection.begin(name: variable.name + (source.map { " · " + $0 } ?? ""))
        showInspection = true
        onInspect(variable) { result, error in
            inspection.finish(token: token, statistics: result, error: error)
        }
    }
}

/// The sheet observes a reference directly: it does not depend on SwiftUI
/// reevaluating a presentation closure after the asynchronous kernel reply.
private final class WorkspaceInspectionModel: ObservableObject {
    @Published var name = ""
    @Published var statistics: VariableStatistics?
    @Published var error: String?
    private var token = UUID()

    func begin(name: String) -> UUID {
        token = UUID()
        self.name = name
        statistics = nil
        error = nil
        return token
    }

    func finish(token: UUID, statistics: VariableStatistics?, error: String?) {
        guard token == self.token else { return }
        self.statistics = statistics
        self.error = error ?? (statistics == nil ? "The kernel did not return a variable summary." : nil)
    }
}

private struct VariableStatisticsView: View {
    @ObservedObject var model: WorkspaceInspectionModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Inspect: \(model.name)", systemImage: "chart.bar.xaxis").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            if let error = model.error {
                ContentUnavailableView("Inspection unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let statistics = model.statistics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(statistics.type + (statistics.shape.isEmpty ? "" : " · " + statistics.shape))
                            .foregroundStyle(.secondary)
                        if !statistics.fields.isEmpty { fields(statistics.fields) }
                        ForEach(statistics.columns) { column in
                            GroupBox(column.title) { fields(column.fields).padding(6) }
                        }
                        ForEach(Array(statistics.notes.enumerated()), id: \.offset) { _, note in
                            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Statistics exclude NaN and infinite values from Min, Max, Mean, and Std. Std uses the population formula.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(18).textSelection(.enabled)
                }
            } else {
                ProgressView("Inspecting variable…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(width: 520, height: 580)
    }
    private func fields(_ values: [VariableStatisticField]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
            ForEach(values) { field in
                GridRow {
                    Text(field.label).foregroundStyle(.secondary)
                    Text(field.value).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

/// Keeps multiple variable views available within one project sheet.
struct VariableGallery: View {
    @Binding var tabs: [WorkspaceVariable]
    @Binding var selected: WorkspaceVariable?
    let variables: [WorkspaceVariable]
    let table: WorkspaceTable?
    let error: String?
    var cellNames: [String: String] = [:]
    let onLoad: (String, String?, Int) -> Void
    let onEdit: (String, String?, Int, Int, String) -> Void
    let onPaste: (String, String?, Int, Int, [[String]]) -> Void
    let onPlotColumn: (String, String?, Int, [String: Any], @escaping (Data?, String?) -> Void) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Variables").font(.headline).padding(.leading, 14)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(tabs) { variable in
                            HStack(spacing: 6) {
                                Button(title(variable)) { selected = variable }.buttonStyle(.plain)
                                Button { close(variable) } label: { Image(systemName: "xmark").font(.caption2) }
                                    .buttonStyle(.plain).help("Close variable")
                            }.padding(.horizontal, 9).padding(.vertical, 7)
                                .background(selected?.id == variable.id ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.scrollIndicators(.automatic, axes: .horizontal)
                Menu {
                    ForEach(variables.filter { variable in variable.editable && !tabs.contains(where: { tab in tab.id == variable.id }) }) { variable in
                        Button(title(variable)) { tabs.append(variable); selected = variable }
                    }
                } label: { Image(systemName: "plus") }.help("Open another variable")
                if selected == nil { Button("Done") { dismiss() }.buttonStyle(.glassProminent) }
            }.padding(.vertical, 7).padding(.trailing, 12).background(.bar)
            Divider()
            if let variable = selected {
                VariableEditorPane(table: table?.name == variable.name && table?.scopeID == variable.scopeID ? table : nil,
                    name: variable.name, scopeID: variable.scopeID, displayName: title(variable), error: error,
                    onLoad: { onLoad(variable.name, variable.scopeID, $0) },
                    onEdit: { row, column, text in onEdit(variable.name, variable.scopeID, row, column, text) },
                    onPaste: { row, column, values in onPaste(variable.name, variable.scopeID, row, column, values) },
                    onPlotColumn: { column, options, completion in onPlotColumn(variable.name, variable.scopeID, column, options, completion) })
                    .id(variable.id)
            } else {
                ContentUnavailableView("No variable open", systemImage: "tablecells", description: Text("Choose a variable with the plus button."))
                    .frame(width: 700, height: 450)
            }
        }.frame(minWidth: 700, minHeight: 480)
    }
    private func title(_ variable: WorkspaceVariable) -> String {
        guard let scope = variable.scopeID else { return variable.name }
        let cell = cellNames[scope] ?? (scope == "internal:console" ? "Console" : "Other cell")
        return variable.name + " · " + cell
    }
    private func close(_ variable: WorkspaceVariable) {
        tabs.removeAll { $0.id == variable.id }
        if selected?.id == variable.id { selected = tabs.last }
    }
}

/// Paginated positional editor for supported NumPy arrays and pandas tables.
/// Cells are committed on Return; the caller refreshes the table after completion.
struct VariableEditorPane: View {
    let table: WorkspaceTable?
    let name: String
    var scopeID: String? = nil
    var displayName: String? = nil
    let error: String?
    let onLoad: (Int) -> Void
    let onEdit: (Int, Int, String) -> Void
    let onPaste: (Int, Int, [[String]]) -> Void
    let onPlotColumn: (Int, [String: Any], @escaping (Data?, String?) -> Void) -> Void
    @State private var plot: VariablePlot?
    @State private var plotError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var filterText = ""
    @State private var sortColumn: Int?
    @State private var descending = false

    private func visibleRows(_ table: WorkspaceTable) -> [(offset: Int, element: [String])] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = Array(table.cells.enumerated()).filter { row in
            query.isEmpty || row.element.contains { $0.localizedCaseInsensitiveContains(query) } ||
                (row.offset < table.indices.count && table.indices[row.offset].localizedCaseInsensitiveContains(query))
        }
        if let column = sortColumn {
            rows.sort { left, right in
                let a = column < left.element.count ? left.element[column] : ""
                let b = column < right.element.count ? right.element[column] : ""
                let result = a.localizedStandardCompare(b)
                if result == .orderedSame { return left.offset < right.offset }
                return descending ? result == .orderedDescending : result == .orderedAscending
            }
        }
        return rows
    }
    private func copyVisible(_ table: WorkspaceTable, includeHeaders: Bool) {
        let rows = visibleRows(table).map { row in
            includeHeaders ? [row.offset < table.indices.count ? table.indices[row.offset] : String(table.offset + row.offset)] + row.element : row.element
        }
        let lines = includeHeaders ? [["Index"] + table.columns] + rows : rows
        let text = lines.map { row in row.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t") }.joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "tablecells.fill")
                    .font(.title3).foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName ?? name).font(.title3.weight(.semibold)).textSelection(.enabled)
                    if let table {
                        Text("\(table.total) rows × \(table.width) columns")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Loading variable…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let table {
                    Menu("Copy Visible") {
                        Button("Values Only") { copyVisible(table, includeHeaders: false) }
                        Button("Values with Headers") { copyVisible(table, includeHeaders: true) }
                    }.help("Copy the displayed rows as tab-separated text")
                }
                Button("Done") { dismiss() }.buttonStyle(.glassProminent)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()
            if let error, !error.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).textSelection(.enabled)
                    Spacer()
                    Button("Retry") { onLoad(table?.offset ?? 0) }
                }
                .font(.callout).padding(14)
            }
            if let table {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter displayed rows", text: $filterText).textFieldStyle(.plain)
                    if sortColumn != nil { Button("Clear Sort") { sortColumn = nil }.buttonStyle(.link) }
                    Text("Current page").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.vertical, 8)
                if table.cells.isEmpty {
                    ContentUnavailableView("Empty variable", systemImage: "tablecells", description: Text("This variable has no rows to display."))
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                TableHeader(text: "#", width: 96)
                                ForEach(Array(table.columns.enumerated()), id: \.offset) { index, column in
                                    Button {
                                        if sortColumn == index { descending.toggle() } else { sortColumn = index; descending = false }
                                    } label: {
                                        TableHeader(text: column + (sortColumn == index ? (descending ? " ↓" : " ↑") : ""), width: 150)
                                    }.buttonStyle(.plain).help("Sort the displayed page")
                                        .contextMenu {
                                            Button("Plot Column") {
                                                onPlotColumn(index, [:]) { data, error in
                                                    if let data { plot = VariablePlot(name: (displayName ?? name) + " · " + column, data: data, sourceName: name, column: index, scopeID: scopeID) }
                                                    else { plotError = error ?? "Unable to plot this column." }
                                                }
                                            }
                                        }
                                }
                            }
                            ForEach(visibleRows(table), id: \.offset) { row, cells in
                                GridRow {
                                    Text(row < table.indices.count ? table.indices[row] : String(table.offset + row))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                        .lineLimit(1).padding(.horizontal, 10)
                                        .frame(width: 96, height: 32, alignment: .leading)
                                        .background(.quaternary.opacity(0.3))
                                    ForEach(Array(cells.enumerated()), id: \.offset) { column, value in
                                        LiteralField(value: value) { literal in
                                            onEdit(table.offset + row, column, literal)
                                        }
                                        .contextMenu {
                                            Button("Paste Table Starting Here") {
                                                guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
                                                var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
                                                if lines.last == "" { lines.removeLast() }
                                                let rows = lines.map { $0.components(separatedBy: "\t") }
                                                onPaste(table.offset + row, column, rows)
                                            }
                                            .disabled(!filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sortColumn != nil)
                                            if !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sortColumn != nil {
                                                Text("Clear the filter and sort before pasting.")
                                            }
                                        }
                                        .id("\(table.scopeID ?? "shared")-\(table.name)-\(table.offset)-\(row)-\(column)-\(value)")
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                Divider()
                HStack {
                    Text("Edit and press Return; right-click a cell to paste a table. Strings need quotes.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { onLoad(max(0, table.offset - 100)) } label: { Image(systemName: "chevron.left") }
                        .disabled(table.offset == 0).help("Previous 100 rows")
                    Text("\(table.total == 0 ? 0 : table.offset + 1)–\(min(table.total, table.offset + table.cells.count)) of \(table.total)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button { onLoad(table.offset + 100) } label: { Image(systemName: "chevron.right") }
                        .disabled(table.offset + 100 >= table.total).help("Next 100 rows")
                }
                .buttonStyle(.glass)
                .padding(14)
                if table.width > 30 {
                    Text("Showing the first 30 columns.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 10)
                }
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 430)
        .sheet(item: $plot) { figure in
            VariablePlotView(plot: figure, regenerate: { options, completion in
                if let column = figure.column { onPlotColumn(column, options, completion) }
            })
        }
        .alert("Could not plot column", isPresented: Binding(get: { plotError != nil }, set: { if !$0 { plotError = nil } })) {
            Button("OK", role: .cancel) { plotError = nil }
        } message: { Text(plotError ?? "") }
        .onAppear { onLoad(0) }
    }
}

private struct TableHeader: View {
    let text: String
    let width: CGFloat
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .lineLimit(1).padding(.horizontal, 10)
            .frame(width: width, height: 34, alignment: .leading)
            .background(.quaternary.opacity(0.5))
    }
}

private struct LiteralField: View {
    @State private var text: String
    let commit: (String) -> Void
    init(value: String, commit: @escaping (String) -> Void) {
        self._text = State(initialValue: value)
        self.commit = commit
    }
    var body: some View {
        TextField("Value", text: $text)
            .textFieldStyle(.plain).font(.caption.monospaced())
            .padding(.horizontal, 10)
            .frame(width: 150, height: 32)
            .background(.quaternary.opacity(0.12))
            .onSubmit { commit(text) }
            .help("Enter a Python scalar literal, then press Return")
    }
}
