import SwiftUI
import AppKit

@main struct NativeWorkspaceModesCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let a = WorkspaceVariable(name: "x", type: "ndarray", shape: "3", value: "[1, 2, 3]", editable: true,
            originID: "cell-A", exportExtension: "npy", exportLabel: "NumPy", plottable: true, scopeID: "cell-A")
        let b = WorkspaceVariable(name: "x", type: "ndarray", shape: "3", value: "[10, 20, 30]", editable: true,
            originID: "cell-B", exportExtension: "npy", exportLabel: "NumPy", plottable: true, scopeID: "cell-B")
        precondition(a.id != b.id)
        let pane = WorkspacePane(variables: [a,b], cellNames: ["cell-A":"Notebook / Alpha", "cell-B":"Notebook / Beta"],
            cellOrder: ["cell-A", "cell-B"], onRefresh: {}, onOpen: { _ in }, onSave: { _ in }, onPlot: { _ in },
            onInspect: { _, completion in completion(nil, "not used") },
            onRename: { _, _, completion in completion(nil) }, onDelete: { _, completion in completion(nil) },
            variableMode: .independent)
        let host = NSHostingView(rootView: pane)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 620), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        for width in [390.0, 260.0] {
            window.setContentSize(NSSize(width: width, height: 620))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            host.layoutSubtreeIfNeeded()
            let outlines = all(host).compactMap { $0 as? NSOutlineView }
            guard let outline = outlines.first else { preconditionFailure("Missing native variable table") }
            precondition(outline.numberOfRows == 4, "Two scoped x variables and two group headings did not remain distinct: \(outline.numberOfRows)")
            precondition(host.bounds.width == width)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("No native image cache") }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { preconditionFailure("No PNG") }
            try! png.write(to: URL(fileURLWithPath: "/private/tmp/pylab-workspace-modes-\(Int(width)).png"))
            print("PASS: \(Int(width))-point workspace retains \(outline.numberOfRows) scoped rows; image rendered")
        }
    }
}
