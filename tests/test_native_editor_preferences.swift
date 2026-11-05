import SwiftUI
import AppKit

@main struct NativeEditorPreferenceChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let suite = "org.pylab.tests.native-editor." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = EditorPreferences(defaults: defaults)
        let store = NotebookStore()
        let firstSource = "def example():\n    value = 42\n    return value\n\nprint(example())"
        store.cells = [NotebookCell(id: "first", source: firstSource), NotebookCell(id: "second", source: "second_value = 7\nprint(second_value)")]
        store.selectedID = "first"
        let host = NSHostingView(rootView: NotebookView(store: store, onRun: { _, _ in }, onComplete: { _, _, _ in }, editorPreferences: settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 900), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35)); host.layoutSubtreeIfNeeded() }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func editors() -> [NSTextView] { views(host).compactMap { $0 as? NSTextView }.filter { String(describing: type(of: $0)) == "CellTextView" } }
        settle()
        precondition(editors().count == 2)
        let originalEditors = editors()
        let code = originalEditors.first { $0.string == firstSource }!
        let scroll = code.enclosingScrollView!, ruler = scroll.verticalRulerView!
        window.makeFirstResponder(code)
        code.setSelectedRange(NSRange(location: (code.string as NSString).length, length: 0))
        code.insertText("\n# retained edit", replacementRange: code.selectedRange())
        code.breakUndoCoalescing()
        settle()
        store.isDirty = false
        let source = code.string, selection = code.selectedRange()
        precondition(code.undoManager?.canUndo == true)
        func keywordColor() -> NSColor {
            (code.layoutManager!.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as! NSColor).usingColorSpace(.deviceRGB)!
        }
        let originalColor = keywordColor()
        settings.setFontSize(22); settings.setPalette(.nord); settings.setShowsIndentGuides(false); settings.setShowsLineNumbers(false)
        settle()
        precondition(editors().count == 2 && originalEditors.allSatisfy { original in editors().contains { $0 === original } })
        precondition(editors().allSatisfy { $0.font?.pointSize == 22 && $0.enclosingScrollView?.rulersVisible == false })
        precondition(code.string == source && code.selectedRange() == selection && window.firstResponder === code && !store.isDirty && code.undoManager?.canUndo == true)
        precondition(keywordColor() != originalColor)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let menu = code.menu(for: event)!
        let comment = menu.items.first { $0.title == "Toggle Line Comment" }!
        precondition(code.validateMenuItem(comment), "Hiding guides disabled Python comments")
        code.setSelectedRange(selection)
        settings.setShowsLineNumbers(true)
        settle()
        precondition(scroll.rulersVisible && ruler.ruleThickness >= 65, "Large-font gutter does not fit its line numbers")
        // Fold a function in the native gutter, then keep the folded source
        // representation and full notebook source across preference changes.
        code.scrollRangeToVisible(NSRange(location: 0, length: 0))
        settle()
        let fragment = code.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let linePoint = ruler.convert(NSPoint(x: code.textContainerOrigin.x, y: fragment.midY + code.textContainerOrigin.y), from: code)
        let windowPoint = ruler.convert(NSPoint(x: ruler.bounds.width - 10, y: linePoint.y), to: nil)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        ruler.mouseDown(with: click)
        settle()
        precondition(code.string.contains("⋯"), "Native function did not fold")
        let folded = code.string
        settings.setFontSize(15); settings.setPalette(.solarized); settings.setShowsLineNumbers(false); settings.setShowsIndentGuides(true)
        settle()
        precondition(code.string == folded && store.cells[0].source == source && !store.isDirty)
        settings.reset()
        settle()
        precondition(code.string == folded && code.font?.pointSize == 13 && scroll.rulersVisible && !store.isDirty)
        // Unfold before proving style changes have not become text undo items.
        code.scrollRangeToVisible(NSRange(location: 0, length: 0))
        settle()
        let fragment2 = code.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let point2 = ruler.convert(NSPoint(x: code.textContainerOrigin.x, y: fragment2.midY + code.textContainerOrigin.y), from: code)
        let windowPoint2 = ruler.convert(NSPoint(x: ruler.bounds.width - 10, y: point2.y), to: nil)
        let click2 = NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint2, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        ruler.mouseDown(with: click2)
        settle()
        precondition(code.string == source)
        code.undoManager?.undo()
        precondition(code.string == firstSource, "Settings changed the source Undo sequence")
        print("PASS: live editor settings retain both native editors, code/focus/selection/dirty/Undo, Python actions and folds; font-aware gutter stays readable")
    }
}
