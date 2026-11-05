import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct VariablePlot: Identifiable {
    let id = UUID()
    let name: String
    var data: Data
    var sourceName: String? = nil
    var column: Int? = nil
    var scopeID: String? = nil
    var settings: [String: Any] = [:]
    var liveFigure: LiveFigure? = nil
}

struct VariablePlotView: View {
    let plot: VariablePlot
    var regenerate: (([String: Any], @escaping (Data?, String?) -> Void) -> Void)? = nil
    @State private var plotData: Data
    @State private var plotImage: NSImage?
    @State private var fixedSize: CGSize
    @State private var title: String
    @State private var xLabel = "Index"
    @State private var yLabel = ""
    @State private var xMin = ""
    @State private var xMax = ""
    @State private var yMin = ""
    @State private var yMax = ""
    @State private var cursorIndex = ""
    @State private var legendMode = "automatic"
    @State private var showSettings = false
    @State private var working = false
    @State private var appliedSettings: [String: Any]
    init(plot: VariablePlot, regenerate: (([String: Any], @escaping (Data?, String?) -> Void) -> Void)? = nil) {
        self.plot = plot; self.regenerate = regenerate
        _plotData = State(initialValue: plot.liveFigure?.data ?? plot.data)
        _plotImage = State(initialValue: plot.liveFigure?.image ?? NSImage(data: plot.data))
        _fixedSize = State(initialValue: Self.preferredSize(for: plot.data))
        _title = State(initialValue: plot.settings["title"] as? String ?? plot.name)
        _xLabel = State(initialValue: plot.settings["xlabel"] as? String ?? "Index")
        _yLabel = State(initialValue: plot.settings["ylabel"] as? String ?? "")
        _xMin = State(initialValue: plot.settings["xmin"] as? String ?? "")
        _xMax = State(initialValue: plot.settings["xmax"] as? String ?? "")
        _yMin = State(initialValue: plot.settings["ymin"] as? String ?? "")
        _yMax = State(initialValue: plot.settings["ymax"] as? String ?? "")
        _cursorIndex = State(initialValue: plot.settings["cursor"] as? String ?? "")
        let existingLegend = plot.settings["legend"] as? Bool
        _legendMode = State(initialValue: existingLegend.map { $0 ? "show" : "hide" } ?? "automatic")
        _appliedSettings = State(initialValue: plot.settings)
    }
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var zoom: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            figureToolbar
            Divider()
            if showSettings && regenerate != nil {
                VStack(spacing: 8) {
                    HStack {
                        TextField("Title", text: $title).frame(minWidth: 90)
                        TextField("X axis", text: $xLabel).frame(minWidth: 70)
                        TextField("Y axis", text: $yLabel).frame(minWidth: 70)
                        Picker("Legend", selection: $legendMode) {
                            Text("Automatic").tag("automatic")
                            Text("Show").tag("show")
                            Text("Hide").tag("hide")
                        }.frame(width: 125).help("Legend visibility")
                        Button("Apply") { refresh() }.disabled(working)
                    }
                    HStack {
                        Text("Limits").font(.caption).foregroundStyle(.secondary)
                        TextField("X min", text: $xMin); TextField("X max", text: $xMax)
                        TextField("Y min", text: $yMin); TextField("Y max", text: $yMax)
                        TextField("Data index", text: $cursorIndex).help("Show exact values at this zero-based index")
                    }
                }.padding(12).disabled(working)
                Divider()
            }
            if let image = plotImage {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: max(1, geometry.size.width - 32) * zoom,
                                   height: max(1, geometry.size.height - 32) * zoom)
                            .padding(16)
                    }
                }
            } else {
                ContentUnavailableView("Unable to display plot", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(width: fixedSize.width, height: fixedSize.height)
        .onReceive(frameUpdates) { frame in
            plotData = frame.data
            plotImage = frame.image
        }
        .onChange(of: plot.data) { _, data in
            if plot.liveFigure == nil { plotData = data; plotImage = NSImage(data: data) }
        }

        .alert("Could not save plot", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var frameUpdates: AnyPublisher<LiveFigure.Frame, Never> {
        plot.liveFigure?.$frame.eraseToAnyPublisher() ?? Empty<LiveFigure.Frame, Never>(completeImmediately: false).eraseToAnyPublisher()
    }

    private var figureToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                figureTitle.frame(minWidth: 100, alignment: .leading)
                if let live = plot.liveFigure { LiveFigureBadge(figure: live) }
                Spacer(minLength: 8)
                figureZoomControls
                if regenerate != nil { figureEditButton }
                figureExportMenu
                figureDoneButton
            }
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    figureTitle
                    if let live = plot.liveFigure { LiveFigureBadge(figure: live) }
                    Spacer(minLength: 8)
                    figureDoneButton
                }
                HStack(spacing: 6) {
                    figureZoomControls
                    Spacer(minLength: 0)
                    if regenerate != nil { figureEditButton }
                    figureExportMenu
                }.controlSize(.small)
            }
        }.padding(16)
    }

    private var figureTitle: some View {
        Label("Plot: \(plot.name)", systemImage: "chart.xyaxis.line")
            .font(.headline).lineLimit(1).truncationMode(.tail)
            .help(plot.name)
    }

    private var figureZoomControls: some View {
        HStack(spacing: 6) {
            Button { zoom = max(1, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out").accessibilityLabel("Zoom out")
            Text("\(Int(zoom * 100))%").font(.caption.monospacedDigit()).frame(width: 44)
                .accessibilityLabel("Zoom \(Int(zoom * 100)) percent")
            Button { zoom = min(4, zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in").accessibilityLabel("Zoom in")
            Button("Fit") { zoom = 1 }.help("Fit the entire figure")
        }.fixedSize()
    }

    private var figureEditButton: some View {
        Button("Edit") { showSettings.toggle() }.help("Edit figure labels and legend").fixedSize()
    }

    private var figureExportMenu: some View {
        Menu("Export") {
            Button("Save PNG…", action: savePNG)
            if regenerate != nil {
                Text("Vector exports use current workspace data")
                Button("Save Vector PDF…") { saveVector(format: "pdf") }
                Button("Save SVG…") { saveVector(format: "svg") }
            } else { Button("Save PDF (image)…", action: savePDF) }
        }.buttonStyle(.glass).disabled(working).fixedSize()
            .help(regenerate == nil ? "Save this figure snapshot as PNG or image PDF" : "Vector exports are regenerated from the current workspace data")
    }

    private var figureDoneButton: some View {
        Button("Done") { dismiss() }.buttonStyle(.glassProminent).fixedSize()
            .keyboardShortcut(.cancelAction)
    }

    /// Size the sheet to the figure, bounded by the available window and screen.
    /// The image itself always scales to fit the remaining space without cropping.
    private static func preferredSize(for data: Data) -> CGSize {
        let imageSize = NSImage(data: data)?.size ?? CGSize(width: 800, height: 480)
        let ratio = max(0.1, imageSize.width / max(1, imageSize.height))
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let keyWindow = NSApp.keyWindow
        let window = (keyWindow?.sheetParent ?? keyWindow)?.contentLayoutRect.size ?? screen
        let maxWidth = max(320, min(1000, screen.width - 80, window.width - 32))
        let maxHeight = max(260, min(750, screen.height - 80, window.height - 80))
        let imageWidth = min(max(480, imageSize.width), maxWidth - 32, max(1, maxHeight - 100) * ratio)
        let imageHeight = imageWidth / ratio
        return CGSize(width: min(maxWidth, max(320, imageWidth + 32)),
                      height: min(maxHeight, max(260, imageHeight + 100)))
    }

    private func options(format: String = "png") -> [String: Any] {
        var result: [String: Any] = ["title": title, "xlabel": xLabel, "ylabel": yLabel, "format": format,
         "xmin": xMin, "xmax": xMax, "ymin": yMin, "ymax": yMax, "cursor": cursorIndex]
        if legendMode != "automatic" { result["legend"] = legendMode == "show" }
        return result
    }
    private func refresh() {
        working = true
        let submitted = options()
        regenerate?(submitted) { data, error in
            working = false
            if let data { plotData = data; plotImage = NSImage(data: data); appliedSettings = submitted }
            else { errorMessage = error ?? "Unable to update the figure." }
        }
    }
    private func saveVector(format: String) {
        guard let regenerate else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = plot.name + "." + format
        if let type = UTType(filenameExtension: format) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = true
        var exportOptions = appliedSettings
        exportOptions["format"] = format
        regenerate(exportOptions) { data, error in
            working = false
            guard let data else { errorMessage = error ?? "Unable to create the figure."; return }
            do { try data.write(to: url, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func savePDF() {
        guard let image = NSImage(data: plotData) else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = plot.name + ".pdf"; panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = image.size
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = image; view.imageScaling = .scaleProportionallyUpOrDown
        do { try view.dataWithPDF(inside: view.bounds).write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }
    private func savePNG() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = plot.name + ".png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try plotData.write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }
}


/// Keeps generated workspace plots available while a project remains open.
struct FigureGallery: View {
    @Binding var figures: [VariablePlot]
    let render: (VariablePlot, [String: Any], @escaping (Data?, String?) -> Void) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Figures").font(.headline).padding(.leading, 14)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(figures) { figure in
                            HStack(spacing: 5) {
                                Button(figure.name) { selectedID = figure.id }.buttonStyle(.plain).lineLimit(1)
                                Button { close(figure.id) } label: { Image(systemName: "xmark").font(.caption2) }
                                    .buttonStyle(.plain).help("Close figure")
                            }.padding(.horizontal, 9).padding(.vertical, 6)
                                .background(selectedID == figure.id ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.scrollIndicators(.automatic, axes: .horizontal)
                if figures.isEmpty { Button("Done") { dismiss() }.buttonStyle(.glassProminent).padding(.trailing, 12) }
            }.padding(.vertical, 7).background(.bar)
            Divider()
            if let figure = figures.first(where: { $0.id == selectedID }) {
                if figure.sourceName != nil {
                    VariablePlotView(plot: figure, regenerate: { options, completion in
                    render(figure, options) { data, error in
                        if options["format"] as? String == "png", let data,
                           let index = figures.firstIndex(where: { $0.id == figure.id }) {
                            figures[index].data = data; figures[index].settings = options
                        }
                        completion(data, error)
                    }
                    }).id(figure.id)
                } else {
                    VariablePlotView(plot: figure).id(figure.id)
                }
            } else {
                ContentUnavailableView("No figures yet", systemImage: "chart.xyaxis.line", description: Text("Run plotting code in a cell or console, or right-click a workspace variable and choose Plot."))
                    .frame(width: 620, height: 420)
            }
        }.onAppear { selectedID = figures.last?.id }
            .onChange(of: figures.last?.id) { _, id in
                if let id, !figures.contains(where: { $0.id == selectedID }) { selectedID = id }
            }
    }
    private func close(_ id: UUID) {
        guard let index = figures.firstIndex(where: { $0.id == id }) else { return }
        figures.remove(at: index)
        if selectedID == id { selectedID = figures.last?.id }
    }
}
