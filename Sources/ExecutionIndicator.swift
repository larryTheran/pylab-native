import SwiftUI

/// Indeterminate execution feedback; elapsed time never implies a percentage.
struct ExecutionIndicator: View {
    let phase: KernelExecutionPhase
    var startedAt: Date? = nil
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func label(for phase: KernelExecutionPhase) -> String {
        switch phase {
        case .queued: return "Queued"
        case .running: return "Running"
        case .waitingForInput: return "Waiting for input"
        }
    }
    static func elapsedText(_ interval: TimeInterval) -> String {
        let finite = interval.isFinite ? min(max(0, interval), Double(Int.max / 2)) : 0
        let seconds = Int(finite)
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }
    private var tint: Color { phase == .queued ? .secondary : .orange }
    var body: some View {
        if phase != .queued, !compact, let startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(elapsed: Self.elapsedText(context.date.timeIntervalSince(startedAt)))
            }
        } else { content(elapsed: nil) }
    }
    private func content(elapsed: String?) -> some View {
        HStack(spacing: 5) {
            indicator.frame(width: 14, height: 14)
            if !compact {
                Text(Self.label(for: phase)).fontWeight(.medium)
                if let elapsed { Text(elapsed).monospacedDigit() }
            }
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 0 : 7)
        .padding(.vertical, compact ? 0 : 3)
        .background(tint.opacity(compact ? 0 : 0.10), in: Capsule())
        .fixedSize()
        .help(Self.label(for: phase))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(for: phase))
        .accessibilityValue(elapsed.map { "Elapsed " + $0 } ?? "")
    }
    @ViewBuilder private var indicator: some View {
        switch phase {
        case .queued: Image(systemName: "clock").font(.system(size: 11, weight: .semibold))
        case .waitingForInput: Image(systemName: "keyboard").font(.system(size: 11, weight: .semibold))
        case .running:
            if reduceMotion {
                Image(systemName: "hourglass").font(.system(size: 11, weight: .semibold))
            } else {
                ProgressView().controlSize(.mini).tint(.orange)
                    .accessibilityLabel("Code is running")
            }
        }
    }
}
