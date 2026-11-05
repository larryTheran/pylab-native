import SwiftUI
import AppKit

extension Notification.Name {
    static let projectToolbarAction = Notification.Name("PyLabProjectToolbarAction")
}

final class SharedProjectLayout: ObservableObject {
    @Published var sidebarWidth: CGFloat { didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: "layout.sidebarWidth") } }
    @Published var workspaceWidth: CGFloat { didSet { UserDefaults.standard.set(Double(workspaceWidth), forKey: "layout.workspaceWidth") } }
    @Published var consoleHeight: CGFloat { didSet { UserDefaults.standard.set(Double(consoleHeight), forKey: "layout.consoleHeight") } }
    @Published var consolePlacement: ConsolePlacement { didSet { UserDefaults.standard.set(consolePlacement.rawValue, forKey: "layout.consolePlacement") } }
    @Published var showSidebar: Bool { didSet { UserDefaults.standard.set(showSidebar, forKey: "layout.showSidebar") } }
    @Published var showConsole: Bool { didSet { UserDefaults.standard.set(showConsole, forKey: "layout.showConsole") } }
    @Published var showWorkspace: Bool { didSet { UserDefaults.standard.set(showWorkspace, forKey: "layout.showWorkspace") } }
    init() {
        let d = UserDefaults.standard
        sidebarWidth = d.object(forKey: "layout.sidebarWidth") == nil ? 220 : d.double(forKey: "layout.sidebarWidth")
        workspaceWidth = d.object(forKey: "layout.workspaceWidth") == nil ? 390 : d.double(forKey: "layout.workspaceWidth")
        consoleHeight = d.object(forKey: "layout.consoleHeight") == nil ? 230 : d.double(forKey: "layout.consoleHeight")
        consolePlacement = d.string(forKey: "layout.consolePlacement").flatMap(ConsolePlacement.init(rawValue:)) ?? .workspaceBottom
        showSidebar = d.object(forKey: "layout.showSidebar") == nil ? true : d.bool(forKey: "layout.showSidebar")
        showConsole = d.object(forKey: "layout.showConsole") == nil ? true : d.bool(forKey: "layout.showConsole")
        showWorkspace = d.object(forKey: "layout.showWorkspace") == nil ? true : d.bool(forKey: "layout.showWorkspace")
    }
}

private struct ProjectTab: Identifiable {
    let id = UUID()
    var folder: URL
    var title: String
    var dirty = false
    var hasVariables = false
    var executionPhase: KernelExecutionPhase? = nil
    var notebooks: [String] = []
    var selectedNotebook: String? = nil
    var variableMode: VariableSharingMode = .shared
}

