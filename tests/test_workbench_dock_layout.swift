// Compile with WorkbenchLayout.swift, WorkbenchDockLayout.swift and the actual ConsolePlacement definition from ConsoleDocking.swift.
import Foundation
@main struct DockGeometryChecks {
    static func main() {
        var checked = 0
        for width in [820.0, 1100, 1450, 2400] {
            for height in [0.0, 60, 350, 540, 900] {
                for sidebar in [false, true] {
                    for workspace in [false, true] {
                        for console in [false, true] {
                            for placement in ConsolePlacement.allCases {
                                let panels = WorkbenchPaneLayout(width: width, sidebarPreferred: 220, workspacePreferred: 390, showSidebar: sidebar, showWorkspace: workspace)
                                let dock = WorkbenchDockLayout(size: CGSize(width: width, height: height), panels: panels, showSidebar: sidebar, showWorkspace: workspace, showConsole: console, placement: placement, consolePreferred: 230)
                                for rect in [dock.sidebar, dock.notebook, dock.workspace, dock.console, dock.sidebarDivider, dock.workspaceDivider, dock.consoleDivider] {
                                    precondition(rect.minX >= 0 && rect.minY >= 0 && rect.width >= 0 && rect.height >= 0)
                                    precondition(rect.maxX <= width + 0.001 && rect.maxY <= height + 0.001, "Pane outside viewport")
                                }
                                for other in [dock.notebook, dock.workspace, dock.sidebar] {
                                    let overlap = dock.console.intersection(other)
                                    precondition(overlap.isNull || overlap.width * overlap.height < 0.001, "Console overlaps another pane")
                                }
                                precondition(dock.notebook.width >= 360 - 0.001)
                                if sidebar { precondition(dock.sidebar.height == height) }
                                if !workspace && placement == .workspaceBottom { precondition(dock.effectivePlacement == .notebookBottom) }
                                if !console { precondition(dock.console == .zero && dock.notebook.height == height) }
                                if console && workspace && placement == .workspaceBottom {
                                    precondition(dock.notebook.height == height && dock.console.minX == dock.workspace.minX)
                                }
                                if console && placement == .windowBottom {
                                    precondition(dock.console.minX == dock.content.minX && dock.console.maxX == width)
                                }
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        print("PASS: " + String(checked) + " dock layouts, bounds, non-overlap, sidebar height, workspace fallback, and hidden console")
    }
}

