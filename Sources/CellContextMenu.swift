import SwiftUI

/// Shared cell actions for both the tab strip and expanded cell headers.
struct CellContextMenu: View {
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    var deleteEnabled = true

    var body: some View {
        Button(action: onDuplicate) {
            Label("Duplicate Cell", systemImage: "doc.on.doc")
        }
        Button(role: .destructive, action: onDelete) {
            Label("Delete Cell", systemImage: "trash")
        }
        .disabled(!deleteEnabled)
        .help(deleteEnabled ? "Delete this cell" : "Wait for this cell to finish running before deleting it")
    }
}
