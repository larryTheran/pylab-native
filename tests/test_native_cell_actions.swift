import SwiftUI
import AppKit

@main struct NativeCellActionChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let store = NotebookStore()
        let alpha = NotebookCell(id: "alpha", name: "Alpha", source: "value = 1\nprint(value)")
        let beta = NotebookCell(id: "beta", name: "Beta", source: "other = 2")
        store.cells = [alpha, beta]; store.selectedID = beta.id
        var selectionRequest: (String, String)?
        let host = NSHostingView(rootView: NotebookView(store: store, onRun: { _, _ in },
            onComplete: { _, _, _ in }, onRunSelection: { selectionRequest = ($0, $1) }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3)); host.layoutSubtreeIfNeeded() }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func editor(source: String) -> NSTextView {
            guard let value = views(host).compactMap({ $0 as? NSTextView }).first(where: {
                String(describing: type(of: $0)) == "CellTextView" && $0.string == source
            }) else { preconditionFailure("Missing expected editor") }
            return value
        }
        func menu(for editor: NSTextView) -> NSMenu {
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            guard let value = editor.menu(for: event) else { preconditionFailure("Missing editor menu") }
            for title in ["Duplicate Cell", "Delete Cell", "Run Selection", "Toggle Line Comment"] {
                precondition(value.items.filter { $0.title == title }.count == 1, "Missing or repeated action: " + title)
            }
            precondition(value.items.contains { $0.action == NSSelectorFromString("copy:") }, "Standard Copy menu was lost")
            precondition(value.items.contains { $0.action == NSSelectorFromString("paste:") }, "Standard Paste menu was lost")
            return value
        }
        func item(_ title: String, in menu: NSMenu) -> NSMenuItem {
            guard let value = menu.items.first(where: { $0.title == title }) else { preconditionFailure("Missing action") }
            return value
        }
        func invoke(_ item: NSMenuItem) {
            guard let action = item.action else { preconditionFailure("Missing selector") }
            precondition(NSApp.sendAction(action, to: item.target, from: item), "Action was not delivered")
        }
        settle()
        let code = editor(source: alpha.source)
        code.setSelectedRange(NSRange(location: 0, length: 5))
        var actions = menu(for: code)
        for _ in 0..<3 { actions = menu(for: code) }
        // AppKit may select the word under the synthetic context-click. Restore
        // the intended selection before checking the existing Run Selection action.
        code.setSelectedRange(NSRange(location: 0, length: 5))
        let run = item("Run Selection", in: actions)
        precondition(code.validateMenuItem(run))
        invoke(run)
        precondition(selectionRequest?.0 == alpha.id && selectionRequest?.1 == "value")
        // Target the inactive Alpha while Beta is the selected cell.
        store.selectedID = beta.id
        invoke(item("Duplicate Cell", in: actions))
        precondition(store.cells.count == 3 && store.cells[0].id == alpha.id && store.cells[2].id == beta.id)
        let copy = store.cells[1]
        precondition(copy.source == alpha.source && copy.id != alpha.id && copy.id != beta.id && store.selectedID == copy.id)
        settle()
        store.runningCellIDs.insert(alpha.id)
        settle()
        let original = editor(source: alpha.source)
        let blocked = item("Delete Cell", in: menu(for: original))
        precondition(!blocked.isEnabled && !original.validateMenuItem(blocked))
        invoke(blocked) // The selector guard must also block programmatic dispatch.
        precondition(store.cells.contains { $0.id == alpha.id } && store.cells.count == 3)
        store.runningCellIDs.remove(alpha.id)
        settle()
        actions = menu(for: original)
        let remove = item("Delete Cell", in: actions)
        precondition(remove.isEnabled && original.validateMenuItem(remove))
        store.selectedID = beta.id
        invoke(remove)
        precondition(!store.cells.contains { $0.id == alpha.id } && store.cells.contains { $0.id == copy.id })
        precondition(store.selectedID == beta.id && store.cells.count == 2)
        print("PASS: native cell menus retain editing actions, avoid repeated items, target inactive cell and block running-cell deletion")
    }
}
