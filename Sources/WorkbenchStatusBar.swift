import SwiftUI
import Foundation

/// A compact project status surface stays visible when side panes are hidden.
struct WorkbenchStatusBar: View {
    @ObservedObject var kernel: KernelController
    let pendingCount: Int
    let startedAt: Date?
    let isDirty: Bool
    let isFileBacked: Bool
    let onChoosePython: () -> Void
    let onRestart: () -> Void
    let onInterrupt: () -> Void
    let onEditorSettings: () -> Void
    @State private var showActivity = false

    private var healthy: Bool { kernel.state == "Ready" }
    private var activity: KernelExecutionActivity? {
        KernelExecutionActivity.representative(in: Array(kernel.executionActivities.values))
    }
    private var phase: KernelExecutionPhase? {
        if let activity { return activity.phase }
        if kernel.inputPrompt != nil { return .waitingForInput }
        if kernel.state == "Busy" { return .running }
        return pendingCount > 0 ? .queued : nil
    }
    private var executionCount: Int { max(pendingCount, kernel.executionActivities.count) }
    private var canInterrupt: Bool { phase == .running || phase == .waitingForInput }
    private var hasFailure: Bool { !["Ready", "Busy", "Starting", "Disconnected"].contains(kernel.state) }
    private var stateColor: Color { hasFailure ? .red : phase != nil || kernel.state == "Starting" ? .orange : healthy ? .green : .secondary }
    private var environmentName: String {
        let url = URL(fileURLWithPath: kernel.interpreter)
        let parent = url.deletingLastPathComponent()
        return parent.lastPathComponent == "bin" ? parent.deletingLastPathComponent().lastPathComponent + " · " + url.lastPathComponent : url.lastPathComponent
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12).frame(minHeight: 30)
        .background(.bar)
        .popover(isPresented: $showActivity) {
            KernelActivityView(activity: kernel.activity, history: kernel.activityHistory, unavailable: kernel.activityUnavailable)
                .padding(16)
        }
    }
    private func row(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 16) {
            Button(action: onChoosePython) {
                HStack(spacing: 5) {
                    if let phase {
                        ExecutionIndicator(phase: phase, startedAt: activity?.startedAt ?? (canInterrupt ? startedAt : nil))
                    } else {
                        Circle().fill(stateColor).frame(width: 6, height: 6)
                        Text(hasFailure ? "Kernel needs attention" : kernel.state).lineLimit(1)
                    }
                    if !compact { Text(environmentName).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 190) }
                }
            }.buttonStyle(.plain).help(kernel.state + "\n" + kernel.interpreter + "\nChoose Python or check installed packages")
            if executionCount > 1 {
                Text("\(executionCount) executions").foregroundStyle(.secondary).fixedSize()
                    .help("Running and queued requests in this project")
            }
            if canInterrupt {
                Button(action: onInterrupt) { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.red)
                    .help("Interrupt running code in this project’s kernel")
                    .accessibilityLabel("Stop running code")
                    .accessibilityIdentifier("execution.stop")
            }
            if hasFailure || kernel.state == "Disconnected" {
                Button("Restart", action: onRestart).buttonStyle(.plain).foregroundStyle(.tint)
            }
            Spacer(minLength: 4)
            if !compact { Text(isDirty ? "Unsaved changes" : isFileBacked ? "Saved" : "New notebook").foregroundStyle(isDirty ? Color.orange : .secondary).fixedSize() }
            Button { showActivity = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                    if let activity = kernel.activity {
                        Text(activity.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "CPU —").monospacedDigit()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: activity.residentBytes), countStyle: .memory)).monospacedDigit()
                    } else { Text(compact ? "Activity" : "Kernel activity") }
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Python kernel CPU and resident memory. CPU uses 100% per core.")
                .accessibilityLabel("Show kernel CPU and memory activity")
            Button(action: onEditorSettings) {
                Label("Editor", systemImage: "slider.horizontal.3").labelStyle(.titleAndIcon)
            }.buttonStyle(.plain).help("Editor palette, font size, line numbers, and guides (⌘,)")
        }
    }
}
