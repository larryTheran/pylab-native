import SwiftUI

/// Compact glass appearance control, with a raised crescent cap that changes
/// sides while the binding remains the sole source of appearance state.
struct GlassAppearanceToggle: View {
    @Binding var isDark: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Namespace private var glassNamespace

    var body: some View {
        Button(action: toggle) {
            ZStack {
                GlassEffectContainer(spacing: 0) {
                    ZStack {
                        track
                            .frame(width: 108, height: 28)
                            .position(x: 63, y: 22)
                        cap
                            .frame(width: 44, height: 44)
                            .position(x: isDark ? 104 : 22, y: 22)
                    }
                    .frame(width: 126, height: 44)
                }
                // Keep foreground symbols above the shared glass pass so the
                // overlapping lenses never dim their labels or the active icon.
                Text(isDark ? "Dark" : "Light")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isDark ? Color.white.opacity(0.84) : Color.black.opacity(0.66))
                    .shadow(color: .black.opacity(0.13), radius: 0.6, y: 0.5)
                    .frame(width: 58)
                    .position(x: isDark ? 42 : 84, y: 22)
                Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: isDark ? 16 : 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(isDark ? 0.28 : 0.42), radius: 4)
                    .position(x: isDark ? 104 : 22, y: 22)
                    .allowsHitTesting(false)
            }
            .frame(width: 126, height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isDark ? "Switch to light appearance" : "Switch to dark appearance")
        .onKeyPress(keys: [.return], phases: .down) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            toggle()
            return .handled
        }
        .accessibilityRepresentation {
            Toggle("Dark Mode", isOn: $isDark)
                .accessibilityValue(isDark ? "On" : "Off")
        }
    }

    private var track: some View {
        Group {
            if reduceTransparency {
                Capsule().fill(isDark ? Color(white: 0.15) : Color(white: 0.54))
            } else {
                Capsule()
                    .fill(LinearGradient(colors: isDark
                        ? [Color.black.opacity(0.34), Color.black.opacity(0.60)]
                        : [Color.white.opacity(0.10), Color.black.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom))
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("appearance-track", in: glassNamespace)
            }
        }
        .overlay {
            Capsule().stroke(LinearGradient(colors: [Color.white.opacity(contrast == .increased ? 0.65 : 0.37), .clear, Color.black.opacity(0.19)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
        }
        .shadow(color: isDark ? .black.opacity(0.30) : .white.opacity(0.20), radius: 5, y: 3)
    }

    private var cap: some View {
        let shape = AppearanceGlassCap(openToRight: !isDark)
        return Group {
            if reduceTransparency {
                shape.fill(isDark ? Color(white: 0.24) : Color(white: 0.74))
            } else {
                Capsule()
                    .fill(LinearGradient(colors: isDark
                        ? [Color.white.opacity(0.12), Color.white.opacity(0.025)]
                        : [Color.white.opacity(0.26), Color.white.opacity(0.07)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    // Keep a convex native lens for stable glass rendering,
                    // then clip the C silhouette and draw its custom rim below.
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("appearance-cap", in: glassNamespace)
                    .mask(shape)
            }
        }
        .overlay {
            shape.stroke(LinearGradient(stops: [
                .init(color: .white.opacity(contrast == .increased ? 0.82 : (isDark ? 0.37 : 0.72)), location: 0),
                .init(color: .white.opacity(isDark ? 0.08 : 0.18), location: 0.48),
                .init(color: .white.opacity(isDark ? 0.26 : 0.49), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(isDark ? 0.25 : 0.16), radius: 6, y: 4)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.83)) {
            isDark.toggle()
        }
    }
}

/// A continuous C-shaped lens leaves the icon visible over the track beneath it.
private struct AppearanceGlassCap: Shape {
    let openToRight: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.79, y: 0.12))
        path.addCurve(to: CGPoint(x: 0.47, y: 0.00), control1: CGPoint(x: 0.71, y: 0.03), control2: CGPoint(x: 0.59, y: 0.00))
        path.addCurve(to: CGPoint(x: 0.02, y: 0.50), control1: CGPoint(x: 0.18, y: 0.00), control2: CGPoint(x: 0.02, y: 0.21))
        path.addCurve(to: CGPoint(x: 0.47, y: 1.00), control1: CGPoint(x: 0.02, y: 0.79), control2: CGPoint(x: 0.18, y: 1.00))
        path.addCurve(to: CGPoint(x: 0.79, y: 0.88), control1: CGPoint(x: 0.59, y: 1.00), control2: CGPoint(x: 0.71, y: 0.97))
        path.addCurve(to: CGPoint(x: 0.68, y: 0.77), control1: CGPoint(x: 0.83, y: 0.82), control2: CGPoint(x: 0.80, y: 0.77))
        path.addLine(to: CGPoint(x: 0.51, y: 0.77))
        path.addCurve(to: CGPoint(x: 0.24, y: 0.50), control1: CGPoint(x: 0.36, y: 0.77), control2: CGPoint(x: 0.24, y: 0.65))
        path.addCurve(to: CGPoint(x: 0.51, y: 0.23), control1: CGPoint(x: 0.24, y: 0.35), control2: CGPoint(x: 0.36, y: 0.23))
        path.addLine(to: CGPoint(x: 0.68, y: 0.23))
        path.addCurve(to: CGPoint(x: 0.79, y: 0.12), control1: CGPoint(x: 0.80, y: 0.23), control2: CGPoint(x: 0.83, y: 0.18))
        path.closeSubpath()
        return path.applying(CGAffineTransform(a: openToRight ? rect.width : -rect.width, b: 0, c: 0, d: rect.height,
            tx: openToRight ? rect.minX : rect.maxX, ty: rect.minY))
    }
}
