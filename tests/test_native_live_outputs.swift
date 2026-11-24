import SwiftUI
import AppKit

@main struct NativeLiveOutputChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        func png(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Data {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 120,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let bytes = rep.bitmapData!
            for y in 0..<120 { for x in 0..<240 {
                let offset = y * rep.bytesPerRow + x * 4
                bytes[offset] = red; bytes[offset + 1] = green; bytes[offset + 2] = blue; bytes[offset + 3] = 255
            } }
            return rep.representation(using: .png, properties: [:])!
        }
        let first = png(240, 20, 20), last = png(20, 80, 240)
        precondition(first != last, "Image fixtures must differ")
        func output(_ data: Data) -> [String: Any] {
            ["output_type": "display_data", "data": ["image/png": data.base64EncodedString()], "metadata": ["probe": "latest"]]
        }
        checkTextFirstDisplays(first: output(first), next: output(last), latestBytes: last)
        let store = NotebookStore()
        let source = "def example():\n    return 42\n\nprint(example())"
        store.cells = [NotebookCell(id: "code", name: "Live FDTD", source: source), NotebookCell(id: "other", name: "Other")]
        store.selectedID = "code"
        let frame = store.appendDisplayOutput("code", output: output(first), displayID: "live-test")!
        let other = store.appendDisplayOutput("other", output: output(first), displayID: "live-test", liveFigure: frame)!
        precondition(other === frame)
        let secondStore = NotebookStore()
        let secondCell = secondStore.cells[0].id
        _ = secondStore.appendDisplayOutput(secondCell, output: output(first), displayID: "live-test", liveFigure: frame)
        precondition(store.updateDisplayOutput(displayID: "unknown", output: output(last)) == 0)
        precondition(store.cells.allSatisfy { $0.outputs.count == 1 })

        let suite = "org.pylab.tests.live-output." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        let host = NSHostingView(rootView: NotebookSingleCellView(store: store, onRun: { _, _ in }, onComplete: { _, _, _ in }, editorPreferences: preferences))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 760)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled,.resizable], backing: .buffered, defer: false)
        window.contentView = host
        func settle(_ view: NSView = host) { view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25)); view.layoutSubtreeIfNeeded() }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func capture(_ view: NSView, path: String) throws -> Data {
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            let data = rep.representation(using: .png, properties: [:])!
            try data.write(to: URL(fileURLWithPath: path)); return data
        }
        settle()
        let editor = views(host).compactMap { $0 as? NSTextView }.first(where: { String(describing: type(of: $0)) == "CellTextView" })!
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("# retained\n", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing(); settle()
        let editedSource = editor.string, cursor = editor.selectedRange(), height = editor.enclosingScrollView!.frame.height
        precondition(height > 400, "Live plot took too much code space")
        for index in 0..<20 {
            let currentFrame = index.isMultiple(of: 2) ? first : last
            precondition(store.updateDisplayOutput(displayID: "live-test", output: output(currentFrame)) == 2)
            precondition(secondStore.updateDisplayOutput(displayID: "live-test", output: output(currentFrame)) == 1)
            settle()
            let current = views(host).compactMap { $0 as? NSTextView }.first(where: { String(describing: type(of: $0)) == "CellTextView" })!
            precondition(current === editor && current.string == editedSource && current.selectedRange() == cursor)
            precondition(window.firstResponder === editor && current.undoManager?.canUndo == true)
            precondition(abs(current.enclosingScrollView!.frame.height - height) < 0.5)
        }
        precondition(frame.data == last && store.cells.allSatisfy { $0.outputs.count == 1 })
        precondition(NotebookStore.text((store.cells[0].outputs[0]["data"] as? [String: Any])?["image/png"]) == last.base64EncodedString())
        _ = try capture(host, path: "/private/tmp/pylab-live-output-1000.png")
        window.setContentSize(NSSize(width: 420, height: 460)); settle()
        precondition(editor.string == editedSource && editor.enclosingScrollView!.frame.height > 150)
        _ = try capture(host, path: "/private/tmp/pylab-live-output-420.png")
        editor.undoManager?.undo(); precondition(editor.string == source, "Live frames changed native Undo")

        let plot = VariablePlot(name: "Live field", data: last, liveFigure: frame)
        let figureHost = NSHostingView(rootView: VariablePlotView(plot: plot))
        figureHost.sizingOptions = []; figureHost.frame = NSRect(x: 0, y: 0, width: 800, height: 480)
        let figureWindow = NSWindow(contentRect: figureHost.frame, styleMask: [.titled,.resizable], backing: .buffered, defer: false)
        figureWindow.contentView = figureHost
        settle(figureHost)
        let figureSize = figureHost.frame.size
        let before = try capture(figureHost, path: "/private/tmp/pylab-live-figure-before.png")
        _ = frame.update(data: first); settle(figureHost)
        let after = try capture(figureHost, path: "/private/tmp/pylab-live-figure-after.png")
        precondition(before != after && figureHost.frame.size == figureSize, "Open figure did not refresh in-place")
        precondition(frame.data == first)

        let text: [String: Any] = ["output_type": "display_data", "data": ["text/plain": "now text"], "metadata": [:]]
        precondition(store.updateDisplayOutput(displayID: "live-test", output: text) == 2)
        precondition(!frame.isLive && store.liveFigures(for: "code").isEmpty)
        precondition((store.cells[0].outputs[0]["data"] as? [String: Any])?["image/png"] == nil)
        let unsupported: [String: Any] = ["output_type": "display_data", "data": ["text/html": "<b>Only HTML</b>"], "metadata": [:]]
        precondition(store.updateDisplayOutput(displayID: "live-test", output: unsupported) == 2)
        precondition((store.cells[0].outputs[0]["data"] as? [String: Any])?["text/plain"] == nil)
        precondition(store.updateDisplayOutput(displayID: "live-test", output: output(last)) == 2)
        precondition(frame.isLive && frame.data == last)
        precondition(!frame.update(data: Data("invalid PNG".utf8)) && !frame.isLive && frame.data == last)
        _ = frame.update(data: first); precondition(frame.isLive)

        let url = URL(fileURLWithPath: "/private/tmp/pylab-live-" + UUID().uuidString + ".ipynb")
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(to: url)
        let saved = try String(contentsOf: url, encoding: .utf8)
        precondition(!saved.contains("live-test") && !saved.contains("display_id"), "Transient display mapping leaked into notebook")
        store.clearDisplayOutputs("code")
        precondition(store.liveFigures(for: "code").isEmpty && store.updateDisplayOutput(displayID: "live-test", output: output(first)) == 1)
        store.removeCell("other")
        precondition(store.updateDisplayOutput(displayID: "live-test", output: output(first)) == 0)
        try store.load(from: url)
        precondition(store.displayOutputTargets.isEmpty && store.displayFigures.isEmpty)
        _ = store.appendDisplayOutput(store.cells[0].id, output: output(first), displayID: "reset")
        store.newNotebook(); precondition(store.displayOutputTargets.isEmpty && store.displayFigures.isEmpty)
        print("PASS: live output replacement/cross-store IDs, unsupported MIME reset, latest-frame-only state, stable full-figure size, editor focus/source/Undo/code space, PNG persistence and transient cleanup")
    }
    @MainActor private static func checkTextFirstDisplays(first: [String: Any], next: [String: Any], latestBytes: Data) {
        let stores = [NotebookStore(), NotebookStore()]
        let id = "pending-plot"
        let text: [String: Any] = ["output_type": "display_data", "data": ["text/plain": "Computing"]]
        for store in stores {
            let cell = store.cells[0]
            precondition(store.appendDisplayOutput(cell.id, output: text, displayID: id) == nil)
        }

        var added: [LiveFigure] = []
        func update(_ output: [String: Any], displayID: String = id, consolePlaceholder: Bool = false) {
            NotebookStore.updateDisplayOutputs(displayID: displayID, output: output, stores: stores,
                galleryFigure: added.first(where: { $0.displayID == displayID }), consolePlaceholder: consolePlaceholder) { label, figure in
                precondition(label == (consolePlaceholder ? "Console" : stores[0].cells[0].name))
                added.append(figure)
            }
        }
        update(first)
        precondition(added.count == 1, "The first image from a placeholder must enter Figures once")
        let frame = added[0]
        for store in stores {
            precondition(store.displayFigures[id] === frame && store.cells[0].outputs.count == 1)
        }
        update(next)
        precondition(added.count == 1 && frame.data == latestBytes)
        let invalid = ["data": ["image/png": "bm90IGEgcG5n", "text/plain": "No image available"]]
        update(invalid)
        precondition(!frame.isLive && frame.data == latestBytes)
        precondition(stores.allSatisfy { $0.liveFigures(for: $0.cells[0].id).isEmpty })
        update(text)
        update(first)
        precondition(frame.isLive && added.count == 1)

        added.removeAll() // The user closed the gallery tab. Inline updates continue.
        update(next)
        precondition(added.isEmpty && frame.data == latestBytes)
        for store in stores { store.clearDisplayOutputs(store.cells[0].id) }
        update(first)
        update(first, displayID: "unregistered")
        precondition(added.isEmpty)
        update(first, displayID: "console-plot", consolePlaceholder: true)
        update(next, displayID: "console-plot")
        precondition(added.count == 1 && added[0].data == latestBytes)
        print("PASS: text-first notebook and console plots, cross-notebook sharing, invalid PNG fallback, gallery close and cleared targets")
    }

}
