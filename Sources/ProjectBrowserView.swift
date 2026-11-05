import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// File navigation stays local. The parent opens notebooks and imports data;
/// rendering this browser never runs Python or modifies project files.
struct ProjectBrowserView: View {
    let folder: URL
    let items: [ProjectItem]
    let canGoBack: Bool
    let isNavigating: Bool
    let kernelState: String
    let interpreter: String
    var isOpeningFiles = false
    let onBack: () -> Void
    let onParent: () -> Void
    let onNavigateFolder: (URL) -> Void
    let onChooseFolder: () -> Void
    let onCreateFolder: () -> Void
    let onOpen: (ProjectItem) -> Void
    let onRename: (ProjectItem) -> Void
    let onDuplicate: (ProjectItem) -> Void
    let onDropFiles: ([URL]) -> Void
    let onRefresh: () -> Void
    @State private var query = ""
    @State private var dropTargeted = false
    @State private var loadingDrop = false
    @State private var localError: String?

    private var filtered: [ProjectItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? items : items.filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(term) }
    }
    private var navigationDisabled: Bool { isNavigating || loadingDrop || isOpeningFiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader
            navigation
            fileFilter
            fileList
            dropArea.padding(.horizontal, 10).padding(.top, 5).padding(.bottom, 7)
            footer
        }
        .background(.ultraThinMaterial)
        .onChange(of: folder) { _, _ in query = ""; localError = nil }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { acceptDrop($0) }
        .alert("Project Files", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button("OK", role: .cancel) { localError = nil }
        } message: { Text(localError ?? "") }
    }
    private var projectHeader: some View {
        HStack(spacing: 8) {
            Text("PROJECT").font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Spacer(minLength: 4)
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                .help("Refresh files").accessibilityLabel("Refresh files")
            Button(action: onCreateFolder) { Image(systemName: "folder.badge.plus") }
                .help("New folder").accessibilityLabel("New folder")
            Button(action: onChooseFolder) { Image(systemName: "folder.badge.gearshape") }
                .help("Choose project folder").accessibilityLabel("Choose project folder")
        }.buttonStyle(.plain).disabled(navigationDisabled)
            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 9)
    }
    private var navigation: some View {
        HStack(spacing: 8) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .disabled(!canGoBack || navigationDisabled)
                .help("Back to previous folder").accessibilityLabel("Back to previous folder")
            Button(action: onParent) { Image(systemName: "arrow.up") }
                .disabled((folder.path as NSString).standardizingPath == "/" || navigationDisabled)
                .help("Go to parent folder").accessibilityLabel("Go to parent folder")
            if isNavigating { ProgressView().controlSize(.small).accessibilityLabel("Changing Python folder") }
            folderMenu
            Spacer(minLength: 0)
        }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 9)
    }
    private var folderMenu: some View {
        Menu { folderChoices } label: {
            Text(folder.lastPathComponent.isEmpty ? "/" : folder.lastPathComponent)
                .font(.headline).lineLimit(1).truncationMode(.middle)
        }.menuStyle(.borderlessButton).disabled(navigationDisabled)
            .help(folder.path).accessibilityLabel("Current folder: " + folder.path)
    }
    @ViewBuilder private var folderChoices: some View {
        Button("Open Folder in Finder", systemImage: "folder") { reveal(folder, select: false) }
        Button("Copy Folder Path", systemImage: "doc.on.doc") { copyPath(folder) }
        if !ProjectBrowserFiles.ancestors(of: folder).isEmpty {
            Divider()
            Section("Go to Folder") {
                ForEach(ProjectBrowserFiles.ancestors(of: folder), id: \.path) { parent in
                    Button { onNavigateFolder(parent) } label: {
                        Label(parent.lastPathComponent.isEmpty ? "/" : parent.lastPathComponent, systemImage: "folder")
                    }.help(parent.path)
                }
            }
        }
    }
    private var fileFilter: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter files", text: $query).textFieldStyle(.plain)
                .accessibilityLabel("Filter project files")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Clear file filter").accessibilityLabel("Clear file filter")
            }
        }.font(.caption).padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10).padding(.bottom, 5)
    }
    private var fileList: some View {
        List(filtered) { item in fileRow(item) }
            .listStyle(.sidebar).disabled(navigationDisabled)
            .overlay { emptyListMessage }
    }
    @ViewBuilder private var emptyListMessage: some View {
        if filtered.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: query.isEmpty ? "folder" : "magnifyingglass").font(.title3)
                Text(query.isEmpty ? "No visible files" : "No matching files").font(.caption)
            }.foregroundStyle(.secondary).allowsHitTesting(false)
        }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(kernelState == "Ready" ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(kernelState).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(filtered.count == 1 ? "1 file" : "\(filtered.count) files").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.horizontal, 14).padding(.bottom, 10).help("Python: " + interpreter)
    }
    private func fileRow(_ item: ProjectItem) -> some View {
        let directory = item.isDirectory
        return Button { onOpen(item) } label: {
            HStack(spacing: 7) {
                Image(systemName: directory ? "folder.fill" : icon(for: item.url))
                    .foregroundStyle(directory ? Color.blue : Color.secondary).frame(width: 15)
                Text(item.url.lastPathComponent).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if directory { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).help(item.url.path)
            .contextMenu { fileChoices(item) }
    }
    @ViewBuilder private func fileChoices(_ item: ProjectItem) -> some View {
        Button("Open", systemImage: item.isDirectory ? "folder" : "doc.text") { onOpen(item) }
        Button("Show in Finder", systemImage: "folder") { reveal(item.url, select: true) }
        Button("Copy Path", systemImage: "doc.on.doc") { copyPath(item.url) }
        Divider()
        Button("Rename…") { onRename(item) }
        Button("Duplicate") { onDuplicate(item) }
    }
    private var dropArea: some View {
        HStack(spacing: 8) {
            if loadingDrop || isOpeningFiles { ProgressView().controlSize(.small) }
            else { Image(systemName: "square.and.arrow.down").font(.title3).foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary) }
            VStack(alignment: .leading, spacing: 2) {
                Text(isOpeningFiles ? "Opening files…" : loadingDrop ? "Reading file locations…" : "Drop files here").font(.caption.weight(.medium))
                Text("Notebook · Python · Data · Folder").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(dropTargeted ? 0.13 : 0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(dropTargeted ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4,3])))
            .magneticDropFeedback(isTargeted: dropTargeted, cornerRadius: 10, movesContent: false)
            .help("Drop .ipynb to open, .py/.pyw to import as a new notebook, or CSV, NumPy, MAT, and Excel files to import. Python code is not run automatically.")
            .accessibilityLabel("Drop project files")
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !navigationDisabled, !providers.isEmpty else { return false }
        loadingDrop = true
        ProjectFileDropLoader.load(providers) { result in
            loadingDrop = false
            switch result {
            case .success(let urls): onDropFiles(urls)
            case .failure(let error): localError = error.localizedDescription
            }
        }
        return true
    }
    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "ipynb": return "book.closed"
        case "py", "pyw": return "chevron.left.forwardslash.chevron.right"
        case "csv", "xlsx", "xls", "npy", "mat": return "tablecells"
        default: return "doc.text"
        }
    }
    private func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
    private func reveal(_ url: URL, select: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            localError = "This file or folder is no longer available: " + url.path
            return
        }
        if select { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else if !NSWorkspace.shared.open(url) { localError = "Finder could not open this folder: " + url.path }
    }
}
