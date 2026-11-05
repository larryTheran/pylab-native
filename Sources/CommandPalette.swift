import SwiftUI

/// Actions are scoped to one project by ProjectTabsHost before delivery.
enum ProjectToolbarAction: String {
    case open, save, addCell, runCell, interrupt, kernelSettings, newNotebook, saveAs
    case runAll, runAbove, runAdvance, debugCell, showFigures, refresh, restart, toggleConsole, toggleWorkspace, resetLayout, importMat, exportMat
    case findCells, clearOutputs, runBelow, saveAll, runCode, editorSettings, importScript, showActivity
}

struct PaletteCommand: Identifiable {
    let action: ProjectToolbarAction
    let title: String
    let detail: String
    let icon: String
    var shortcut = ""
    var keywords = ""
    var id: String { action.rawValue }

    static let all: [PaletteCommand] = [
        .init(action: .findCells, title: "Find in Notebooks", detail: "Search names and code across this project's open notebooks", icon: "magnifyingglass", shortcut: "⌘F", keywords: "search navigate cells"),
        .init(action: .editorSettings, title: "Editor Settings", detail: "Code palette, font size, line numbers, and indentation guides", icon: "slider.horizontal.3", shortcut: "⌘,", keywords: "theme colors appearance"),
        .init(action: .importScript, title: "Import Python Script", detail: "Open a .py file as an unexecuted notebook cell", icon: "doc.badge.plus", keywords: "source file"),
        .init(action: .showActivity, title: "Kernel Activity", detail: "Inspect the Python process CPU and resident memory", icon: "waveform.path.ecg", keywords: "resources ram monitor metrics"),
        .init(action: .newNotebook, title: "New Notebook", detail: "Create a notebook tab in this project", icon: "doc.badge.plus", shortcut: "⌘N"),
        .init(action: .open, title: "Open Notebook", detail: "Open an .ipynb file in another tab", icon: "folder", shortcut: "⌘O"),
        .init(action: .save, title: "Save Notebook", detail: "Save the active notebook", icon: "square.and.arrow.down", shortcut: "⌘S"),
        .init(action: .saveAs, title: "Save Notebook As", detail: "Choose a new name or location", icon: "doc.on.doc", shortcut: "⇧⌘S"),
        .init(action: .saveAll, title: "Save All Notebooks", detail: "Save changed notebooks in this project", icon: "square.and.arrow.down.on.square"),
        .init(action: .addCell, title: "Add Cell", detail: "Insert a cell after the selected cell", icon: "plus.square"),
        .init(action: .runCell, title: "Run Selected Cell", detail: "Execute the selected cell in the project Python kernel", icon: "play.fill", shortcut: "⌘↩", keywords: "execute"),
        .init(action: .runAdvance, title: "Run Cell and Advance", detail: "Execute and select the next cell", icon: "play.square.stack", shortcut: "⇧⌘↩"),
        .init(action: .runAbove, title: "Run All Above", detail: "Execute code cells before the selected cell", icon: "arrow.up.to.line", keywords: "execute"),
        .init(action: .runBelow, title: "Run Selected and Below", detail: "Execute from the selected cell to the end", icon: "arrow.down.to.line", keywords: "execute"),
        .init(action: .runAll, title: "Run All Cells", detail: "Execute every code cell in the active notebook", icon: "play.rectangle.on.rectangle", keywords: "execute"),
        .init(action: .debugCell, title: "Debug Selected Cell", detail: "Start the Python debugger with this cell's breakpoints", icon: "ladybug"),
        .init(action: .clearOutputs, title: "Clear Notebook Outputs", detail: "Clear saved outputs without changing code or live variables", icon: "eraser", keywords: "clean reset results"),
        .init(action: .showFigures, title: "Show Figures", detail: "Revisit notebook, console, and workspace plots", icon: "chart.xyaxis.line", keywords: "plot gallery"),
        .init(action: .importMat, title: "Import Data", detail: "Load MAT, NPY, CSV, or Excel data into the workspace", icon: "square.and.arrow.down", keywords: "load matrix table"),
        .init(action: .exportMat, title: "Export Workspace to MAT", detail: "Save supported live variables in a MATLAB file", icon: "square.and.arrow.up", keywords: "save data"),
        .init(action: .refresh, title: "Refresh Workspace", detail: "Update the live variable list", icon: "arrow.clockwise"),
        .init(action: .interrupt, title: "Interrupt Kernel", detail: "Ask Python to stop the running calculation", icon: "stop.fill", keywords: "cancel execution"),
        .init(action: .restart, title: "Restart Kernel", detail: "Restart Python after confirmation; live variables are cleared", icon: "arrow.counterclockwise", keywords: "reset python"),
        .init(action: .kernelSettings, title: "Choose Python Kernel", detail: "Select a Python environment for this project", icon: "cpu", keywords: "interpreter conda environment"),
        .init(action: .toggleConsole, title: "Toggle Console", detail: "Show or hide the shared IPython command console", icon: "terminal"),
        .init(action: .toggleWorkspace, title: "Toggle Workspace", detail: "Show or hide the variable inspector", icon: "tablecells"),
        .init(action: .resetLayout, title: "Reset Layout", detail: "Restore the default pane arrangement", icon: "rectangle.3.group", keywords: "panes sidebar"),
    ]

