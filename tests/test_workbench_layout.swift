import Foundation
@main struct PaneLayoutChecks {
    static func main() {
        for width in stride(from: 820.0, through: 2400.0, by: 79.0) {
            for sidebar in [false,true] {
                for workspace in [false,true] {
                    let panels=WorkbenchPaneLayout(width: width, sidebarPreferred: 500, workspacePreferred: 900, showSidebar: sidebar, showWorkspace: workspace)
                    let dividers: CGFloat = (sidebar ? 5 : 0) + (workspace ? 5 : 0)
                    precondition(abs(panels.sidebar + panels.workspace + panels.notebook + dividers - width) < 0.001)
                    precondition(panels.notebook >= 359.999)
                    precondition(sidebar ? panels.sidebar >= 169.999 : panels.sidebar == 0)
                    precondition(workspace ? panels.workspace >= 259.999 : panels.workspace == 0)
                }
            }
        }
        let wide=WorkbenchPaneLayout(width: 1450, sidebarPreferred: 220, workspacePreferred: 390, showSidebar: true, showWorkspace: true)
        precondition(wide.sidebar==220 && wide.workspace==390 && wide.notebook==830)
        let compact=WorkbenchPaneLayout(width: 820, sidebarPreferred: 220, workspacePreferred: 390, showSidebar: true, showWorkspace: true)
        precondition(compact.sidebar < 220 && compact.workspace < 390)
        precondition(WorkbenchPaneLayout.consoleHeight(preferred: 700, height: 600)==280)
        precondition(WorkbenchPaneLayout.consoleHeight(preferred: 20, height: 600)==120)
        print("PASS: responsive pane bounds, notebook priority, visibility, preferences, and console limits")
    }
}
