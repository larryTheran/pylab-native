import SwiftUI

/// Brief, settled motion for deliberate layout changes. Live editor typing and
/// divider tracking should stay outside these transactions.
enum LiquidMotion {
    static func transition(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85)
    }
    static func feedback(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.86)
    }
}

/// A small lift and rim highlight make the accepted drop destination visible.
/// The large code surface keeps its normal material and does not animate text.
private struct MagneticDropFeedback: ViewModifier {
    let isTargeted: Bool
    let cornerRadius: CGFloat
    let movesContent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.accentColor.opacity(isTargeted ? 0.85 : 0), lineWidth: 1.5)
                    .shadow(color: Color.accentColor.opacity(isTargeted ? 0.22 : 0), radius: isTargeted ? 7 : 0)
                    .scaleEffect(isTargeted && !reduceMotion && !movesContent ? 1.006 : 1)
                    .allowsHitTesting(false)
                    .animation(LiquidMotion.feedback(reduceMotion: reduceMotion), value: isTargeted)
            }
            .scaleEffect(isTargeted && !reduceMotion && movesContent ? 1.012 : 1)
            .offset(y: isTargeted && !reduceMotion && movesContent ? -2 : 0)
            .animation(LiquidMotion.feedback(reduceMotion: reduceMotion), value: isTargeted)
    }
}

extension View {
    func magneticDropFeedback(isTargeted: Bool, cornerRadius: CGFloat = 10, movesContent: Bool = true) -> some View {
        modifier(MagneticDropFeedback(isTargeted: isTargeted, cornerRadius: cornerRadius, movesContent: movesContent))
    }
}
