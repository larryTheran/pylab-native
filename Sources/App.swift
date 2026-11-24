import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct PyLabApp: App {
    @NSApplicationDelegateAdaptor(PyLabLifecycle.self) private var lifecycle
    @StateObject private var appearance = AppearanceSettings()
    var body: some Scene {
        WindowGroup("PyLab Native") {
            ProjectTabsHost()
                .environmentObject(appearance)
                .preferredColorScheme(appearance.mode.colorScheme)
                .frame(minWidth: 820, minHeight: 540)
        }
            .defaultSize(width: 1450, height: 950)
            .windowStyle(.titleBar)
            .commands {
                PyLabCommands()
                AppearanceCommands(settings: appearance)
            }
    }
}

@MainActor
final class PyLabLifecycle: NSObject, NSApplicationDelegate {
    static var dirtyProjects = Set<UUID>()
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.dirtyProjects.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit with unsaved notebooks?"
        alert.informativeText = "Save your notebooks before quitting if you want to keep their changes."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

struct Workbench: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var consoleDockDrag = ConsoleDockDragState()
    @FocusState private var consoleInputFocused: Bool
    @Namespace private var notebookSelectionNamespace
    @Namespace private var notebookGlassNamespace
    @StateObject private var notebooks = NotebookCollection()
    private var notebook: NotebookStore { notebooks.selected.store }
    @State private var runningCells = Set<String>()
    @State private var executionStarted: [String: Date] = [:]
    @State private var debugRequestID: String?
    @StateObject private var kernel = KernelController()
    @State private var project: URL
    let projectID: UUID
    @ObservedObject var layout: SharedProjectLayout
    let initialNotebookPaths: [String]
    let initialSelectedNotebook: String?
    let onVariableModeChanged: (VariableSharingMode) -> Void
    let onNotebookStateChanged: ([String], String?) -> Void
    let onProjectSelected: (URL) -> Void
    let onStatusChanged: (Bool, Bool) -> Void
    let onExecutionPhaseChanged: (KernelExecutionPhase?) -> Void
    @State private var projectHistory: [URL] = []
    @State private var pendingFolder: URL?
    @State private var files: [ProjectItem] = []
    @State private var command = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int?
    @State private var historyDraft = ""
    @State private var showHistory = false
    @State private var console: ConsoleLog = "IPython console · shared with the notebook\n"
    @State private var consoleIDs = Set<String>()
    @State private var pendingClear = Set<String>()
    @State private var selectedVariable: WorkspaceVariable?
    @State private var variableTabs: [WorkspaceVariable] = []
    @State private var showVariables = false
    @State private var figures: [VariablePlot] = []
    @State private var showFigures = false
    @State private var errorMessage: String?
    @State private var sidebarDragStart: CGFloat?
    @State private var workspaceDragStart: CGFloat?
    @State private var consoleDragStart: CGFloat?
    @State private var showKernelSettings = false
    @State private var showEditorSettings = false
    @State private var showKernelActivity = false
    @State private var openingFiles = false
    @State private var showNotebookSearch = false
    @State private var pendingSearchResult: NotebookSearchResult?
    @State private var nextFigureNumber = 1
    @State private var consoleDisplayPlaceholders: [String] = []
    private static let figureLimit = 50
    @State private var isWorkbenchVisible = false
    @State private var didRestoreNotebooks = false
    @State private var unavailableNotebookPaths: [String] = []

    init(initialProject: URL, projectID: UUID, layout: SharedProjectLayout,
         initialNotebookPaths: [String], initialSelectedNotebook: String?,
         initialVariableMode: VariableSharingMode = .shared, onVariableModeChanged: @escaping (VariableSharingMode) -> Void = { _ in }, onNotebookStateChanged: @escaping ([String], String?) -> Void, onProjectSelected: @escaping (URL) -> Void, onStatusChanged: @escaping (Bool, Bool) -> Void, onExecutionPhaseChanged: @escaping (KernelExecutionPhase?) -> Void = { _ in }) {
        _project = State(initialValue: initialProject)
        _kernel = StateObject(wrappedValue: KernelController(variableMode: initialVariableMode))
        _console = State(initialValue: ConsoleLog(stringLiteral: initialVariableMode == .shared
            ? "IPython console · shared with all cells in this project\n"
            : "IPython console · follows the selected cell’s independent workspace\n"))
        self.onVariableModeChanged = onVariableModeChanged
        self.projectID = projectID
        self.layout = layout
        self.initialNotebookPaths = initialNotebookPaths
        self.initialSelectedNotebook = initialSelectedNotebook
        self.onNotebookStateChanged = onNotebookStateChanged
        self.onProjectSelected = onProjectSelected
        self.onStatusChanged = onStatusChanged
        self.onExecutionPhaseChanged = onExecutionPhaseChanged
    }