    static func matching(_ query: String, commands: [PaletteCommand] = all) -> [PaletteCommand] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return commands }
        let phrase = terms.joined(separator: " ")
        // Prefer the command the user named over an incidental word in help
        // text. Original ordering breaks ties, so keyboard selection is stable.
        return commands.enumerated().compactMap { index, command -> (Int, Int, PaletteCommand)? in
            let haystack = command.title + " " + command.detail + " " + command.keywords
            guard terms.allSatisfy({ haystack.localizedCaseInsensitiveContains($0) }) else { return nil }
            let rank: Int
            if command.title.compare(phrase, options: .caseInsensitive) == .orderedSame { rank = 0 }
            else if command.title.range(of: phrase, options: [.caseInsensitive, .anchored]) != nil { rank = 1 }
            else if command.title.range(of: phrase, options: .caseInsensitive) != nil { rank = 2 }
            else if terms.allSatisfy({ command.title.localizedCaseInsensitiveContains($0) }) { rank = 3 }
            else { rank = 4 }
            return (rank, index, command)
        }.sorted { left, right in
            left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
        }.map { $0.2 }
    }
}

struct CommandPaletteView: View {
    let projectName: String
    let onSelect: (ProjectToolbarAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selection: String? = PaletteCommand.all.first?.id
    private var results: [PaletteCommand] { PaletteCommand.matching(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Search commands…", text: $query)
                    .textFieldStyle(.plain).font(.title3)
                    .focused($searchFocused)
                    .onSubmit(runSelection)
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close command palette")
                    .accessibilityLabel("Close command palette")
            }
            .padding(18)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(results) { command in
                            Button { onSelect(command.action) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: command.icon).font(.system(size: 16)).frame(width: 24).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(command.title).font(.system(size: 13, weight: .medium))
                                        Text(command.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    Text(command.shortcut).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == command.id ? Color.accentColor.opacity(0.19) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(command.id)
                            .accessibilityLabel(command.title + ". " + command.detail)
                        }
                        if results.isEmpty {
                            ContentUnavailableView.search(text: query).frame(height: 220)
                        }
                    }.padding(8)
                }
                .onChange(of: selection) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            Divider()
            HStack {
                Text(projectName).lineLimit(1)
                Spacer()
                Text("↑↓ to choose · Return to run · Esc to close")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 660, height: 520)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selection = results.first?.id }
        .onExitCommand { dismiss() }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { selection = nil; return }
        let current = results.firstIndex(where: { $0.id == selection }) ?? 0
        selection = results[min(max(current + delta, 0), results.count - 1)].id
    }
    private func runSelection() {
        guard let command = results.first(where: { $0.id == selection }) ?? results.first else { return }
        onSelect(command.action)
    }
}
