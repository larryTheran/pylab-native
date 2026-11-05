import AppKit
import Combine
import Foundation

@main struct EditorPreferenceChecks {
    static func main() {
        let suite = "org.pylab.tests.editor." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = EditorPreferences(defaults: defaults)
        precondition(settings.fontSize == 13 && settings.palette == .vscode && settings.showsIndentGuides && settings.showsLineNumbers)
        var changes = 0
        let subscription = settings.objectWillChange.sink { changes += 1 }
        settings.setFontSize(13); settings.setPalette(.vscode); settings.setShowsLineNumbers(true); settings.setShowsIndentGuides(true)
        precondition(changes == 0, "No-op settings published changes")
        settings.setFontSize(999); settings.setPalette(.nord); settings.setShowsLineNumbers(false); settings.setShowsIndentGuides(false)
        let restored = EditorPreferences(defaults: defaults)
        precondition(restored.fontSize == 22 && restored.palette == .nord && !restored.showsLineNumbers && !restored.showsIndentGuides)
        settings.setFontSize(-5); precondition(settings.fontSize == 11)
        settings.setFontSize(.nan); precondition(settings.fontSize == 13)
        settings.setFontSize(.infinity); precondition(settings.fontSize == 13)
        defaults.set("unknown", forKey: "editor.palette.v1")
        defaults.set([1,2], forKey: "editor.fontSize.v1")
        defaults.set("malformed", forKey: "editor.lineNumbers.v1")
        let fallback = EditorPreferences(defaults: defaults)
        precondition(fallback.palette == .vscode && fallback.fontSize == 13 && fallback.showsLineNumbers)
        settings.reset()
        let reset = EditorPreferences(defaults: defaults)
        precondition(reset.fontSize == 13 && reset.palette == .vscode && reset.showsIndentGuides && reset.showsLineNumbers)
        for palette in EditorPalette.allCases {
            for kind in [PythonSyntaxKind.keyword, .constant, .string, .comment, .number, .builtin, .function, .typeName, .decorator] {
                let dark = palette.color(kind, dark: true).usingColorSpace(.deviceRGB)!
                let light = palette.color(kind, dark: false).usingColorSpace(.deviceRGB)!
                precondition(dark.alphaComponent == 1 && light.alphaComponent == 1)
                precondition(dark != light, "Palette must adapt to both appearances")
            }
        }
        precondition(EditorPalette.vscode.colorHex(.keyword, dark: true) == 0xC586C0)
        _ = subscription
        print("PASS: editor defaults, bounded font settings, persistence/reset, no-op updates, invalid-value fallback and adaptive palettes")
    }
}
