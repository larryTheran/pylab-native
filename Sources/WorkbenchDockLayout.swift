import Foundation

/// All panes remain stable siblings; docking changes only their rectangles.
struct WorkbenchDockLayout {
    let effectivePlacement: ConsolePlacement
    let sidebar: CGRect
    let notebook: CGRect
    let workspace: CGRect
    let console: CGRect
    let sidebarDivider: CGRect
    let workspaceDivider: CGRect
    let consoleDivider: CGRect
    let content: CGRect
    let consoleBranchHeight: CGFloat

    init(size: CGSize, panels: WorkbenchPaneLayout, showSidebar: Bool, showWorkspace: Bool,
         showConsole: Bool, placement: ConsolePlacement, consolePreferred: CGFloat) {
        let width = max(0, size.width), height = max(0, size.height)
        let contentX = showSidebar ? panels.sidebar + 5 : 0
        let contentWidth = max(0, width - contentX)
        let workspaceX = width - panels.workspace
        effectivePlacement = placement == .workspaceBottom && !showWorkspace ? .notebookBottom : placement
        consoleBranchHeight = height
        let consoleHeight = showConsole ? min(height, WorkbenchPaneLayout.consoleHeight(preferred: consolePreferred, height: height)) : 0
        let separatorHeight = showConsole ? min(5, max(0, height - consoleHeight)) : 0
        let upperHeight = showConsole ? max(0, height - consoleHeight - separatorHeight) : height
        let notebookHeight = showConsole && effectivePlacement != .workspaceBottom ? upperHeight : height
        let workspaceHeight = showConsole && effectivePlacement != .notebookBottom ? upperHeight : height
        sidebar = showSidebar ? CGRect(x: 0, y: 0, width: panels.sidebar, height: height) : .zero
        sidebarDivider = showSidebar ? CGRect(x: panels.sidebar, y: 0, width: 5, height: height) : .zero
        notebook = CGRect(x: contentX, y: 0, width: panels.notebook, height: notebookHeight)
        workspace = showWorkspace ? CGRect(x: workspaceX, y: 0, width: panels.workspace, height: workspaceHeight) : .zero
        workspaceDivider = showWorkspace ? CGRect(x: workspaceX - 5, y: 0, width: 5,
            height: showConsole && effectivePlacement == .windowBottom ? upperHeight : height) : .zero
        content = CGRect(x: contentX, y: 0, width: contentWidth, height: height)
        if showConsole {
            let x: CGFloat, consoleWidth: CGFloat
            switch effectivePlacement {
            case .workspaceBottom: x = workspaceX; consoleWidth = panels.workspace
            case .notebookBottom: x = contentX; consoleWidth = panels.notebook
            case .windowBottom: x = contentX; consoleWidth = contentWidth
            }
            console = CGRect(x: x, y: max(0, height - consoleHeight), width: consoleWidth, height: consoleHeight)
            consoleDivider = CGRect(x: x, y: upperHeight, width: consoleWidth, height: separatorHeight)
        } else {
            console = .zero
            consoleDivider = .zero
        }
    }
}
