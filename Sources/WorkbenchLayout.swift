import Foundation

/// Fits persisted pane preferences into the current window without changing them.
/// The notebook keeps priority when side panels compete for horizontal space.
struct WorkbenchPaneLayout {
    let sidebar: CGFloat
    let workspace: CGFloat
    let notebook: CGFloat

    init(width: CGFloat, sidebarPreferred: CGFloat, workspacePreferred: CGFloat,
         showSidebar: Bool, showWorkspace: Bool) {
        let width = max(0, width)
        let dividers: CGFloat = (showSidebar ? 5 : 0) + (showWorkspace ? 5 : 0)
        let sidebarMinimum: CGFloat = showSidebar ? 170 : 0
        let workspaceMinimum: CGFloat = showWorkspace ? 260 : 0
        let preferredSidebar = showSidebar ? max(sidebarMinimum, sidebarPreferred) : 0
        let preferredWorkspace = showWorkspace ? max(workspaceMinimum, workspacePreferred) : 0
        let minimumTotal = sidebarMinimum + workspaceMinimum
        let budget = max(0, width - 360 - dividers)
        let desiredExtra = preferredSidebar + preferredWorkspace - minimumTotal
        if budget < minimumTotal, minimumTotal > 0 {
            let ratio = budget / minimumTotal
            sidebar = sidebarMinimum * ratio
            workspace = workspaceMinimum * ratio
        } else {
            let fraction = desiredExtra > 0 ? min(1, (budget - minimumTotal) / desiredExtra) : 0
            sidebar = sidebarMinimum + (preferredSidebar - sidebarMinimum) * fraction
            workspace = workspaceMinimum + (preferredWorkspace - workspaceMinimum) * fraction
        }
        notebook = max(0, width - sidebar - workspace - dividers)
    }

    static func consoleHeight(preferred: CGFloat, height: CGFloat) -> CGFloat {
        min(max(preferred, 120), max(120, height - 320))
    }
}
