import SwiftUI
import AppKit

/// Choose and inspect the Python executable without resolving environment links.
struct KernelSettingsView: View {
    let currentPath: String
    let onApply: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var path: String
    @State private var errorMessage: String?
    @State private var confirmSwitch = false
    @StateObject private var inspection = EnvironmentInspectionModel()
    private let defaultPython = "/opt/miniconda3/bin/python3.12"

    init(currentPath: String, onApply: @escaping (String) -> Bool) {
        self.currentPath = currentPath; self.onApply = onApply
        _path = State(initialValue: currentPath)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "cpu").font(.title2).foregroundStyle(.tint)
                    .frame(width: 44, height: 44).glassEffect(.regular, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Python Environment").font(.title2.weight(.semibold))
                    Text("Choose Python and check the packages available to this project.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Python executable").font(.headline)
                        HStack {
                            TextField("/path/to/python", text: $path)
                                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                                .accessibilityIdentifier("kernelPythonPath")
                            Button("Browse…", action: browse).buttonStyle(.glass)
                        }
                        Text("Paste a virtual environment's bin/python path to keep that environment selected.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Use Default Miniconda") { path = defaultPython; errorMessage = nil }
                                .buttonStyle(.glass).controlSize(.small)
                            Spacer()
                            if inspection.isChecking {
                                ProgressView().controlSize(.small)
                                Button("Cancel Check") { inspection.cancel() }.controlSize(.small)
                            } else {
                                Button("Check Environment") { inspection.check(pythonPath: normalizedPath) }
                                    .buttonStyle(.glass).controlSize(.small)
                            }
                        }
                    }
                    if let errorMessage { message(errorMessage, color: .red) }
                    if let error = inspection.error { message(error, color: .orange) }
                    if let report = inspection.report { environmentReport(report) }
                    else if !inspection.isChecking && inspection.error == nil {
                        Text("Check Environment shows the Python version, architecture, and installed scientific packages.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }
            Divider()
            HStack {
                Text("Switching Python restarts this project's kernel.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Use Python") { requestApply() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 690, height: 650)
        .onAppear { inspection.check(pythonPath: normalizedPath) }
        .onChange(of: path) { _, _ in inspection.cancel(); errorMessage = nil }
        .onDisappear { inspection.cancel() }
        .alert("Switch Python kernel?", isPresented: $confirmSwitch) {
            Button("Cancel", role: .cancel) { }
            Button("Switch Kernel") { apply() }
        } message: {
            Text("Running code stops and live workspace variables are cleared. Notebook cells and outputs stay in place.")
        }
    }
    private func environmentReport(_ report: PythonEnvironmentReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(report.missingRequired.isEmpty ? "Required packages found" : "Missing required packages",
                      systemImage: report.missingRequired.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(report.missingRequired.isEmpty ? Color.green : Color.orange)
                Spacer()
                Button("Copy Details") { copy(report.summary) }.controlSize(.small)
            }
            HStack(spacing: 16) {
                Text("Python " + report.version).fontWeight(.medium)
                Text(report.architecture).foregroundStyle(.secondary)
                Text(report.implementation).foregroundStyle(.secondary)
            }.font(.callout)
            Text(report.executable).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            VStack(spacing: 0) {
                ForEach(report.packages) { package in
                    HStack(spacing: 8) {
                        Image(systemName: package.version != nil ? "checkmark.circle" : (package.required ? "exclamationmark.circle" : "minus.circle"))
                            .foregroundStyle(package.version != nil ? Color.green : (package.required ? Color.orange : Color.secondary))
                        Text(package.name).font(.system(.callout, design: .monospaced))
                        if !package.required { Text("Optional").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        Text(package.version ?? "Not installed").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }.padding(10).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            Text("Installed versions are read from package metadata. Python imports are checked when the kernel starts.")
                .font(.caption).foregroundStyle(.secondary)
            if let command = report.installCommand(pythonPath: normalizedPath) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install missing required packages in this environment:").font(.callout)
                    Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    Button("Copy Install Command") { copy(command) }.buttonStyle(.glass).controlSize(.small)
                }
            }
        }
    }
    private func message(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(color)
            .font(.callout).fixedSize(horizontal: false, vertical: true)
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private var normalizedPath: String { (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath }
    private func requestApply() {
        let candidate = normalizedPath
        var directory: ObjCBool = false
        guard !candidate.isEmpty, candidate.hasPrefix("/"), FileManager.default.fileExists(atPath: candidate, isDirectory: &directory),
              !directory.boolValue, FileManager.default.isExecutableFile(atPath: candidate) else {
            errorMessage = "Choose an absolute path to an executable Python file."; return
        }
        errorMessage = nil
        if candidate == currentPath { dismiss() } else { confirmSwitch = true }
    }
    private func apply() {
        if onApply(normalizedPath) { dismiss() }
        else { errorMessage = "The selected Python executable is unavailable. Check the path and try again." }
    }
    private func browse() {
        let panel = NSOpenPanel(); panel.message = "Choose a Python executable"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { path = url.path; errorMessage = nil }
    }
}
