import SwiftUI
import AppKit
@main struct NativeAppearanceTest {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        let store = NotebookStore()
        store.cells[0].source = "def example():\n    return 42\n\nprint(example())"
        let host = NSHostingView(rootView: NotebookSingleCellView(store: store, onRun: { _, _ in }, onComplete: { _, _, _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3)); host.layoutSubtreeIfNeeded() }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views($0) } }
        func editor() -> NSTextView? { views(host).compactMap { $0 as? NSTextView }.first { String(describing: type(of: $0)) == "CellTextView" } }
        settle()
        guard let code = editor(), let scroll = code.enclosingScrollView, let ruler = scroll.verticalRulerView else { preconditionFailure("Missing native editor") }
        let originalSource = code.string
        window.makeFirstResponder(code)
        code.setSelectedRange(NSRange(location: (code.string as NSString).length, length: 0))
        code.insertText("\n# retained text", replacementRange: code.selectedRange())
        code.breakUndoCoalescing()
        settle()
        store.isDirty = false // A theme change must not mark a saved notebook dirty.
        let selected = code.selectedRange(), source = code.string, dirty = store.isDirty
        precondition(code.undoManager?.canUndo == true)
        func keywordColor() -> NSColor {
            guard let color = code.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor,
                  let rgb = color.usingColorSpace(.deviceRGB) else { preconditionFailure("Missing syntax color") }
            return rgb
        }
        let light = keywordColor()
        precondition(code.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        settle()
        let dark = keywordColor()
        precondition(code.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        precondition(ruler.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        precondition(abs(light.greenComponent - dark.greenComponent) > 0.2, "Syntax palette did not change")
        precondition(editor() === code && code.selectedRange() == selected && code.string == source && store.isDirty == dirty)
        precondition(window.firstResponder === code && code.undoManager?.canUndo == true && scroll.rulersVisible)
        NSApp.appearance = NSAppearance(named: .aqua)
        settle()
        let restored = keywordColor()
        precondition(abs(light.redComponent - restored.redComponent) < 0.01 && abs(light.greenComponent - restored.greenComponent) < 0.01)
        precondition(editor() === code && code.selectedRange() == selected && code.undoManager?.canUndo == true)
        NSApp.appearance = nil
        settle()
        precondition(NSApp.appearance == nil && editor() === code && code.string == source)
        code.undoManager?.undo()
        precondition(code.string == originalSource, "Appearance changes altered the text undo sequence")
        print("PASS: app-wide Light/Dark/System switches update native editor/ruler and syntax colors without replacing editor or changing source, focus, selection, dirty state or undo")
    }
}
