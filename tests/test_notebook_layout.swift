import Foundation
@main struct NotebookLayoutTest {
    static func main() {
        let wide = NotebookLayout(viewport: CGSize(width: 1400, height: 900), singleCell: true)
        let narrow = NotebookLayout(viewport: CGSize(width: 420, height: 360), singleCell: true)
        precondition(wide.outerPadding == 20 && narrow.outerPadding == 12)
        precondition(wide.cardWidth == 1360 && narrow.cardWidth == 396)
        let noOutput = wide.sizing(lineCount: 2, headerHeight: 30, hasOutputs: false)
        precondition(noOutput.editorHeight > 700 && noOutput.outputPaneHeight == 0)
        precondition(abs(noOutput.editorHeight + 30 + 10 + wide.cardPadding * 2 - wide.minimumCardHeight) < 0.001)
        let split = wide.sizing(lineCount: 2, headerHeight: 30, hasOutputs: true)
        precondition(split.editorHeight >= 160 && split.editorHeight / split.resizeExtent >= 0.67)
        precondition(split.outputPaneHeight / split.resizeExtent <= 0.33)
        precondition(abs(split.editorHeight + split.outputPaneHeight + 15 - noOutput.editorHeight) < 0.001)
        let collapsed = wide.sizing(lineCount: 2, headerHeight: 30, hasOutputs: true, outputsCollapsed: true)
        precondition(collapsed.outputPaneHeight == 32 && collapsed.outputContentHeight == 0)
        precondition(collapsed.editorHeight > split.editorHeight + 150)
        for fraction in [CGFloat(-100), 0.14, 0.32, 0.58, 100, .nan, .infinity] {
            let value = wide.sizing(lineCount: 1, headerHeight: 30, hasOutputs: true, outputFraction: fraction)
            precondition(value.editorHeight >= 160 && value.editorHeight.isFinite && value.outputPaneHeight.isFinite)
            precondition(value.outputPaneHeight <= value.resizeExtent - 160)
        }
        precondition(NotebookLayout.clampedOutputFraction(-100) == 0.14)
        precondition(NotebookLayout.clampedOutputFraction(100) == 0.58)
        let small = narrow.sizing(lineCount: 1000, headerHeight: 56, hasOutputs: true)
        precondition(small.editorHeight > 130 && small.outputPaneHeight > 48)
        precondition(small.editorHeight > small.outputPaneHeight)
        let all = NotebookLayout(viewport: CGSize(width: 700, height: 700), singleCell: false)
        precondition(all.sizing(lineCount: 2, headerHeight: 30, hasOutputs: true).editorHeight == 100)
        precondition(all.sizing(lineCount: 1000, headerHeight: 30, hasOutputs: true).outputPaneHeight <= 300)
        precondition(all.sizing(lineCount: 1, headerHeight: 30, hasOutputs: true, outputFraction: 100).outputPaneHeight == 300)
        let tiny = NotebookLayout(viewport: CGSize(width: 0, height: 0), singleCell: true)
        let tinySplit = tiny.sizing(lineCount: 0, headerHeight: 0, hasOutputs: true)
        precondition(tinySplit.editorHeight.isFinite && tinySplit.outputPaneHeight.isFinite)
        print("PASS: code-first default split, bounded outputs, fraction clamps, collapse recovery, compact windows and All Cells output cap")
    }
}
