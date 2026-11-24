import Foundation
import AppKit
import Combine
import SwiftUI

/// One current decoded frame. Observers share it; frames are replaced, not retained.
final class LiveFigure: ObservableObject {
    struct Frame {
        let data: Data
        let image: NSImage
    }
    let displayID: String
    @Published private(set) var frame: Frame
    @Published private(set) var isLive = true
    var data: Data { frame.data }
    var image: NSImage { frame.image }

    init?(displayID: String, data: Data) {
        guard !displayID.isEmpty, let image = NSImage(data: data) else { return nil }
        self.displayID = displayID
        self.frame = Frame(data: data, image: image)
    }
    @discardableResult func update(data: Data) -> Bool {
        if data == frame.data { if !isLive { isLive = true }; return true }
        guard let image = NSImage(data: data) else { markSnapshot(); return false }
        frame = Frame(data: data, image: image)
        if !isLive { isLive = true }
        return true
    }
    func markSnapshot() { if isLive { isLive = false } }
}

struct NotebookDisplayTarget: Equatable {
    let cellID: String
    let outputIndex: Int
}

extension NotebookStore {
    /// Register a display's output slot. One ID can intentionally appear in more
    /// than one cell, as allowed by Jupyter's display/update protocol.
    @discardableResult func appendDisplayOutput(_ cellID: String, output: [String: Any], displayID: String?, liveFigure: LiveFigure? = nil) -> LiveFigure? {
        guard let index = cells.firstIndex(where: { $0.id == cellID }) else { return nil }
        var frame: LiveFigure?
        if let displayID, !displayID.isEmpty {
            let target = NotebookDisplayTarget(cellID: cellID, outputIndex: cells[index].outputs.count)
            displayOutputTargets[displayID, default: []].append(target)
            if let data = Self.figureData(in: output) {
                frame = liveFigure ?? displayFigures[displayID] ?? LiveFigure(displayID: displayID, data: data)
                if let frame { _ = frame.update(data: data); displayFigures[displayID] = frame }
            }
        }
        cells[index].outputs.append(output)
        isDirty = true
        return frame
    }

    /// Fan out a kernel update once. A text placeholder can become an image in
    /// several notebooks at once, all of which must observe the same frame.
    @discardableResult static func updateDisplayOutputs(
        displayID: String, output: [String: Any], stores: [NotebookStore],
        galleryFigure: LiveFigure? = nil, consolePlaceholder: Bool = false,
        onFirstImage: (String, LiveFigure) -> Void = { _, _ in }
    ) -> Int {
        var updated = 0
        var recipients: [NotebookStore] = []
        for store in stores {
            let count = store.replaceDisplaySlots(displayID: displayID, output: output)
            if count > 0 { recipients.append(store); updated += count }
        }
        guard !recipients.isEmpty || galleryFigure != nil || consolePlaceholder else { return 0 }
        let existing = galleryFigure ?? recipients.lazy.compactMap { $0.displayFigures[displayID] }.first
        guard let data = figureData(in: output) else {
            existing?.markSnapshot()
            return updated
        }
        let frame: LiveFigure
        if let existing {
            guard existing.update(data: data) else { return updated }
            frame = existing
        } else {
            guard let first = LiveFigure(displayID: displayID, data: data) else { return updated }
            frame = first
        }
        for store in recipients { store.displayFigures[displayID] = frame }
        if existing == nil {
            let source = recipients.first.flatMap { store in
                let cellID = store.displayOutputTargets[displayID]?.first?.cellID
                return store.cells.first(where: { $0.id == cellID })?.name
            }
            onFirstImage(source ?? "Console", frame)
        }
        return updated
    }

    @discardableResult func updateDisplayOutput(displayID: String, output: [String: Any]) -> Int {
        Self.updateDisplayOutputs(displayID: displayID, output: output, stores: [self])
    }

    /// Replace the MIME bundle while retaining output type and execution count.
    private func replaceDisplaySlots(displayID: String, output: [String: Any]) -> Int {
        guard let targets = displayOutputTargets[displayID] else { return 0 }
        var updated = 0
        var valid: [NotebookDisplayTarget] = []
        for target in targets {
            guard let index = cells.firstIndex(where: { $0.id == target.cellID }),
                  cells[index].outputs.indices.contains(target.outputIndex) else { continue }
            var existing = cells[index].outputs[target.outputIndex]
            existing["data"] = output["data"] as? [String: Any] ?? [:]
            existing["metadata"] = output["metadata"] as? [String: Any] ?? [:]
            cells[index].outputs[target.outputIndex] = existing
            valid.append(target)
            updated += 1
        }
        displayOutputTargets[displayID] = valid.isEmpty ? nil : valid
        if updated > 0 { isDirty = true }
        else { displayFigures[displayID] = nil }
        return updated
    }

    func liveFigures(for cellID: String) -> [Int: LiveFigure] {
        guard let cell = cells.first(where: { $0.id == cellID }) else { return [:] }
        var result: [Int: LiveFigure] = [:]
        for (displayID, targets) in displayOutputTargets {
            guard let frame = displayFigures[displayID], frame.isLive else { continue }
            for target in targets where target.cellID == cellID && cell.outputs.indices.contains(target.outputIndex) {
                // A later text/HTML-only update must remove the old PNG preview.
                let bundle = cell.outputs[target.outputIndex]["data"] as? [String: Any] ?? [:]
                if !Self.text(bundle["image/png"]).isEmpty { result[target.outputIndex] = frame }
            }
        }
        return result
    }
    func removeLiveDisplays(for cellID: String) {
        for displayID in Array(displayOutputTargets.keys) {
            let retained = displayOutputTargets[displayID, default: []].filter { $0.cellID != cellID }
            displayOutputTargets[displayID] = retained.isEmpty ? nil : retained
            if retained.isEmpty { displayFigures[displayID] = nil }
        }
    }
    func resetLiveDisplays() {
        if !displayOutputTargets.isEmpty || !displayFigures.isEmpty { objectWillChange.send() }
        displayOutputTargets.removeAll()
        displayFigures.removeAll()
    }
    private static func figureData(in output: [String: Any]) -> Data? {
        let bundle = output["data"] as? [String: Any] ?? [:]
        let encoded = text(bundle["image/png"])
        guard !encoded.isEmpty else { return nil }
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
    }
}

/// A linked figure can refresh while its sheet is open. A detached/unsupported
/// display retains its last valid image with an explicit snapshot label.
struct LiveFigureBadge: View {
    @ObservedObject var figure: LiveFigure
    var body: some View {
        Label(figure.isLive ? "Live" : "Snapshot", systemImage: figure.isLive ? "dot.radiowaves.left.and.right" : "photo")
            .font(.caption).foregroundStyle(figure.isLive ? Color.green : Color.secondary)
            .help(figure.isLive ? "This figure receives plot updates from Python" : "Last valid image; this display is no longer showing live image data")
    }
}
