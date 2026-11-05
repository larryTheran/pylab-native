import AppKit
import Combine
import Foundation

enum EditorPalette: String, CaseIterable, Identifiable, Codable {
    case vscode, nord, solarized
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vscode: return "VS Code"
        case .nord: return "Nord"
        case .solarized: return "Solarized"
        }
    }
    func color(_ kind: PythonSyntaxKind, dark: Bool) -> NSColor {
        let hex = colorHex(kind, dark: dark)
        return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                       green: CGFloat((hex >> 8) & 255) / 255,
                       blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    func colorHex(_ kind: PythonSyntaxKind, dark: Bool) -> UInt32 {
        switch self {
        case .vscode:
            switch kind {
            case .keyword: return dark ? 0xC586C0 : 0xAF00DB
            case .constant: return dark ? 0x569CD6 : 0x0000FF
            case .string: return dark ? 0xCE9178 : 0xA31515
            case .comment: return dark ? 0x6A9955 : 0x008000
            case .number: return dark ? 0xB5CEA8 : 0x098658
            case .builtin, .typeName: return dark ? 0x4EC9B0 : 0x267F99
            case .function, .decorator: return dark ? 0xDCDCAA : 0x795E26
            }
        case .nord:
            switch kind {
            case .keyword: return dark ? 0x81A1C1 : 0x485E82
            case .constant, .number: return dark ? 0xB48EAD : 0x7E5278
            case .string: return dark ? 0xA3BE8C : 0x426B32
            case .comment: return dark ? 0x8290A7 : 0x617188
            case .builtin, .typeName: return dark ? 0x8FBCBB : 0x286E70
            case .function: return dark ? 0x88C0D0 : 0x24718A
            case .decorator: return dark ? 0xEBCB8B : 0x805A18
            }
        case .solarized:
            switch kind {
            case .keyword: return dark ? 0xB3B94C : 0x667C00
            case .constant, .number: return dark ? 0xD58AB1 : 0xA42B70
            case .string: return dark ? 0x56B7AE : 0x0C756E
            case .comment: return dark ? 0x839496 : 0x657B83
            case .builtin, .typeName: return dark ? 0xE0AC47 : 0x8C6400
            case .function: return dark ? 0x63ABE0 : 0x1769A0
            case .decorator: return dark ? 0xC68DDF : 0x7753A4
            }
        }
    }
}

struct EditorStyle: Equatable {
    var fontSize: Double
    var palette: EditorPalette
    var showsIndentGuides: Bool
    var showsLineNumbers: Bool
}

/// App-wide presentation preferences; changing them never edits notebook text.
final class EditorPreferences: ObservableObject {
    static let shared = EditorPreferences()
    static let defaultFontSize = 13.0
    static let fontSizeRange = 11.0...22.0
    private enum Key {
        static let font = "editor.fontSize.v1"
        static let palette = "editor.palette.v1"
        static let guides = "editor.indentGuides.v1"
        static let numbers = "editor.lineNumbers.v1"
    }
    @Published private(set) var fontSize: Double
    @Published private(set) var palette: EditorPalette
    @Published private(set) var showsIndentGuides: Bool
    @Published private(set) var showsLineNumbers: Bool
    private let defaults: UserDefaults
    var style: EditorStyle { EditorStyle(fontSize: fontSize, palette: palette, showsIndentGuides: showsIndentGuides, showsLineNumbers: showsLineNumbers) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontSize = Self.normalizedFontSize((defaults.object(forKey: Key.font) as? NSNumber)?.doubleValue ?? Self.defaultFontSize)
        palette = defaults.string(forKey: Key.palette).flatMap(EditorPalette.init(rawValue:)) ?? .vscode
        showsIndentGuides = (defaults.object(forKey: Key.guides) as? NSNumber)?.boolValue ?? true
        showsLineNumbers = (defaults.object(forKey: Key.numbers) as? NSNumber)?.boolValue ?? true
    }
    static func normalizedFontSize(_ value: Double) -> Double {
        value.isFinite ? min(fontSizeRange.upperBound, max(fontSizeRange.lowerBound, value)) : defaultFontSize
    }
    func setFontSize(_ value: Double) {
        let next = Self.normalizedFontSize(value)
        guard fontSize != next else { return }
        fontSize = next; defaults.set(next, forKey: Key.font)
    }
    func setPalette(_ value: EditorPalette) {
        guard palette != value else { return }
        palette = value; defaults.set(value.rawValue, forKey: Key.palette)
    }
    func setShowsIndentGuides(_ value: Bool) {
        guard showsIndentGuides != value else { return }
        showsIndentGuides = value; defaults.set(value, forKey: Key.guides)
    }
    func setShowsLineNumbers(_ value: Bool) {
        guard showsLineNumbers != value else { return }
        showsLineNumbers = value; defaults.set(value, forKey: Key.numbers)
    }
    func reset() {
        setFontSize(Self.defaultFontSize); setPalette(.vscode)
        setShowsIndentGuides(true); setShowsLineNumbers(true)
    }
}
