import SwiftUI
import AppKit
final class LayoutMode: ObservableObject { @Published var singleCell = true }
struct LayoutHarness: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var mode: LayoutMode
    var body: some View { NotebookView(store: store, onRun: { _, _ in }, onComplete: { _, _, _ in }, singleCell: mode.singleCell) }
}
@main struct NativeNotebookLayoutTest {
    @MainActor static func main() {
        _ = NSApplication.shared
        let store = NotebookStore()
        store.cells[0].source = "def example():\n    return 42\n\nprint(example())"
        let mode = LayoutMode()
        let view = LayoutHarness(store: store, mode: mode)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
            host.layoutSubtreeIfNeeded()
        }
        func editors(_ view: NSView) -> [NSTextView] {
            var result: [NSTextView] = []
            if let value = view as? NSTextView, String(describing: type(of: value)) == "CellTextView" { result.append(value) }
            for child in view.subviews { result += editors(child) }
            return result
        }
        settle()
        guard let editor = editors(host).first, let scroll = editor.enclosingScrollView else { preconditionFailure("No native editor") }
        let large = scroll.frame.size
        precondition(large.width > 1000 && large.height > 600, "Large editor did not fill pane: \(large)")
        window.setContentSize(NSSize(width: 420, height: 360))
        settle()
        let small = scroll.frame.size
        precondition(small.width >= 330 && small.width <= 400 && small.height >= 160 && small.height < 300, "Compact editor overflow: \(small)")
        precondition(scroll.layer?.masksToBounds == true)
        precondition(editor.string == store.cells[0].source)
        store.cells[0].outputs = [["output_type": "stream", "name": "stdout", "text": "42\n"]]
        settle()
        precondition(scroll.frame.height < small.height && scroll.frame.height >= 110, "Output did not reclaim readable space")
        precondition(editor.string == store.cells[0].source)
        window.setContentSize(NSSize(width: 1100, height: 760))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 4000,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let hugePNG = bitmap.representation(using: .png, properties: [:])!.base64EncodedString()
        store.cells[0].outputs = [["output_type": "display_data", "data": ["image/png": hugePNG], "metadata": [:]]]
        settle()
        let hugeImageCodeHeight = scroll.frame.height
        precondition(hugeImageCodeHeight > 400 && hugeImageCodeHeight > large.height * 0.60,
                     "Huge figure stole code space: \(hugeImageCodeHeight)")
        precondition(editors(host).first === editor)
        let longText = (0..<5000).map { "Output line \($0): value" }.joined(separator: "\n")
        store.cells[0].outputs = [["output_type": "stream", "name": "stdout", "text": longText]]
        settle()
        precondition(abs(scroll.frame.height - hugeImageCodeHeight) < 0.5,
                     "Output content size changed the bounded split")
        precondition(NotebookStore.text(store.cells[0].outputs[0]["text"]) == longText)
        store.cells[0].outputs = []
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("# retained editor\n", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        let selection = editor.selectedRange()
        precondition(editor.undoManager?.canUndo == true)
        mode.singleCell = false
        settle()
        precondition(editors(host).first === editor, "Layout switch replaced native editor")
        precondition(editor.selectedRange() == selection && editor.undoManager?.canUndo == true)
        let compactHeight = scroll.frame.height
        mode.singleCell = true
        settle()
        precondition(editors(host).first === editor && scroll.frame.height > compactHeight)
        precondition(editor.selectedRange() == selection && editor.undoManager?.canUndo == true)
        for index in 1...6 {
            let id = store.addCell(after: store.selectedID)
            if let row = store.cells.firstIndex(where: { $0.id == id }) { store.cells[row].source = "marker_\(index) = \(index)" }
        }
        settle()
        guard let selectedEditor = editors(host).first(where: { $0.string == "marker_6 = 6" }),
              let selectedScroll = selectedEditor.enclosingScrollView else { preconditionFailure("Missing last cell") }
        mode.singleCell = false
        settle()
        let visible = selectedScroll.convert(selectedScroll.bounds, to: host)
        precondition(visible.intersects(host.bounds), "Selected last cell disappeared after expanding: \(visible)")
        precondition(editors(host).contains(where: { $0 === selectedEditor }), "Expanding replaced selected editor")
        mode.singleCell = true
        settle()
        precondition(selectedScroll.convert(selectedScroll.bounds, to: host).intersects(host.bounds))
        print("PASS: native editor resize \(large) -> \(small), bounded huge-image/5000-line output fit, editor identity/undo and last-cell visibility through layout switches")
    }
}