/// Keeps every workbench mounted so its notebook and kernel remain alive while another project is selected.
struct ProjectTabsHost: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var layout = SharedProjectLayout()
    @State private var projects: [ProjectTab]
    @State private var selectedID: UUID
    @StateObject private var projectDragState = TabDragState()
    @Namespace private var projectGlassNamespace
    @Namespace private var projectSelectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCommandPalette = false
    @State private var pendingPaletteAction: (UUID, ProjectToolbarAction)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let data = UserDefaults.standard.data(forKey: "projectSession.v1")
        let saved = data.flatMap { try? JSONDecoder().decode(StoredSession.self, from: $0) }
        // Keep projects whose folders are temporarily unavailable (for example,
        // an external drive). Dropping them here would permanently overwrite
        // their saved tabs as soon as any remaining project updates its state.
        let restored = (saved?.projects ?? []).map {
            let folder = URL(fileURLWithPath: $0.folder)
            return ProjectTab(folder: folder, title: folder.lastPathComponent.isEmpty ? "/" : folder.lastPathComponent,
                              notebooks: $0.notebooks, selectedNotebook: $0.selectedNotebook, variableMode: $0.resolvedVariableMode)
        }
        let projects = restored.isEmpty ? [ProjectTab(folder: home, title: home.lastPathComponent)] : restored
        _projects = State(initialValue: projects)
        _selectedID = State(initialValue: projects[min(max(0, saved?.selectedIndex ?? 0), projects.count - 1)].id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("PROJECTS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 12)
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 5) {
                        ForEach(projects) { project in
                            HStack(spacing: 5) {
                                Button {
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                    selectedID = project.id
                                    persistSession()
                                } label: {
                                    HStack(spacing: 6) {
                                        if let phase = project.executionPhase { ExecutionIndicator(phase: phase, compact: true) }
                                        else { Image(systemName: "folder.fill").font(.caption) }
                                        Text(project.title).lineLimit(1).frame(maxWidth: 140)
                                        if project.dirty { Circle().frame(width: 5, height: 5).help("Unsaved notebook changes") }
                                    }
                                    .padding(.leading, 10).padding(.vertical, 7)
                                }.buttonStyle(.plain)
                                    .accessibilityValue(project.executionPhase.map(ExecutionIndicator.label(for:)) ?? "Idle")
                                if projects.count > 1 {
                                    Button { closeProject(project.id) } label: {
                                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).padding(6)
                                    }.buttonStyle(.plain).help("Close project")
                                        .accessibilityLabel("Close project \(project.title)")
                                }
                            }
                            .padding(.trailing, 4)
                            .background {
                                if selectedID == project.id {
                                    if reduceMotion {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.18))
                                    } else {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.18))
                                            .matchedGeometryEffect(id: "selected-project", in: projectSelectionNamespace)
                                    }
                                }
                            }
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                            .glassEffectID(project.id, in: projectGlassNamespace)
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selectedID == project.id ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 0.8))
                            .magneticDropFeedback(isTargeted: projectDragState.targetID == project.id, cornerRadius: 10)
                            .onDrag { projectDragState.provider(id: project.id) }
                            .onDrop(of: [tabDragType], delegate: TabReorderDrop(state: projectDragState,
                                target: project.id, reduceMotion: reduceMotion, move: moveProject))
                            .contextMenu {
                                Button("Move Project Left") { stepProject(project.id, by: -1) }
                                Button("Move Project Right") { stepProject(project.id, by: 1) }
                            }
                            .help("Drag to reorder · " + project.folder.path)
                        }
                    }
                    .animation(reduceMotion ? nil : LiquidMotion.transition(reduceMotion: false), value: selectedID)
                    .padding(.horizontal, 8).padding(.vertical, 10)
                    }
                }
                .scrollIndicators(.automatic, axes: .horizontal)
                GlassAppearanceToggle(isDark: Binding(
                    get: { appearance.mode.isDark(systemIsDark: colorScheme == .dark) },
                    set: { appearance.select($0 ? .dark : .light) }))
                    .contextMenu { AppearanceModePicker(settings: appearance) }
                    .help("Switch Light / Dark. Right-click to follow macOS appearance.")
                    .padding(.horizontal, 3)
                Button(action: addProject) { Image(systemName: "plus") }
                    .buttonStyle(.glass).controlSize(.small).help("Open another project folder")
                    .accessibilityLabel("Open another project")
                    .padding(.trailing, 10)
            }.background(.ultraThinMaterial)
            Divider()
            ZStack {
                ForEach(projects) { project in
                    Workbench(initialProject: project.folder, projectID: project.id, layout: layout,
                        initialNotebookPaths: project.notebooks, initialSelectedNotebook: project.selectedNotebook,
                        initialVariableMode: project.variableMode,
                        onVariableModeChanged: { updateVariableMode(project.id, $0) },
                        onNotebookStateChanged: { paths, selected in updateNotebooks(project.id, paths, selected) },
                        onProjectSelected: { updateFolder(project.id, $0) },
                        onStatusChanged: { dirty, variables in updateStatus(project.id, dirty, variables) },
                        onExecutionPhaseChanged: { updateExecutionPhase(project.id, $0) })
                        .id(project.id)
                        .opacity(selectedID == project.id ? 1 : 0)
                        .allowsHitTesting(selectedID == project.id)
                        .accessibilityHidden(selectedID != project.id)
                }
            }
        }
        .background(WindowCloseGuard(projectIDs: Set(projects.map(\.id))).frame(width: 0, height: 0))
        .focusedSceneValue(\.pylabProjectCommandTarget, ProjectCommandTarget(send: send, showPalette: { showCommandPalette = true }))
        .sheet(isPresented: $showCommandPalette, onDismiss: dispatchPaletteAction) {
            CommandPaletteView(projectName: projects.first(where: { $0.id == selectedID })?.title ?? "Project") { action in
                // Capture the target before dismissal so a later project switch
                // cannot redirect a command to another live kernel.
                pendingPaletteAction = (selectedID, action)
                showCommandPalette = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { layout.showSidebar.toggle() } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
                Button { send(.open) } label: { Label("Open", systemImage: "folder") }
                Button { send(.save) } label: { Label("Save", systemImage: "square.and.arrow.down") }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showCommandPalette = true } label: { Label("Command Palette", systemImage: "command") }
                    .help("Search commands (⇧⌘P)")
                Button { send(.addCell) } label: { Label("Add Cell", systemImage: "plus") }
                Button { send(.runCell) } label: { Label("Run Cell", systemImage: "play.fill") }
                    .help("Run the selected cell (⌘Return runs highlighted code when editing)")
                Button { send(.interrupt) } label: { Label("Interrupt", systemImage: "stop.fill") }
                Button { send(.kernelSettings) } label: { Label("Python Kernel", systemImage: "cpu") }
                    .help("Choose the Python kernel for the selected project")
                Menu {
                    Button("Command Palette…") { showCommandPalette = true }
                    Button("Find in Notebooks…") { send(.findCells) }
                    Divider()
                    Button("New Notebook") { send(.newNotebook) }
                    Button("Import Python Script…") { send(.importScript) }
                    Button("Save As…") { send(.saveAs) }
                    Button("Save All Notebooks…") { send(.saveAll) }
                    Button("Run Cell and Advance") { send(.runAdvance) }
                    Button("Run All Above") { send(.runAbove) }
                    Button("Run Selected and Below") { send(.runBelow) }
                    Button("Run All Cells") { send(.runAll) }
                    Button("Debug Selected Cell") { send(.debugCell) }
                    Button("Clear Notebook Outputs") { send(.clearOutputs) }
                    Divider()
                    Button("Figures…") { send(.showFigures) }
                    Button("Import Data…") { send(.importMat) }
                    Button("Export Workspace to MAT…") { send(.exportMat) }
                    Divider()
                    Button("Refresh Workspace") { send(.refresh) }
                    Button("Interrupt Kernel") { send(.interrupt) }
                    Button("Restart Kernel") { send(.restart) }
                    Button("Choose Python Kernel…") { send(.kernelSettings) }
                    Divider()
                    Button("Editor Settings…") { send(.editorSettings) }
                    Button("Kernel Activity…") { send(.showActivity) }
                    AppearanceMenu(settings: appearance)
                    Divider()
                    Button("Toggle Console") { send(.toggleConsole) }
                    Button("Toggle Workspace") { send(.toggleWorkspace) }
                    Button("Reset Layout") { send(.resetLayout) }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
    }

    private func dispatchPaletteAction() {
        guard let (projectID, action) = pendingPaletteAction else { return }
        pendingPaletteAction = nil
        DispatchQueue.main.async {
            guard projects.contains(where: { $0.id == projectID }) else { return }
            NotificationCenter.default.post(name: .projectToolbarAction, object: nil,
                userInfo: ["projectID": projectID, "action": action])
        }
    }

    private func send(_ action: ProjectToolbarAction) {
        NotificationCenter.default.post(name: .projectToolbarAction, object: nil,
            userInfo: ["projectID": selectedID, "action": action])
    }

    private func moveProject(_ id: UUID, _ target: UUID) {
        guard let from = projects.firstIndex(where: { $0.id == id }), let to = projects.firstIndex(where: { $0.id == target }), from != to else { return }
        projects.insert(projects.remove(at: from), at: to)
        persistSession()
    }
    private func stepProject(_ id: UUID, by delta: Int) {
        guard let i = projects.firstIndex(where: { $0.id == id }), projects.indices.contains(i + delta) else { return }
        moveProject(id, projects[i + delta].id)
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the new project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let project = ProjectTab(folder: folder, title: folder.lastPathComponent.isEmpty ? "/" : folder.lastPathComponent)
        projects.append(project)
        selectedID = project.id
        persistSession()
    }

    private func closeProject(_ id: UUID) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard projects.count > 1, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let project = projects[index]
        let dirty = project.dirty || PyLabLifecycle.dirtyProjects.contains(id)
        if dirty || project.hasVariables || project.executionPhase != nil {
            let alert = NSAlert()
            alert.messageText = "Close \(project.title)?"
            alert.informativeText = dirty ? "Unsaved notebook changes will be lost, running code will stop, and live variables will be cleared. Save your notebooks before closing if needed." : "Running code will stop and live variables in this project's kernel will be cleared."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Close Project")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        projects.remove(at: index)
        if selectedID == id { selectedID = projects[min(index, projects.count - 1)].id }
        persistSession()
    }

    private func updateFolder(_ id: UUID, _ folder: URL) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].folder = folder
        projects[index].title = folder.lastPathComponent.isEmpty ? "/" : folder.lastPathComponent
        persistSession()
    }
    private func updateVariableMode(_ id: UUID, _ mode: VariableSharingMode) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].variableMode = mode
        persistSession()
    }
    private func updateNotebooks(_ id: UUID, _ paths: [String], _ selected: String?) {
        guard let index = projects.firstIndex(where: { $0.id == id }),
              projects[index].notebooks != paths || projects[index].selectedNotebook != selected else { return }
        projects[index].notebooks = paths; projects[index].selectedNotebook = selected
        persistSession()
    }
    private func persistSession() {
        let saved = StoredSession(projects: projects.map { StoredProject(folder: $0.folder.path, notebooks: $0.notebooks, selectedNotebook: $0.selectedNotebook, variableMode: $0.variableMode) },
                                  selectedIndex: projects.firstIndex(where: { $0.id == selectedID }) ?? 0)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "projectSession.v1") }
    }
    private func updateExecutionPhase(_ id: UUID, _ phase: KernelExecutionPhase?) {
        guard let index = projects.firstIndex(where: { $0.id == id }), projects[index].executionPhase != phase else { return }
        projects[index].executionPhase = phase
    }
    private func updateStatus(_ id: UUID, _ dirty: Bool, _ variables: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == id }),
              projects[index].dirty != dirty || projects[index].hasVariables != variables else { return }
        projects[index].dirty = dirty
        if dirty { PyLabLifecycle.dirtyProjects.insert(id) } else { PyLabLifecycle.dirtyProjects.remove(id) }
        projects[index].hasVariables = variables
    }
}
