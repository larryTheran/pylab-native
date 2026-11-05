import SwiftUI
import AppKit

/// Keeps SwiftUI's existing window delegate while asking before closing a window
/// that contains unsaved notebooks. The application quit guard is separate.
struct WindowCloseGuard: NSViewRepresentable {
    let projectIDs: Set<UUID>

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> GuardView {
        let view = GuardView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.projectIDs = projectIDs
        return view
    }
    func updateNSView(_ view: GuardView, context: Context) {
        context.coordinator.projectIDs = projectIDs
        context.coordinator.attach(to: view.window)
    }
    static func dismantleNSView(_ view: GuardView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class GuardView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var previous: NSWindowDelegate?
        var projectIDs = Set<UUID>()

        func attach(to newWindow: NSWindow?) {
            guard let newWindow else { detach(); return }
            if window === newWindow, newWindow.delegate === self { return }
            detach()
            window = newWindow
            previous = newWindow.delegate
            newWindow.delegate = self
        }
        func detach() {
            if let window, window.delegate === self { window.delegate = previous }
            window = nil
            previous = nil
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (previous?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if previous?.responds(to: selector) == true { return previous }
            return super.forwardingTarget(for: selector)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if !PyLabLifecycle.dirtyProjects.isDisjoint(with: projectIDs) {
                let alert = NSAlert()
                alert.messageText = "Close window with unsaved notebooks?"
                alert.informativeText = "Save your notebooks before closing if you want to keep their changes."
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Close Without Saving")
                guard alert.runModal() == .alertSecondButtonReturn else { return false }
            }
            return previous?.windowShouldClose?(sender) ?? true
        }
    }
}
