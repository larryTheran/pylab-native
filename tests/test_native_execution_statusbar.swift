import SwiftUI
import AppKit

@main struct NativeExecutionStatusChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let suite = "org.pylab.tests.execution-status." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let kernel = KernelController(python: "/opt/miniconda3/bin/python3.12", preferences: defaults)
        var interruptions = 0
        func bar(count: Int) -> some View {
            WorkbenchStatusBar(kernel: kernel, pendingCount: count, startedAt: Date(timeIntervalSinceNow: -65), isDirty: true, isFileBacked: true,
                onChoosePython: {}, onRestart: {}, onInterrupt: { interruptions += 1 }, onEditorSettings: {})
        }
        let host = NSHostingView(rootView: AnyView(bar(count: 1)))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 820, height: 40)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); host.layoutSubtreeIfNeeded() }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        for (label, state, prompt, count) in [("queued", "Ready", Optional<String>.none, 3), ("running", "Busy", nil, 3), ("waiting", "Busy", "Value: ", 1), ("ready", "Ready", nil, 0)] {
            kernel.state = state; kernel.inputPrompt = prompt
            host.rootView = AnyView(bar(count: count))
            for width in [820.0, 1450.0] {
                window.setContentSize(NSSize(width: width, height: 40)); settle()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("Snapshot unavailable") }
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/pylab-status-\(label)-\(Int(width)).png"))
                let buttons = views(host).compactMap { $0 as? NSButton }
                // In this CLI-hosted SwiftUI view the borderless Stop uses an
                // NSButton; the other plain actions are rendered by SwiftUI.
                // Pressing it also verifies the project interrupt callback.
                let stops = buttons
                if label == "running" || label == "waiting" {
                    precondition(stops.count == 1, "Active code must have one Stop control")
                    let original = interruptions
                    stops[0].performClick(nil)
                    precondition(interruptions == original + 1, "Stop did not invoke its interrupt action")
                } else { precondition(stops.isEmpty, "Idle/queued jobs should not expose Stop") }
                let spinners = views(host).compactMap { $0 as? NSProgressIndicator }
                precondition(spinners.count == (label == "running" ? 1 : 0), "Only running code should spin")
            }
        }
        precondition(interruptions == 4)
        print("PASS: global phase/elapsed status at 820/1450 points and active Stop callbacks")
    }
}
