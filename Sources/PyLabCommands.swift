import SwiftUI

struct ProjectCommandTarget {
    let send: (ProjectToolbarAction) -> Void
    let showPalette: () -> Void
}

private struct ProjectCommandTargetKey: FocusedValueKey {
    typealias Value = ProjectCommandTarget
}

extension FocusedValues {
    var pylabProjectCommandTarget: ProjectCommandTarget? {
        get { self[ProjectCommandTargetKey.self] }
        set { self[ProjectCommandTargetKey.self] = newValue }
    }
}

/// Register shortcuts in the native menu bar, independently of lazy toolbar menus.
/// Focused scene values keep each command bound to the frontmost project window.
struct PyLabCommands: Commands {
    @FocusedValue(\.pylabProjectCommandTarget) private var target

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Editor Settings…") { target?.send(.editorSettings) }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(target == nil)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Notebook") { target?.send(.newNotebook) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(target == nil)
            Button("Open Notebook…") { target?.send(.open) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(target == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Notebook") { target?.send(.save) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(target == nil)
            Button("Save As…") { target?.send(.saveAs) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(target == nil)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find in Notebooks…") { target?.send(.findCells) }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(target == nil)
        }
        CommandMenu("Notebook") {
            Button("Command Palette…") { target?.showPalette() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(target == nil)
            Divider()
            Button("Run Selection or Cell") { target?.send(.runCode) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(target == nil)
            Button("Run Cell and Advance") { target?.send(.runAdvance) }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(target == nil)
        }
    }
}
