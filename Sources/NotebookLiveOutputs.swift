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

    /// Unknown update IDs do not create an output. Existing display instances
    /// replace their MIME bundle, retaining slot identity and execution count.
    @discardableResult func updateDisplayOutput(displayID: String, output: [String: Any]) -> Int {
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
        if updated > 0 {
            if let data = Self.figureData(in: output) {
                if let frame = displayFigures[displayID] { _ = frame.update(data: data) }
                else { displayFigures[displayID] = LiveFigure(displayID: displayID, data: data) }
            } else { displayFigures[displayID]?.markSnapshot() }
            isDirty = true
        }
        return updated
    }

    func liveFigures(for cellID: String) -> [Int: LiveFigure] {
        guard let cell = cells.first(where: { $0.id == cellID }) else { return [:] }
        var result: [Int: LiveFigure] = [:]
        for (displayID, targets) in displayOutputTargets {
            guard let frame = displayFigures[displayID] else { continue }
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