    private var workbenchContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in workbenchPanes(size: geometry.size) }
            Divider()
            WorkbenchStatusBar(kernel: kernel, pendingCount: runningCells.count + consoleIDs.count,
                startedAt: executionStarted.values.min(), isDirty: notebooks.isDirty, isFileBacked: notebook.fileURL != nil,
                onChoosePython: { showKernelSettings = true }, onRestart: restartKernel,
                onInterrupt: { kernel.interrupt() }, onEditorSettings: { showEditorSettings = true })
        }
        .navigationTitle(notebook.fileURL?.lastPathComponent ?? "Untitled Notebook")

        .sheet(isPresented: $showVariables) {
            VariableGallery(tabs: $variableTabs, selected: $selectedVariable, variables: kernel.workspace,
                table: kernel.table, error: kernel.tableError, cellNames: workspaceCellNames,
                onLoad: { name, scope, offset in kernel.loadTable(name: name, offset: offset, scopeID: scope) },
                onEdit: { name, scope, row, column, text in kernel.editTable(name: name, row: row, column: column, literal: text, scopeID: scope) },
                onPaste: { name, scope, row, column, values in kernel.pasteTable(name: name, row: row, column: column, values: values, scopeID: scope) },
                onPlotColumn: { name, scope, column, options, completion in kernel.plotVariable(name: name, column: column, options: options, scopeID: scope, completion: completion) })
        }
        .sheet(isPresented: $showFigures) {
            FigureGallery(figures: $figures) { plot, options, completion in
                kernel.plotVariable(name: plot.sourceName ?? plot.name, column: plot.column, options: options, scopeID: plot.scopeID, completion: completion)
            }
        }
        .sheet(isPresented: $showNotebookSearch, onDismiss: {
            guard let result = pendingSearchResult else { return }
            pendingSearchResult = nil
            guard let target = notebooks.tabs.first(where: { $0.id == result.notebookID }) else { return }
            notebooks.selectedID = target.id
            DispatchQueue.main.async { target.store.revealCell(result.cellID, line: result.line) }
        }) {
            NotebookSearchView(notebooks: notebooks) { result in pendingSearchResult = result }
        }
        .sheet(isPresented: $showEditorSettings) { EditorSettingsView() }
        .sheet(isPresented: $showKernelActivity) {
            KernelActivityView(activity: kernel.activity, history: kernel.activityHistory, unavailable: kernel.activityUnavailable)
                .padding(20)
        }
        .sheet(isPresented: $showKernelSettings) {
            KernelSettingsView(currentPath: kernel.interpreter) { path in
                let changed = kernel.selectPython(path: path)
                if changed {
                    pendingClear.removeAll()
                    consoleIDs.removeAll(); runningCells.removeAll(); executionStarted.removeAll(); debugRequestID = nil
                    for tab in notebooks.tabs { tab.store.runningCellIDs.removeAll() }
                    console += "\n[Python kernel changed to " + path + "]\n"
                }
                return changed
            }
        }
        .alert("PyLab", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    var body: some View {
        workbenchContent
        .onAppear {
            isWorkbenchVisible = true
            if !didRestoreNotebooks {
                let initialID = notebooks.selectedID
                for path in initialNotebookPaths {
                    let url = URL(fileURLWithPath: path)
                    let store = NotebookStore()
                    do { try store.load(from: url); notebooks.addLoaded(store) }
                    catch {
                        if !unavailableNotebookPaths.contains(path) { unavailableNotebookPaths.append(path) }
                    }
                }
                if notebooks.tabs.count > 1 { notebooks.remove(initialID) }
                if let path = initialSelectedNotebook, let tab = notebooks.find(url: URL(fileURLWithPath: path)) { notebooks.selectedID = tab.id }
                didRestoreNotebooks = true
                if !unavailableNotebookPaths.isEmpty {
                    errorMessage = "Some saved notebooks could not be opened. Their paths have been kept so they can be restored when the files are available."
                }
                reportNotebookState()
            }
            reloadFiles()
            kernel.onEvent = receive
            kernel.start(cwd: project)
            onStatusChanged(notebooks.isDirty, !kernel.workspace.isEmpty || kernel.state == "Busy" || !kernel.executionActivities.isEmpty)
        }
        .onReceive(notebooks.objectWillChange) { _ in
            guard isWorkbenchVisible else { return }
            // A notification precedes the mutation; conservatively guard window
            // closure until the new dirty state has been observed on the next turn.
            PyLabLifecycle.dirtyProjects.insert(projectID)
            DispatchQueue.main.async {
                guard isWorkbenchVisible else { return }
                if notebooks.isDirty { PyLabLifecycle.dirtyProjects.insert(projectID) }
                else { PyLabLifecycle.dirtyProjects.remove(projectID) }
                onStatusChanged(notebooks.isDirty, !kernel.workspace.isEmpty || kernel.state == "Busy" || !kernel.executionActivities.isEmpty)
                if didRestoreNotebooks { reportNotebookState() }
            }
        }
        .onChange(of: layout.showSidebar) { _, _ in sidebarDragStart = nil }
        .onChange(of: layout.showWorkspace) { _, _ in workspaceDragStart = nil }
        .onChange(of: layout.showConsole) { _, visible in
            consoleDragStart = nil
            if !visible { consoleInputFocused = false; consoleDockDrag.end() }
        }
        .onChange(of: layout.consolePlacement) { _, _ in consoleDragStart = nil }
        .onChange(of: kernel.workspace.map(\.id)) { _, identities in
            let available = Set(identities)
            variableTabs.removeAll { !available.contains($0.id) }
            if let selectedVariable, !available.contains(selectedVariable.id) { self.selectedVariable = variableTabs.last }
        }
        .onChange(of: kernel.executionActivities) { _, _ in
            guard isWorkbenchVisible else { return }
            syncExecutionIndicators()
            onStatusChanged(notebooks.isDirty, !kernel.workspace.isEmpty || !kernel.executionActivities.isEmpty)
        }
        .onChange(of: kernel.workspace.count) { _, _ in onStatusChanged(notebooks.isDirty, !kernel.workspace.isEmpty || kernel.state == "Busy" || !kernel.executionActivities.isEmpty) }
        .onChange(of: kernel.state) { _, state in
            if state != "Ready" && state != "Busy" { detachLiveDisplays() }
            onStatusChanged(notebooks.isDirty, !kernel.workspace.isEmpty || kernel.state == "Busy" || !kernel.executionActivities.isEmpty)
        }
        .onChange(of: kernel.inputPrompt) { _, prompt in
            if let prompt { layout.showConsole = true; console += "\n" + prompt }
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectToolbarAction)) { notification in
            guard let id = notification.userInfo?["projectID"] as? UUID, id == projectID,
                  let action = notification.userInfo?["action"] as? ProjectToolbarAction else { return }
            handleToolbarAction(action)
        }
        .onDisappear { isWorkbenchVisible = false; PyLabLifecycle.dirtyProjects.remove(projectID); kernel.stop() }
    }

    private func workbenchPanes(size: CGSize) -> some View {
        let panels = WorkbenchPaneLayout(width: size.width,
            sidebarPreferred: layout.sidebarWidth, workspacePreferred: layout.workspaceWidth,
            showSidebar: layout.showSidebar, showWorkspace: layout.showWorkspace)
        let frames = dockFrames(size: size, panels: panels, placement: layout.consolePlacement)
        return ZStack(alignment: .topLeading) {
            if layout.showSidebar { pane(projectSidebar, in: frames.sidebar) }
            pane(notebookPane, in: frames.notebook)
            if layout.showWorkspace { pane(workspacePane, in: frames.workspace) }
            if layout.showConsole {
                pane(consoleView, in: frames.console)
                    .opacity(consoleDockDrag.isDragging ? 0.68 : 1)
            }
            if layout.showSidebar { pane(sidebarResizeHandle(size: size, panels: panels), in: frames.sidebarDivider) }
            if layout.showWorkspace { pane(workspaceResizeHandle(size: size, panels: panels), in: frames.workspaceDivider) }
            if layout.showConsole { pane(consoleResizeHandle(frames: frames), in: frames.consoleDivider) }
            if consoleDockDrag.isDragging { consoleDockTargets(size: size, panels: panels, frames: frames).zIndex(100) }
        }
        .frame(width: max(0, size.width), height: max(0, size.height), alignment: .topLeading)
        .background(.background)
        .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: layout.showSidebar)
        .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: layout.showWorkspace)
        .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: layout.showConsole)
        .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: layout.consolePlacement)
    }

    private func pane<Content: View>(_ content: Content, in rect: CGRect) -> some View {
        content
            .frame(width: max(0, rect.width), height: max(0, rect.height), alignment: .topLeading)
            .clipped()
            .offset(x: rect.minX, y: rect.minY)
    }

    private var notebookPane: some View {
        VStack(spacing: 0) {
            notebookTabs
            NotebookPresentationView(store: notebook, onRun: runCell,
                onComplete: { code, position, completion in kernel.complete(code: code, cursorUTF16: position, scopeID: activeCellScopeID, completion: completion) },
                onRunSelection: runSelection, onInterrupt: { kernel.interrupt() })
                .id(notebooks.selectedID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var workspacePane: some View {
        WorkspacePane(variables: kernel.workspace,
            cellNames: workspaceCellNames,
            cellOrder: notebooks.tabs.flatMap { tab in tab.store.cells.map { executionID(tab.id, $0.id) } },
            onRefresh: { kernel.refreshWorkspace() }, onOpen: openVariable, onSave: saveVariable, onPlot: plotVariable,
            onInspect: { variable, completion in kernel.inspectVariable(name: variable.name, scopeID: variable.scopeID, completion: completion) },
            onRename: { variable, replacement, completion in kernel.renameVariable(name: variable.name, to: replacement, scopeID: variable.scopeID, completion: completion) },
            onDelete: { variable, completion in kernel.deleteVariable(name: variable.name, scopeID: variable.scopeID, completion: completion) },
            actionsEnabled: kernel.state == "Ready" && kernel.inputPrompt == nil,
            variableMode: kernel.variableMode, onVariableModeChange: changeVariableMode, modeChangeEnabled: canChangeVariableMode)
    }

    private var activeCellScopeID: String? {
        guard kernel.variableMode == .independent,
              let cellID = notebook.selectedID ?? notebook.cells.first?.id else { return nil }
        return executionID(notebooks.selectedID, cellID)
    }
    private var canChangeVariableMode: Bool {
        kernel.state != "Starting" && kernel.state != "Busy" && kernel.inputPrompt == nil &&
            runningCells.isEmpty && consoleIDs.isEmpty && debugRequestID == nil && pendingFolder == nil
    }
    private func changeVariableMode(_ mode: VariableSharingMode) {
        guard mode != kernel.variableMode else { return }
        guard canChangeVariableMode else {
            errorMessage = "Wait for running code and pending input to finish before changing variable sharing."
            return
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "Use " + mode.title + "?"
        alert.informativeText = mode.explanation + "\n\nPython will restart and clear live variables. Notebook code and outputs remain. Rerun cells to populate the new workspace."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Restart and Switch")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        showVariables = false; variableTabs.removeAll(); selectedVariable = nil
        // Old plots stay as snapshots instead of retargeting another namespace.
        for index in figures.indices { figures[index].sourceName = nil }
        kernel.setVariableMode(mode, cwd: project)
        onVariableModeChanged(mode)
        console += "\n[Variable mode: " + mode.title + ". Run cells to populate the workspace.]\n"
    }

    private var workspaceCellNames: [String: String] {
        notebooks.tabs.reduce(into: [String: String]()) { result, tab in
            for cell in tab.store.cells { result[executionID(tab.id, cell.id)] = tab.title + " / " + cell.name }
        }
    }

    private func dockFrames(size: CGSize, panels: WorkbenchPaneLayout, placement: ConsolePlacement) -> WorkbenchDockLayout {
        WorkbenchDockLayout(size: size, panels: panels, showSidebar: layout.showSidebar,
            showWorkspace: layout.showWorkspace, showConsole: layout.showConsole,
            placement: placement, consolePreferred: layout.consoleHeight)
    }

    private func sidebarResizeHandle(size: CGSize, panels: WorkbenchPaneLayout) -> some View {
        PaneResizeHandle(vertical: true, label: "Drag to resize project browser")
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if sidebarDragStart == nil {
                    sidebarDragStart = panels.sidebar
                    if layout.showWorkspace { layout.workspaceWidth = panels.workspace }
                }
                let maximum = size.width - 360 - (layout.showWorkspace ? panels.workspace + 5 : 0) - 5
                layout.sidebarWidth = min(max((sidebarDragStart ?? panels.sidebar) + value.translation.width, 170), max(170, maximum))
            }.onEnded { _ in sidebarDragStart = nil })
    }

    private func workspaceResizeHandle(size: CGSize, panels: WorkbenchPaneLayout) -> some View {
        PaneResizeHandle(vertical: true, label: "Drag to resize workspace")
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if workspaceDragStart == nil {
                    workspaceDragStart = panels.workspace
                    if layout.showSidebar { layout.sidebarWidth = panels.sidebar }
                }
                let maximum = size.width - 360 - (layout.showSidebar ? panels.sidebar + 5 : 0) - 5
                layout.workspaceWidth = min(max((workspaceDragStart ?? panels.workspace) - value.translation.width, 260), max(260, maximum))
            }.onEnded { _ in workspaceDragStart = nil })
    }

    private func consoleResizeHandle(frames: WorkbenchDockLayout) -> some View {
        PaneResizeHandle(vertical: false, label: "Drag to resize command console")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                if consoleDragStart == nil { consoleDragStart = frames.console.height }
                layout.consoleHeight = WorkbenchPaneLayout.consoleHeight(
                    preferred: (consoleDragStart ?? frames.console.height) - value.translation.height,
                    height: frames.consoleBranchHeight)
            }.onEnded { _ in consoleDragStart = nil })
    }

    private func consoleDockTargets(size: CGSize, panels: WorkbenchPaneLayout, frames: WorkbenchDockLayout) -> some View {
        ZStack(alignment: .topLeading) {
            if let target = consoleDockDrag.target {
                let preview = dockFrames(size: size, panels: panels, placement: target).console.insetBy(dx: 3, dy: 3)
                pane(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)), in: preview)
                    .allowsHitTesting(false)
            }
            dockTarget(.notebookBottom, current: frames.effectivePlacement,
                rect: CGRect(x: frames.notebook.midX - min(310, frames.notebook.width - 24) / 2,
                    y: max(12, size.height - 194), width: min(310, frames.notebook.width - 24), height: 94))
            if layout.showWorkspace {
                dockTarget(.workspaceBottom, current: frames.effectivePlacement,
                    rect: CGRect(x: frames.workspace.midX - min(300, frames.workspace.width - 24) / 2,
                        y: max(12, size.height - 194), width: min(300, frames.workspace.width - 24), height: 94))
            }
            dockTarget(.windowBottom, current: frames.effectivePlacement,
                rect: CGRect(x: frames.content.midX - min(520, frames.content.width - 24) / 2,
                    y: max(118, size.height - 88), width: min(520, frames.content.width - 24), height: 76))
        }.frame(width: max(0, size.width), height: max(0, size.height), alignment: .topLeading)
    }

    private func dockTarget(_ placement: ConsolePlacement, current: ConsolePlacement, rect: CGRect) -> some View {
        ConsoleDockZoneView(placement: placement, currentPlacement: current, state: consoleDockDrag,
            scope: projectID, onSelect: placeConsole)
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .offset(x: rect.minX, y: rect.minY)
    }

    private func placeConsole(_ placement: ConsolePlacement) {
        withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) {
            if placement == .workspaceBottom { layout.showWorkspace = true }
            layout.showConsole = true
            layout.consolePlacement = placement
        }
    }

    private func handleToolbarAction(_ action: ProjectToolbarAction) {
        switch action {
        case .open: openNotebook()
        case .save: saveNotebook()
        case .addCell:
            let added = notebook.addCell(after: notebook.selectedID)
            notebook.revealCell(added, line: 1)
        case .runCell: runSelected()
        case .runCode: if !runFocusedCodeSelection() { runSelected() }
        case .interrupt: kernel.interrupt()
        case .kernelSettings: showKernelSettings = true
        case .newNotebook: newNotebook()
        case .saveAs: saveNotebookAs()
        case .saveAll: saveAllNotebooks()
        case .findCells: showNotebookSearch = true
        case .clearOutputs:
            guard notebook.runningCellIDs.isEmpty else {
                errorMessage = "Wait for this notebook's running cells to finish before clearing outputs."; return
            }
            for cell in notebook.cells where cell.cellType == "code" { notebook.clearOutputs(cell.id) }
            notebook.executionTimes.removeAll()
        case .runBelow:
            if let id = notebook.selectedID, let start = notebook.cells.firstIndex(where: { $0.id == id }) {
                for cell in notebook.cells[start...] where cell.cellType == "code" { runCell(cell.id, cell.source) }
            }
        case .runAll: for cell in notebook.cells where cell.cellType == "code" { runCell(cell.id, cell.source) }
        case .debugCell: debugSelected()
        case .showFigures: showFigures = true
        case .runAbove:
            if let id = notebook.selectedID, let end = notebook.cells.firstIndex(where: { $0.id == id }) {
                for cell in notebook.cells[..<end] where cell.cellType == "code" { runCell(cell.id, cell.source) }
            }
        case .runAdvance:
            if let id = notebook.selectedID, let index = notebook.cells.firstIndex(where: { $0.id == id }) {
                guard notebook.cells[index].cellType == "code", debugRequestID == nil,
                      !runningCells.contains(executionID(notebooks.selectedID, id)),
                      kernel.state == "Ready" || kernel.state == "Busy" else {
                    errorMessage = "Select a code cell and wait for the kernel to be ready before running it."; return
                }
                runSelected()
                if index + 1 < notebook.cells.count { notebook.revealCell(notebook.cells[index + 1].id, line: 1) }
                else { let added = notebook.addCell(after: id); notebook.revealCell(added, line: 1) }
            }
        case .refresh: kernel.refreshWorkspace()
        case .restart: restartKernel()
        case .toggleConsole: layout.showConsole.toggle()
        case .toggleWorkspace: layout.showWorkspace.toggle()
        case .resetLayout:
            layout.sidebarWidth = 220; layout.workspaceWidth = 390; layout.consoleHeight = 230
            layout.consolePlacement = .workspaceBottom
            layout.showSidebar = true; layout.showWorkspace = true; layout.showConsole = true
        case .editorSettings: showEditorSettings = true
        case .importScript: choosePythonScripts()
        case .showActivity: showKernelActivity = true
        case .importMat: importMAT()
        case .exportMat: exportMAT()
        }
    }

    private func reportNotebookState() {
        onNotebookStateChanged(notebooks.tabs.compactMap { $0.store.fileURL?.path } + unavailableNotebookPaths,
            notebooks.selected.store.fileURL?.path ?? (unavailableNotebookPaths.contains(initialSelectedNotebook ?? "") ? initialSelectedNotebook : nil))
    }

    var projectSidebar: some View {
        ProjectBrowserView(folder: project, items: files, canGoBack: !projectHistory.isEmpty,
            isNavigating: pendingFolder != nil, kernelState: kernel.state, interpreter: kernel.interpreter,
            isOpeningFiles: openingFiles,
            onBack: goBackFolder, onParent: goToParentFolder,
            onNavigateFolder: { navigateToFolder($0) }, onChooseFolder: chooseFolder,
            onCreateFolder: createFolder, onOpen: openProjectItem, onRename: renameItem,
            onDuplicate: duplicateItem, onDropFiles: handleDroppedFiles, onRefresh: reloadFiles)
    }

    var consoleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            consoleHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(console.displayText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).id("consoleEnd")
                        .padding(.horizontal, 15).padding(.vertical, 8)
                }.onChange(of: console) { _, _ in proxy.scrollTo("consoleEnd", anchor: .bottom) }
            }
            HStack {
                Text("❯").foregroundStyle(.pink).fontWeight(.bold)
                Group {
                    if kernel.inputIsPassword {
                        SecureField("Input requested", text: $command).onSubmit(runCommand).focused($consoleInputFocused)
                    } else {
                        TextField(kernel.inputPrompt == nil ? "Enter Python or IPython command" : "Enter requested input or debugger command", text: $command)
                            .focused($consoleInputFocused)
                            .onSubmit(runCommand)
                            .onMoveCommand { direction in
                                switch direction {
                                case .up: navigateHistory(-1)
                                case .down: navigateHistory(1)
                                default: break
                                }
                            }
                    }
                }.textFieldStyle(.plain).font(.system(.body, design: .monospaced))
            }.padding(.horizontal, 15).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                .padding(.horizontal, 10).padding(.bottom, 8)
        }.background(.regularMaterial)
    }

    private var consoleHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                consoleDockHandle(compact: false)
                Spacer(minLength: 8)
                consoleStatus
                if debugRequestID != nil { consoleDebuggerControls }
                consoleHeaderActions(compact: false)
            }
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    consoleDockHandle(compact: true)
                    Spacer(minLength: 6)
                    consoleStatus
                    consoleHeaderActions(compact: true)
                }
                if debugRequestID != nil {
                    HStack(spacing: 8) {
                        consoleDebuggerControls
                        Spacer(minLength: 0)
                    }
                }
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    consoleDockHandle(compact: true)
                    Spacer(minLength: 0)
                    consoleHeaderActions(compact: true)
                }
                HStack {
                    if debugRequestID != nil {
                        consoleDebuggerControls
                            .accessibilityLabel(kernel.inputPrompt == nil ? "Python debugger running" : "Python debugger paused")
                    } else { consoleStatus }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popover(isPresented: $showHistory) {
            VStack(alignment: .leading) {
                Text("Command History").font(.headline)
                if commandHistory.isEmpty { Text("No commands yet").foregroundStyle(.secondary) }
                else {
                    List(commandHistory.indices.reversed(), id: \.self) { index in
                        Button(commandHistory[index]) { command = commandHistory[index]; showHistory = false }
                            .buttonStyle(.plain).lineLimit(2)
                    }.frame(width: 420, height: 260)
                }
            }.padding()
        }
    }

    private var consoleStatus: some View {
        Group {
            if let activity = KernelExecutionActivity.representative(in: Array(kernel.executionActivities.values)) {
                ExecutionIndicator(phase: activity.phase, startedAt: activity.startedAt)
            } else {
                Text(kernel.variableMode == .independent ? "Cell: " + (notebook.cells.first(where: { $0.id == notebook.selectedID })?.name ?? "Console") : "Shared kernel")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .help(kernel.inputPrompt != nil ? "Python is waiting for input in the console" : "Execution status for this project's kernel")
    }

    private func consoleDockHandle(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.secondary)
            Label(compact ? "Console" : "Command Console", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
        }
        .fixedSize().contentShape(Rectangle())
        .help("Drag to move the console, or choose a position from its Dock menu")
        .accessibilityLabel("Command Console, drag to move")
        .onDrag {
            showHistory = false
            return consoleDockDrag.provider(scope: projectID)
        } preview: { ConsoleDockDragPreview() }
    }

    private var consoleDebuggerControls: some View {
        HStack(spacing: 7) {
            Button("Step") { debuggerCommand("s") }.help("Step into")
            Button("Next") { debuggerCommand("n") }.help("Step over")
            Button("Continue") { debuggerCommand("c") }
            Button("Stop") { debuggerCommand("q") }
        }.controlSize(.small).disabled(kernel.inputPrompt == nil).fixedSize()
    }

    private func consoleHeaderActions(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(ConsolePlacement.allCases) { placement in
                    Button { placeConsole(placement) } label: {
                        Label(placement.title, systemImage: layout.consolePlacement == placement ? "checkmark" : placement.symbol)
                    }
                }
            } label: {
                if compact { Image(systemName: "rectangle.bottomthird.inset.filled") }
                else { Label("Dock", systemImage: "rectangle.bottomthird.inset.filled") }
            }.menuStyle(.borderlessButton).fixedSize()
                .help("Choose where the Command Console is docked").accessibilityLabel("Dock console")
            Button { showFigures = true } label: {
                if compact { Image(systemName: "chart.xyaxis.line") }
                else { Label("Figures (\(figures.count))", systemImage: "chart.xyaxis.line") }
            }.help("Figures (\(figures.count)) · Open saved previews from code and workspace plots")
                .accessibilityLabel("Figures (\(figures.count))")
            Button { showHistory.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }
                .help("Command history").accessibilityLabel("Command history")
            Button { console = ""; consoleDisplayPlaceholders.removeAll() } label: { Image(systemName: "trash") }
                .help("Clear console display").accessibilityLabel("Clear console display")
        }.buttonStyle(.plain).font(.caption).fixedSize()
    }

    private func openVariable(_ variable: WorkspaceVariable) {
        if !variableTabs.contains(where: { $0.id == variable.id }) { variableTabs.append(variable) }
        selectedVariable = variable; showVariables = true
    }

    func saveVariable(_ variable: WorkspaceVariable) {
        guard let ext = variable.exportExtension else { return }
        let panel = NSSavePanel()
        panel.title = "Save Variable"
        panel.directoryURL = project
        panel.message = "Choose a format for \(variable.name). Excel files require an installed Excel engine."
        panel.nameFieldStringValue = variable.name + "." + ext
        panel.canCreateDirectories = true
        var extensions = [ext]
        if variable.type == "ndarray" || variable.type == "DataFrame" || variable.type == "Series" { extensions += ["csv", "xlsx"] }
        if variable.type == "ndarray" || ["int", "float", "complex", "bool", "str"].contains(variable.type) { extensions.append("mat") }
        var seen = Set<String>()
        panel.allowedContentTypes = extensions.filter { seen.insert($0).inserted }.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard extensions.contains(url.pathExtension.lowercased()) else { errorMessage = "Choose one of the supported formats."; return }
        guard let replaceExisting = confirmReplacement(at: url) else { return }
        kernel.exportVariable(name: variable.name, path: url.path, replaceExisting: replaceExisting, scopeID: variable.scopeID) { error in
            if let error { errorMessage = "Could not save \(variable.name): \(error)" }
            else { console += "\n[Saved \(variable.name) to \(url.path)]\n"; reloadFiles() }
        }
    }
    func plotVariable(_ variable: WorkspaceVariable) {
        kernel.plotVariable(name: variable.name, scopeID: variable.scopeID) { data, error in
            if let error { errorMessage = "Could not plot \(variable.name): \(error)" }
            else if let data {
                appendFigure(VariablePlot(name: variable.name + (variable.scopeID.flatMap { workspaceCellNames[$0] }.map { " · " + $0 } ?? ""), data: data, sourceName: variable.name, scopeID: variable.scopeID))
                showFigures = true
            }
        }
    }

    func runCell(_ id: String, _ source: String) {
        guard debugRequestID == nil else { errorMessage = "Finish the debugger before running another cell."; return }
        guard notebook.cells.first(where: { $0.id == id })?.cellType == "code" else { return }
        guard kernel.state == "Ready" || kernel.state == "Busy" else {
            errorMessage = "The Python kernel is not ready yet. " + kernel.state
            return
        }
        let requestID = executionID(notebooks.selectedID, id)
        guard !runningCells.contains(requestID) else {
            errorMessage = "This cell is already running or queued. Wait for it to finish before running it again."
            return
        }
        pendingClear.remove(requestID)
        notebook.clearOutputs(id)
        runningCells.insert(requestID)
        executionStarted[requestID] = Date()
        notebook.runningCellIDs.insert(id)
        notebook.executionTimes[id] = nil
        kernel.execute(code: source, id: requestID, scopeID: requestID,
            scriptPath: notebook.cells.first(where: { $0.id == id }).flatMap(ImportedScriptContext.path(for:)))
    }
    func runSelected() {
        if let id = notebook.selectedID, let cell = notebook.cells.first(where: { $0.id == id }) {
            runCell(id, cell.source)
        }
    }
    private func runSelection(_ cellID: String, _ source: String) {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard debugRequestID == nil, kernel.inputPrompt == nil,
              kernel.state == "Ready" || kernel.state == "Busy" else {
            errorMessage = "Finish any pending input or debugging and wait for the Python kernel to be ready."; return
        }
        let name = notebook.cells.first(where: { $0.id == cellID })?.name ?? "Cell"
        layout.showConsole = true
        console += "\n[Selection · " + name + "]\n" + source + "\n"
        let id = "console-selection-" + UUID().uuidString
        consoleIDs.insert(id); executionStarted[id] = Date()
        kernel.execute(code: source, id: id, source: .cell, originID: executionID(notebooks.selectedID, cellID), scopeID: executionID(notebooks.selectedID, cellID),
            scriptPath: notebook.cells.first(where: { $0.id == cellID }).flatMap(ImportedScriptContext.path(for:)))
    }

    private func liveFigure(for displayID: String) -> LiveFigure? {
        figures.first(where: { $0.liveFigure?.displayID == displayID })?.liveFigure
            ?? notebooks.tabs.lazy.compactMap { $0.store.displayFigures[displayID] }.first
    }
    @discardableResult private func retainFigure(_ image: String, label: String, displayID: String? = nil, liveFigure: LiveFigure? = nil) -> Bool {
        guard let data = Data(base64Encoded: image, options: .ignoreUnknownCharacters) else { return false }
        if let displayID, let existing = figures.first(where: { $0.liveFigure?.displayID == displayID })?.liveFigure {
            return existing.update(data: data)
        }
        let live = liveFigure ?? displayID.flatMap { LiveFigure(displayID: $0, data: data) }
        if let live {
            guard live.update(data: data) else { return false }
        } else if NSImage(data: data) == nil { return false }
        addDisplayFigure(label: label, data: data, live: live)
        return true
    }
    private func addDisplayFigure(label: String, data: Data, live: LiveFigure?) {
        appendFigure(VariablePlot(name: label + " · Figure " + String(nextFigureNumber), data: data, liveFigure: live))
        nextFigureNumber += 1
    }
    private func displayOutput(for event: KernelEvent) -> [String: Any]? {
        guard let data = event.displayData else { return nil }
        var output: [String: Any] = ["output_type": event.count == nil ? "display_data" : "execute_result",
            "data": data, "metadata": event.displayMetadata ?? [:]]
        if let count = event.count { output["execution_count"] = count }
        return output
    }
    private func updateLiveDisplay(_ displayID: String, output: [String: Any], announceConsoleFigure: Bool = true) {
        let galleryFigure = figures.first(where: { $0.liveFigure?.displayID == displayID })?.liveFigure
        let fromConsole = consoleDisplayPlaceholders.contains(displayID)
        NotebookStore.updateDisplayOutputs(displayID: displayID, output: output, stores: notebooks.tabs.map(\.store),
            galleryFigure: galleryFigure, consolePlaceholder: fromConsole) { label, frame in
            addDisplayFigure(label: label, data: frame.data, live: frame)
            if fromConsole {
                consoleDisplayPlaceholders.removeAll { $0 == displayID }
                if announceConsoleFigure { console += "[Figure available in Figures (" + String(figures.count) + ").]\n" }
            }
        }
    }
    private func detachLiveDisplays() {
        consoleDisplayPlaceholders.removeAll()
        for tab in notebooks.tabs {
            for figure in tab.store.displayFigures.values { figure.markSnapshot() }
            tab.store.resetLiveDisplays()
        }
        for index in figures.indices {
            if let live = figures[index].liveFigure {
                figures[index].data = live.data
                live.markSnapshot()
                figures[index].liveFigure = nil
            }
        }
    }

    private func appendFigure(_ figure: VariablePlot) {
        figures.append(figure)
        if figures.count > Self.figureLimit { figures.removeFirst(figures.count - Self.figureLimit) }
    }

    func runCommand() {
        if kernel.inputPrompt != nil {
            let value = command
            let secret = kernel.inputIsPassword
            command = ""
            if !secret { console += value + "\n" }
            kernel.replyToInput(value)
            return
        }
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard kernel.state == "Ready" || kernel.state == "Busy" else {
            errorMessage = "The Python kernel is not ready yet. " + kernel.state
            return
        }
        if commandHistory.last != text { commandHistory.append(text) }
        if commandHistory.count > 500 { commandHistory.removeFirst(commandHistory.count - 500) }
        historyIndex = nil; historyDraft = ""
        command = ""
        console += "\nIn ❯ " + text + "\n"
        let id = "console-" + UUID().uuidString
        consoleIDs.insert(id); executionStarted[id] = Date()
        kernel.execute(code: text, id: id, source: .console, scopeID: activeCellScopeID)
    }
    private func debuggerCommand(_ command: String) {
        guard debugRequestID != nil, kernel.inputPrompt != nil else { return }
        console += command + "\n"
        kernel.replyToInput(command)
    }
    private func debugSelected() {
        guard debugRequestID == nil else { errorMessage = "A debugging session is already active."; return }
        guard kernel.state == "Ready", let id = notebook.selectedID,
              let cell = notebook.cells.first(where: { $0.id == id }), cell.cellType == "code" else {
            errorMessage = "Select a code cell and wait for the kernel to become ready."; return
        }
        guard let literal = pythonLiteral(cell.source), let fileLiteral = pythonLiteral("<pylab-" + id + ">") else { return }
        let points = (notebook.breakpoints[id] ?? []).sorted().map(String.init).joined(separator: ", ")
        let script = """
        import pdb as _pylab_debugger, linecache as _pylab_linecache
        _pylab_debug_source = \(literal)
        _pylab_debug_file = \(fileLiteral)
        _pylab_linecache.cache[_pylab_debug_file] = (len(_pylab_debug_source), None, _pylab_debug_source.splitlines(True), _pylab_debug_file)
        _pylab_debug_session = _pylab_debugger.Pdb()
        for _pylab_debug_line in [\(points)]:
            _pylab_debug_error = _pylab_debug_session.set_break(_pylab_debug_file, _pylab_debug_line)
            if _pylab_debug_error: print(_pylab_debug_error)
        _pylab_debug_session.run(compile(_pylab_debug_source, _pylab_debug_file, 'exec'), globals(), globals())
        """
        let requestID = executionID(notebooks.selectedID, id)
        debugRequestID = requestID; runningCells.insert(requestID); executionStarted[requestID] = Date()
        notebook.runningCellIDs.insert(id); notebook.executionTimes[id] = nil; notebook.clearOutputs(id)
        layout.showConsole = true
        console += "\n[Debugger started. Use Step, Next, Continue, or type PDB commands such as p variable.]\n"
        kernel.execute(code: script, id: requestID, scopeID: requestID, scriptPath: ImportedScriptContext.path(for: cell))
    }
    private func navigateHistory(_ direction: Int) {
        guard !commandHistory.isEmpty else { return }
        if historyIndex == nil { historyDraft = command }
        let current = historyIndex ?? commandHistory.count
        let next = min(max(current + direction, 0), commandHistory.count)
        historyIndex = next == commandHistory.count ? nil : next
        command = historyIndex.map { commandHistory[$0] } ?? historyDraft
    }
    private func pythonLiteral(_ value: String) -> String? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
    private func importMAT() {
        guard kernel.state == "Ready", kernel.inputPrompt == nil, debugRequestID == nil else {
            errorMessage = "Wait for the kernel to be ready before importing data."; return
        }
        let panel = NSOpenPanel(); panel.directoryURL = project; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["mat", "npy", "csv", "xlsx", "xls"].compactMap { UTType(filenameExtension: $0) }
        if kernel.variableMode == .independent { panel.message = "Import data into the selected cell’s workspace." }
        if panel.runModal() == .OK { importDataFiles(panel.urls) }
    }
    private func importDataFiles(_ urls: [URL]) {
        guard kernel.state == "Ready", kernel.inputPrompt == nil, debugRequestID == nil else {
            errorMessage = "Wait for running code or pending input to finish before importing data."; return
        }
        let scope = activeCellScopeID
        for url in urls {
            guard url.isFileURL, ProjectBrowserFiles.supportedDataExtensions.contains(url.pathExtension.lowercased()),
                  let literal = pythonLiteral(url.path) else { continue }
            let id = "console-" + UUID().uuidString
            consoleIDs.insert(id); executionStarted[id] = Date()
            console += "\n[Importing data file: " + url.path + "]\n"
            kernel.execute(code: "_pylab_import_data(" + literal + ")", id: id, source: .console, scopeID: scope)
        }
        layout.showConsole = true
    }
    private func handleDroppedFiles(_ incoming: [URL]) {
        guard !openingFiles, pendingFolder == nil else { return }
        let urls = ProjectBrowserFiles.unique(incoming)
        guard !urls.isEmpty else { return }
        let kinds = urls.map { ProjectBrowserFiles.kind(of: $0) }
        guard !kinds.contains(.unsupported) else {
            errorMessage = "Drop a folder, notebooks (.ipynb), Python scripts (.py/.pyw), or data files (.csv, .npy, .mat, .xlsx, .xls)."; return
        }
        if kinds.contains(.folder) {
            guard urls.count == 1 else { errorMessage = "Drop a folder on its own to change the working directory."; return }
            navigateToFolder(urls[0]); return
        }
        if kinds.contains(.data) {
            guard kinds.allSatisfy({ $0 == .data }) else {
                errorMessage = "Drop data files separately from notebooks and scripts so the destination cell is clear."; return
            }
            importDataFiles(urls)
        } else { openCodeFiles(urls) }
    }
    private func choosePythonScripts() {
        let panel = NSOpenPanel(); panel.directoryURL = project; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["py", "pyw"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Import Python scripts as unexecuted notebook cells. Original files stay in place."
        if panel.runModal() == .OK { openCodeFiles(panel.urls) }
    }
    private func openCodeFiles(_ urls: [URL]) {
        guard !openingFiles else { return }
        openingFiles = true
        Task { @MainActor in
            defer { openingFiles = false }
            for url in urls {
                guard isWorkbenchVisible else { return }
                if url.pathExtension.lowercased() == "ipynb" { loadNotebook(url); continue }
                do {
                    let imported = try await Task.detached { try PythonScriptImport.read(url) }.value
                    guard isWorkbenchVisible else { return }
                    let store = NotebookStore()
                    let cell = NotebookCell(name: imported.cellName, source: imported.source,
                        original: ["metadata": [ImportedScriptContext.metadataKey: imported.sourcePath]])
                    store.cells = [cell]; store.selectedID = cell.id; store.isDirty = true
                    notebooks.addLoaded(store, untitledName: imported.title)
                    console += "\n[Imported " + url.lastPathComponent + " as an unexecuted notebook.]\n"
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }
    private func confirmReplacement(at url: URL) -> Bool? {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let alert = NSAlert()
        alert.messageText = "Replace \(url.lastPathComponent)?"
        alert.informativeText = "The existing file will be replaced with the exported data."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Replace")
        return alert.runModal() == .alertSecondButtonReturn ? true : nil
    }
    private func exportMAT() {
        guard kernel.state == "Ready", debugRequestID == nil else { errorMessage = "Wait for the kernel to be ready before exporting data."; return }
        let panel = NSSavePanel(); panel.directoryURL = project; panel.nameFieldStringValue = "workspace.mat"
        if kernel.variableMode == .independent { panel.message = "Export variables from the selected cell’s independent workspace." }
        if let mat = UTType(filenameExtension: "mat") { panel.allowedContentTypes = [mat] }
        guard panel.runModal() == .OK, let path = panel.url?.path, let literal = pythonLiteral(path) else { return }
        guard let shouldReplace = confirmReplacement(at: URL(fileURLWithPath: path)) else { return }
        let replace = shouldReplace ? "True" : "False"
        let code = "_pylab_export_mat(" + literal + ", replace_existing=" + replace + ")"
        let id = "console-" + UUID().uuidString; consoleIDs.insert(id); executionStarted[id] = Date()
        console += "\n[Exporting workspace to MAT: " + path + "]\n"
        kernel.execute(code: code, id: id, source: .console, scopeID: activeCellScopeID)
    }
    private func syncExecutionIndicators() {
        let activities = Array(kernel.executionActivities.values)
        for tab in notebooks.tabs {
            var mapped: [String: KernelExecutionActivity] = [:]
            for cell in tab.store.cells {
                if let activity = KernelExecutionActivity.representative(forOriginID: executionID(tab.id, cell.id), in: activities) {
                    mapped[cell.id] = activity
                }
            }
            if tab.store.cellExecutionActivity != mapped { tab.store.cellExecutionActivity = mapped }
            let pending = Set(mapped.keys)
            if tab.store.runningCellIDs != pending { tab.store.runningCellIDs = pending }
        }
        onExecutionPhaseChanged(KernelExecutionActivity.representative(in: activities)?.phase)
    }
    private func executionID(_ notebookID: UUID, _ cellID: String) -> String {
        notebookID.uuidString + "|" + cellID
    }
    func receive(_ event: KernelEvent) {
        // Display handles can update existing outputs from another cell, or
        // from a background timer after their original request has finished.
        if event.isDisplayUpdate {
            if let displayID = event.displayID, let output = displayOutput(for: event) {
                updateLiveDisplay(displayID, output: output)
            }
            return
        }
        guard let id = event.id else { return }
        if event.type == "status" {
            if event.text == "busy", let started = kernel.executionActivities[id]?.startedAt { executionStarted[id] = started }
            return
        }
        if event.type == "execute_input", let started = kernel.executionActivities[id]?.startedAt { executionStarted[id] = started }
        if event.type == "finished" {
            if event.id == debugRequestID { debugRequestID = nil; console += "\n[Debugger finished.]\n" }
            consoleIDs.remove(id); pendingClear.remove(id); runningCells.remove(id)
            let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, let notebookID = UUID(uuidString: parts[0]),
               let target = notebooks.tabs.first(where: { $0.id == notebookID })?.store {
                target.runningCellIDs.remove(parts[1])
                if let start = executionStarted.removeValue(forKey: id) { target.executionTimes[parts[1]] = Date().timeIntervalSince(start) }
            } else { executionStarted[id] = nil }
            return
        }
        if consoleIDs.contains(id) {
            if let output = displayOutput(for: event), let displayID = event.displayID {
                updateLiveDisplay(displayID, output: output, announceConsoleFigure: false)
                // Keep a bounded set of console placeholders for late image updates.
                if event.image == nil && liveFigure(for: displayID) == nil {
                    consoleDisplayPlaceholders.removeAll { $0 == displayID }
                    consoleDisplayPlaceholders.append(displayID)
                    if consoleDisplayPlaceholders.count > Self.figureLimit { consoleDisplayPlaceholders.removeFirst() }
                }
            }
            if let image = event.image {
                let existing = event.displayID.flatMap { liveFigure(for: $0) }
                if retainFigure(image, label: "Console", displayID: event.displayID, liveFigure: existing) {
                    console += "[Figure available in Figures (" + String(figures.count) + ").]\n"
                }
            } else if let text = event.text { console += text + (text.hasSuffix("\n") ? "" : "\n") }
            return
        }
        let pieces = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard pieces.count == 2, let notebookID = UUID(uuidString: pieces[0]),
              let target = notebooks.tabs.first(where: { $0.id == notebookID })?.store else { return }
        let cellID = pieces[1]
        let outputText = (id == debugRequestID ? event.text?.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression) : event.text)
        if id == debugRequestID, let text = outputText { console += text + (text.hasSuffix("\n") ? "" : "\n") }
        if event.type == "clear_output" {
            if event.wait == true { pendingClear.insert(id) } else { target.clearDisplayOutputs(cellID) }
            return
        }
        if pendingClear.contains(id), ["stream", "result", "image", "display", "error"].contains(event.type) {
            target.clearDisplayOutputs(cellID); pendingClear.remove(id)
        }
        if let count = event.count { target.setExecutionCount(cellID, count: count) }
        if let output = displayOutput(for: event) {
            if let displayID = event.displayID { updateLiveDisplay(displayID, output: output) }
            let existing = event.displayID.flatMap { liveFigure(for: $0) }
            let live = target.appendDisplayOutput(cellID, output: output, displayID: event.displayID, liveFigure: existing)
            if let image = event.image {
                retainFigure(image, label: target.cells.first(where: { $0.id == cellID })?.name ?? "Notebook",
                    displayID: event.displayID, liveFigure: live)
            }
        } else if let output = event.notebookTextOutput {
            target.appendOutput(cellID, output: output)
        }
    }
    func restartKernel() {
        let alert = NSAlert()
        alert.messageText = "Restart the kernel?"
        alert.informativeText = "Live variables will be cleared. Notebook cells and outputs will remain."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { runningCells.removeAll(); executionStarted.removeAll(); pendingClear.removeAll(); debugRequestID = nil;
            for tab in notebooks.tabs { tab.store.runningCellIDs.removeAll() }
            kernel.stop(); kernel.start(cwd: project) }
    }
    private func askName(_ title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else {
            errorMessage = "Enter a valid file or folder name."; return nil
        }
        return name
    }
    private func createFolder() {
        guard let name = askName("New Folder", initial: "Untitled Folder") else { return }
        do { try FileManager.default.createDirectory(at: project.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: false); reloadFiles() }
        catch { errorMessage = error.localizedDescription }
    }
    private func renameItem(_ item: ProjectItem) {
        guard let name = askName("Rename", initial: item.url.lastPathComponent) else { return }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(name)
        guard destination != item.url else { return }
        // Renaming an open notebook would invalidate its save path.
        let originalPath = item.url.standardizedFileURL.path
        let affectsOpenNotebook = notebooks.tabs.contains { tab in
            guard let path = tab.store.fileURL?.standardizedFileURL.path else { return false }
            return path == originalPath || (item.isDirectory && path.hasPrefix(originalPath + "/"))
        }
        if affectsOpenNotebook { errorMessage = "Close the affected notebook tabs before renaming this item."; return }
        do { try FileManager.default.moveItem(at: item.url, to: destination); reloadFiles() }
        catch { errorMessage = error.localizedDescription }
    }
    private func duplicateItem(_ item: ProjectItem) {
        let parent = item.url.deletingLastPathComponent()
        let ext = item.url.pathExtension
        let base = ext.isEmpty ? item.url.lastPathComponent : item.url.deletingPathExtension().lastPathComponent
        var n = 1, destination: URL
        repeat {
            let suffix = n == 1 ? " copy" : " copy \(n)"
            let name = base + suffix + (ext.isEmpty ? "" : "." + ext)
            destination = parent.appendingPathComponent(name); n += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        do { try FileManager.default.copyItem(at: item.url, to: destination); reloadFiles() }
        catch { errorMessage = error.localizedDescription }
    }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            navigateToFolder(url, selectsProject: true)
        }
    }
    func navigateToFolder(_ url: URL, selectsProject: Bool = false) {
        changeFolder(to: url, recordsHistory: true) {
            if selectsProject { onProjectSelected(url) }
        }
    }
    private func changeFolder(to url: URL, recordsHistory: Bool, didChange: @escaping () -> Void = {}) {
        let target = URL(fileURLWithPath: (url.path as NSString).standardizingPath, isDirectory: true)
        guard pendingFolder == nil else { return }
        guard target.path != (project.path as NSString).standardizingPath else { didChange(); return }
        let previous = project
        pendingFolder = target
        kernel.changeDirectory(to: target) { error in
            pendingFolder = nil
            guard error == nil else {
                errorMessage = "Could not open " + target.path + ": " + (error ?? "Unknown folder error")
                return
            }
            // Commit the browser and history only once Python has accepted it.
            if recordsHistory { projectHistory.append(previous) }
            project = target
            reloadFiles()
            didChange()
        }
    }
    func goBackFolder() {
        guard let previous = projectHistory.last else { return }
        changeFolder(to: previous, recordsHistory: false) { _ = projectHistory.popLast() }
    }
    func goToParentFolder() {
        let path = (project.path as NSString).standardizingPath
        guard path != "/" else { return }
        navigateToFolder(URL(fileURLWithPath: (path as NSString).deletingLastPathComponent, isDirectory: true))
    }
    func reloadFiles() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .map { ProjectItem(url: $0) }
                .sorted { if $0.isDirectory != $1.isDirectory { return $0.isDirectory }; return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        } catch {
            files = []
            errorMessage = "Could not read the project folder: " + error.localizedDescription
        }
    }
    func openProjectItem(_ item: ProjectItem) {
        switch ProjectBrowserFiles.kind(of: item.url) {
        case .folder: navigateToFolder(item.url)
        case .notebook, .pythonScript: openCodeFiles([item.url])
        case .data: importDataFiles([item.url])
        case .unsupported: break
        }
    }
    func newNotebook() { notebooks.add() }
    private var notebookTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Notebook")
                    .font(.subheadline.weight(.semibold))
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(notebooks.tabs) { tab in
                            HStack(spacing: 4) {
                                Button { notebooks.selectedID = tab.id } label: {
                                    HStack(spacing: 6) {
                                        if let activity = KernelExecutionActivity.representative(in: Array(tab.store.cellExecutionActivity.values)) {
                                            ExecutionIndicator(phase: activity.phase, compact: true)
                                        } else { Image(systemName: "doc.text") }
                                        Text(tab.title).lineLimit(1).frame(maxWidth: 160)
                                        if tab.store.isDirty { Circle().frame(width: 5, height: 5).help("Unsaved changes") }
                                    }.padding(.leading, 10).padding(.vertical, 7)
                                }.buttonStyle(.plain).accessibilityLabel("Notebook: " + tab.title)
                                    .accessibilityValue(KernelExecutionActivity.representative(in: Array(tab.store.cellExecutionActivity.values)).map { ExecutionIndicator.label(for: $0.phase) } ?? "Idle")
                                    .accessibilityAddTraits(notebooks.selectedID == tab.id ? [.isSelected] : [])
                                if notebooks.tabs.count > 1 {
                                    Button { closeNotebook(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).padding(6) }
                                        .buttonStyle(.plain).accessibilityLabel("Close notebook " + tab.title)
                                }
                            }
                            .padding(.trailing, 4)
                            .background {
                                if notebooks.selectedID == tab.id {
                                    if reduceMotion {
                                        RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.18))
                                    } else {
                                        RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.18))
                                            .matchedGeometryEffect(id: "selected-notebook", in: notebookSelectionNamespace)
                                    }
                                }
                            }
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 9))
                            .glassEffectID(tab.id, in: notebookGlassNamespace)
                            .magneticDropFeedback(isTargeted: notebooks.dragState.targetID == tab.id, cornerRadius: 9)
                            .onDrag { notebooks.dragState.provider(id: tab.id) }
                            .onDrop(of: [tabDragType], delegate: TabReorderDrop(state: notebooks.dragState, target: tab.id, reduceMotion: reduceMotion) { notebooks.move($0, to: $1) })
                            .contextMenu {
                                Button { showNotebookInFinder(tab.store.fileURL) } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                                .disabled(tab.store.fileURL == nil)
                                .help(tab.store.fileURL?.deletingLastPathComponent().path ?? "Save this notebook first to show its location in Finder")
                                Divider()
                                Button("Move Notebook Left") { withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { notebooks.step(tab.id, by: -1) } }
                                Button("Move Notebook Right") { withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { notebooks.step(tab.id, by: 1) } }
                            }
                            .help("Drag to reorder · " + tab.title)
                        }
                    }
                    .animation(LiquidMotion.transition(reduceMotion: reduceMotion), value: notebooks.tabs.map(\.id))
                    .animation(LiquidMotion.feedback(reduceMotion: reduceMotion), value: notebooks.selectedID)
                    .padding(.vertical, 8).padding(.leading, 10)
                    }
                }
                .scrollIndicators(.automatic, axes: .horizontal)
                Button { newNotebook() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).padding(8).help("New notebook").accessibilityLabel("New notebook")
            }.background(.bar)
            Divider()
        }
    }
    private func showNotebookInFinder(_ url: URL?) {
        guard let url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        // The file may have moved or been deleted since it was opened. Its
        // containing folder is still useful when it remains available.
        let folder = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue, NSWorkspace.shared.open(folder) else {
            errorMessage = "This notebook’s folder is no longer available: " + folder.path
            return
        }
    }

    private func closeNotebook(_ id: UUID) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard let tab = notebooks.tabs.first(where: { $0.id == id }) else { return }
        let running = !tab.store.cellExecutionActivity.isEmpty || runningCells.contains { $0.hasPrefix(id.uuidString + "|") }
        if tab.store.isDirty || running {
            let alert = NSAlert()
            alert.messageText = "Close \(tab.title)?"
            alert.informativeText = "Unsaved notebook changes will be lost. Running code will continue in the shared project kernel, but its output will no longer appear in this notebook."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Close Notebook")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        notebooks.remove(id)
    }
    func saveNotebookAs() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        let panel = NSSavePanel(); panel.nameFieldStringValue = notebook.fileURL?.lastPathComponent ?? suggestedNotebookFilename
        panel.directoryURL = notebook.fileURL?.deletingLastPathComponent() ?? project
        if let type = UTType(filenameExtension: "ipynb") { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveSelectedNotebook(to: url)
    }
    private func saveSelectedNotebook(to url: URL) {
        if let other = notebooks.find(url: url), other.id != notebooks.selectedID {
            errorMessage = "That notebook is already open in another tab. Choose a different file name."
            return
        }
        do { try notebook.save(to: url); reportNotebookState(); reloadFiles() } catch { errorMessage = error.localizedDescription }
    }
    private func saveAllNotebooks() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        var saved = 0
        for tab in notebooks.tabs where tab.store.isDirty {
            var destination = tab.store.fileURL
            if destination == nil {
                let panel = NSSavePanel()
                panel.title = "Save " + tab.title
                panel.nameFieldStringValue = tab.title.hasSuffix(".ipynb") ? tab.title : tab.title + ".ipynb"
                panel.directoryURL = project
                if let type = UTType(filenameExtension: "ipynb") { panel.allowedContentTypes = [type] }
                guard panel.runModal() == .OK, let url = panel.url else { return }
                destination = url
            }
            guard let url = destination else { continue }
            if let existing = notebooks.find(url: url), existing.id != tab.id {
                errorMessage = "That file is already open as another notebook. Save All stopped; choose another name."; return
            }
            do { try tab.store.save(to: url); saved += 1 }
            catch { errorMessage = "Could not save " + tab.title + ": " + error.localizedDescription; return }
        }
        console += "\n[Save All: " + String(saved) + " notebook(s) saved.]\n"
        reportNotebookState()
        reloadFiles()
    }

    func openNotebook() {
        let panel = NSOpenPanel(); panel.directoryURL = project; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["ipynb", "py", "pyw"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Open notebooks or import Python scripts as unexecuted cells."
        if panel.runModal() == .OK { openCodeFiles(panel.urls) }
    }
    func loadNotebook(_ url: URL) {
        if let existing = notebooks.find(url: url) {
            notebooks.selectedID = existing.id
            unavailableNotebookPaths.removeAll { NotebookStore.refersToSameFile(URL(fileURLWithPath: $0), url) }
            reportNotebookState()
            return
        }
        let store = NotebookStore()
        do {
            try store.load(from: url)
            notebooks.addLoaded(store)
            unavailableNotebookPaths.removeAll { NotebookStore.refersToSameFile(URL(fileURLWithPath: $0), url) }
            reportNotebookState()
        } catch { errorMessage = error.localizedDescription }
    }
    private var suggestedNotebookFilename: String {
        let title = notebooks.selected.title
        return title.hasSuffix(".ipynb") ? title : title + ".ipynb"
    }
    func saveNotebook() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        var target = notebook.fileURL
        if target == nil {
            let panel = NSSavePanel(); panel.nameFieldStringValue = suggestedNotebookFilename
            panel.directoryURL = project
            if let type = UTType(filenameExtension: "ipynb") { panel.allowedContentTypes = [type] }
            guard panel.runModal() == .OK else { return }; target = panel.url
        }
        if let target { saveSelectedNotebook(to: target) }
    }
}
