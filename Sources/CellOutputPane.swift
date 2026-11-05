import SwiftUI
import AppKit
import Combine

/// A bounded viewport for notebook outputs, including replaceable live figures. Collapsing or resizing this
/// view changes presentation only; the notebook's complete output JSON is retained.
struct CellOutputPane: View {
    let outputs: [[String: Any]]
    let markdown: String?
    let cellName: String
    let contentHeight: CGFloat
    @Binding var collapsed: Bool
    var liveFigures: [Int: LiveFigure] = [:]
    let onGoToLine: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: VariablePlot?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: markdown == nil ? "terminal" : "text.alignleft").foregroundStyle(.secondary)
                Text(markdown == nil ? "Output" : "Preview").font(.caption.weight(.semibold))
                if markdown == nil { Text("\(outputs.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                Button {
                    withAnimation(LiquidMotion.transition(reduceMotion: reduceMotion)) { collapsed.toggle() }
                } label: {
                    Label(collapsed ? "Show" : "Hide", systemImage: collapsed ? "chevron.down" : "chevron.up")
                        .font(.caption)
                }.buttonStyle(.plain)
                    .accessibilityLabel(collapsed ? "Show outputs" : "Hide outputs")
                    .help(collapsed ? "Show saved cell outputs" : "Collapse outputs to give the code more space")
            }
            .padding(.horizontal, 10)
            .frame(height: NotebookLayout.outputHeaderHeight)
            if !collapsed {
                Divider()
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if let markdown {
                            Text(.init(markdown)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        } else {
                            ForEach(Array(outputs.enumerated()), id: \.offset) { index, output in
                                CellOutputItemView(output: output, previewHeight: max(48, contentHeight - 50), liveFigure: liveFigures[index],
                                    onGoToLine: onGoToLine,
                                    onOpenFigure: { data in snapshot = VariablePlot(name: cellName + " · Output \(index + 1)", data: data, liveFigure: liveFigures[index]) })
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .frame(height: max(0, contentHeight))
                .accessibilityLabel("Cell output content")
            }
        }
        .frame(maxWidth: .infinity)
        .background(.background.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 0.6))
        .sheet(item: $snapshot) { plot in VariablePlotView(plot: plot) }
    }
}

private struct CellOutputItemView: View {
    let output: [String: Any]
    let previewHeight: CGFloat
    let liveFigure: LiveFigure?
    let onGoToLine: (Int) -> Void
    let onOpenFigure: (Data) -> Void
    private struct DecodedFigure { let data: Data; let image: NSImage }
    @State private var figure: DecodedFigure?
    @State private var figureLoadFailed = false

    private func errorLine(_ text: String) -> Int? {
        let clean = text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        let patterns = ["(?i)Cell\\s+In\\[\\d+\\],\\s*line\\s+(\\d+)", "(?i)<pylab-[^>]+>\\s*\\(\\s*(\\d+)\\s*\\)"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: clean, range: NSRange(location: 0, length: (clean as NSString).length)),
               let result = Range(match.range(at: 1), in: clean), let line = Int(clean[result]), line > 0 { return line }
        }
        return nil
    }
    var body: some View {
        let kind = output["output_type"] as? String ?? ""
        let data = output["data"] as? [String: Any] ?? [:]
        let image = NotebookStore.text(data["image/png"])
        let outputText: String = {
            if kind == "stream" {
                let text = NotebookStore.text(output["text"])
                return output["name"] as? String == "stderr"
                    ? text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression) : text
            }
            if kind == "error" {
                let trace = (output["traceback"] as? [String] ?? []).joined(separator: "\n")
                return trace.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
            }
            return NotebookStore.text(data["text/plain"])
        }()
        VStack(alignment: .leading, spacing: 6) {
            if let figure {
                HStack {
                    if let liveFigure { LiveFigureBadge(figure: liveFigure) }
                    else { Label("Figure", systemImage: "chart.xyaxis.line").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    Button("Open Figure") { onOpenFigure(figure.data) }.controlSize(.small)
                        .help("Open the complete figure with zoom and PNG export")
                }
                Image(nsImage: figure.image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity).frame(height: previewHeight)
                    .contentShape(Rectangle()).onTapGesture(count: 2) { onOpenFigure(figure.data) }
                    .accessibilityLabel("Figure preview; use Open Figure for full size")
            } else if !image.isEmpty && !figureLoadFailed {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).frame(height: previewHeight)
            } else if !outputText.isEmpty {
                Text(outputText).font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(kind == "error" || output["name"] as? String == "stderr" ? Color.red : Color.primary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if (kind == "error" || output["name"] as? String == "stderr"), let line = errorLine(outputText) {
                    Button("Go to line \(line)") { onGoToLine(line) }.buttonStyle(.link)
                }
            } else {
                Text("Rich output preserved in notebook").foregroundStyle(.secondary).font(.caption)
            }
        }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        .task(id: image) {
            // Keep the decoded snapshot while the output divider moves. Resizing
            // must not repeatedly decode a large PNG on the main thread.
            if let liveFigure, !image.isEmpty {
                figure = DecodedFigure(data: liveFigure.data, image: liveFigure.image)
                figureLoadFailed = false
            } else if let raw = Data(base64Encoded: image, options: .ignoreUnknownCharacters), let decoded = NSImage(data: raw), !image.isEmpty {
                figure = DecodedFigure(data: raw, image: decoded)
                figureLoadFailed = false
            } else { figure = nil; figureLoadFailed = !image.isEmpty }
        }
        .onReceive(frameUpdates) { frame in
            figure = DecodedFigure(data: frame.data, image: frame.image)
            figureLoadFailed = false
        }
    }
    private var frameUpdates: AnyPublisher<LiveFigure.Frame, Never> {
        liveFigure?.$frame.eraseToAnyPublisher() ?? Empty<LiveFigure.Frame, Never>(completeImmediately: false).eraseToAnyPublisher()
    }
}
