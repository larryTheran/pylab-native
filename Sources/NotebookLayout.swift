import Foundation

struct NotebookCellSizing {
    let editorHeight: CGFloat
    let outputPaneHeight: CGFloat
    let resizeExtent: CGFloat
    var outputContentHeight: CGFloat { max(0, outputPaneHeight - 33) }
}

/// Output geometry is bounded by the viewport, never the rendered image or log.
/// Code keeps the larger share; each output pane scrolls its full content itself.
struct NotebookLayout {
    let viewport: CGSize
    let singleCell: Bool
    static let defaultOutputFraction: CGFloat = 0.32
    static let outputHeaderHeight: CGFloat = 32

    var outerPadding: CGFloat {
        min(20, max(12, 12 + (max(0, viewport.width) - 500) / 65))
    }
    var cardWidth: CGFloat { max(0, viewport.width - outerPadding * 2) }
    var cardPadding: CGFloat { cardWidth < 600 ? 12 : 15 }
    var minimumCardHeight: CGFloat { singleCell ? max(0, viewport.height - outerPadding * 2) : 0 }

    static func clampedOutputFraction(_ fraction: CGFloat) -> CGFloat {
        guard fraction.isFinite else { return defaultOutputFraction }
        return min(0.58, max(0.14, fraction))
    }
    func sizing(lineCount: Int, headerHeight: CGFloat, hasOutputs: Bool,
                outputsCollapsed: Bool = false, outputFraction: CGFloat = defaultOutputFraction) -> NotebookCellSizing {
        let fraction = Self.clampedOutputFraction(outputFraction)
        if singleCell {
            let available = max(0, minimumCardHeight - cardPadding * 2 - headerHeight - 10)
            guard hasOutputs else {
                return NotebookCellSizing(editorHeight: max(100, available), outputPaneHeight: 0, resizeExtent: available)
            }
            if outputsCollapsed {
                return NotebookCellSizing(editorHeight: max(100, available - 10 - Self.outputHeaderHeight),
                                          outputPaneHeight: Self.outputHeaderHeight, resizeExtent: max(1, available - 15))
            }
            // Ten points separate code/output; the direct resize handle takes five.
            let split = max(0, available - 15)
            let minimumCode = max(72, min(160, split * 0.60))
            let minimumOutput = max(48, min(110, split * 0.25))
            let output = min(max(minimumOutput, split * fraction), max(minimumOutput, split - minimumCode))
            return NotebookCellSizing(editorHeight: max(minimumCode, split - output),
                                      outputPaneHeight: output, resizeExtent: max(1, split))
        }
        let naturalHeight = CGFloat(max(1, lineCount)) * 19 + 30
        let viewportLimit = max(140, min(720, viewport.height * 0.68))
        let editor = max(100, min(viewportLimit, naturalHeight))
        let output: CGFloat = !hasOutputs ? 0 : outputsCollapsed ? Self.outputHeaderHeight : min(300, max(80, viewport.height * fraction))
        return NotebookCellSizing(editorHeight: editor, outputPaneHeight: output, resizeExtent: max(1, viewport.height))
    }
}
