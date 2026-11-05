import SwiftUI
import AppKit

/// A quiet resize affordance: direct manipulation stays attached to the pointer.
struct PaneResizeHandle: View {
    let vertical: Bool
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.primary.opacity(0.045)
            Capsule().fill(Color.accentColor.opacity(hovering ? 0.55 : 0.0))
                .frame(width: vertical ? 2 : 36, height: vertical ? 36 : 2)
        }
        .frame(width: vertical ? 5 : nil, height: vertical ? nil : 5)
        .contentShape(Rectangle())
        .onHover { active in
            hovering = active
            (active ? (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown) : NSCursor.arrow).set()
        }
        .onDisappear { if hovering { NSCursor.arrow.set() } }
        .animation(LiquidMotion.feedback(reduceMotion: reduceMotion), value: hovering)
        .help(label).accessibilityLabel(label)
    }
}
