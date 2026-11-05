import SwiftUI
import AppKit

@main struct NativeExecutionIndicatorChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let suite = "org.pylab.tests.execution-ui." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        let store = NotebookStore()
        let initial = "for index in range(10):\n    print(index)"
        store.cells = [NotebookCell(id: "code", name: "Simulation", source: initial)]
        store.selectedID = "code"
        let host = NSHostingView(rootView: NotebookSingleCellView(store: store, onRun: { _, _ in },
            onComplete: { _, _, _ in }, editorPreferences: preferences, onInterrupt: {}))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled,.resizable], backing: .buffered, defer: false)
        window.contentView = host
        func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3)); host.layoutSubtreeIfNeeded() }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func editor() -> NSTextView {
            guard let value = views(host).compactMap({ $0 as? NSTextView }).first(where: { String(describing: type(of: $0)) == "CellTextView" }) else { preconditionFailure("Missing editor") }
            return value
        }
        func snapshot(_ name: String) throws {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("Snapshot unavailable") }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { preconditionFailure("PNG unavailable") }
            try png.write(to: URL(fileURLWithPath: "/private/tmp/pylab-cell-" + name + ".png"))
        }
        settle()
        let code = editor()
        window.makeFirstResponder(code)
        code.setSelectedRange(NSRange(location: (code.string as NSString).length, length: 0))
        code.insertText("\n# retained", replacementRange: code.selectedRange())
        code.breakUndoCoalescing(); settle(); store.isDirty = false
        let source = code.string, cursor = code.selectedRange()
        for phase in [KernelExecutionPhase.queued, .running, .waitingForInput] {
            store.runningCellIDs = ["code"]
            store.cellExecutionActivity = ["code": KernelExecutionActivity(id: "request", originID: "book|code", phase: phase,
                queuedAt: Date(timeIntervalSinceNow: -70), startedAt: phase == .queued ? nil : Date(timeIntervalSinceNow: -65))]
            settle()
            precondition(editor() === code && code.string == source && code.selectedRange() == cursor)
            precondition(window.firstResponder === code && !store.isDirty && code.undoManager?.canUndo == true)
            let spinners = views(host).compactMap { $0 as? NSProgressIndicator }
            precondition(spinners.count == (phase == .running && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0), "Only active execution should spin")
            precondition(spinners.allSatisfy(\.isIndeterminate))
            try snapshot(phase.rawValue + "-900")
        }
        for width in [900.0, 360.0] {
            window.setContentSize(NSSize(width: width, height: 650)); settle()
            precondition(editor() === code && code.string == source)
            try snapshot("waiting-\(Int(width))")
        }
        store.cellExecutionActivity = [:]; store.runningCellIDs = []; store.executionTimes["code"] = 2.5
        settle()
        precondition(editor() === code && code.string == source && code.selectedRange() == cursor && !store.isDirty)
        code.undoManager?.undo()
        precondition(code.string == initial, "Execution indicators altered native Undo history")
        precondition(ExecutionIndicator.elapsedText(65) == "1:05" && ExecutionIndicator.elapsedText(-1) == "0:00" && ExecutionIndicator.elapsedText(.infinity) == "0:00")
        precondition(!views(host).contains { $0 is NSProgressIndicator })
        let queued = KernelExecutionActivity(id: "request", originID: "book|code", phase: .queued, queuedAt: Date())
        store.cellExecutionActivity["code"] = queued
        store.removeCell("code")
        precondition(store.cellExecutionActivity.isEmpty)
        store.cellExecutionActivity[store.cells[0].id] = queued
        store.newNotebook()
        precondition(store.cellExecutionActivity.isEmpty)
        let url = URL(fileURLWithPath: "/private/tmp/pylab-runtime-" + UUID().uuidString + ".ipynb")
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(to: url)
        store.cellExecutionActivity[store.cells[0].id] = queued
        try store.load(from: url)
        precondition(store.cellExecutionActivity.isEmpty)
        print("PASS: only running code spins, phase rendering at narrow/wide sizes, finished reset, editor identity/focus/source/Undo, transient cleanup")
    }
}
