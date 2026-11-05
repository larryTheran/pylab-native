import SwiftUI

struct EditorSettingsView: View {
    @ObservedObject var preferences: EditorPreferences = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "textformat.size").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editor Appearance").font(.headline)
                    Text("Applies to all notebook editors").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(20)
            Divider()
            Form {
                Picker("Code colors", selection: Binding(get: { preferences.palette }, set: { preferences.setPalette($0) })) {
                    ForEach(EditorPalette.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Text("Font size")
                    Spacer()
                    Stepper(value: Binding(get: { preferences.fontSize }, set: { preferences.setFontSize($0) }), in: EditorPreferences.fontSizeRange, step: 1) {
                        Text("\(Int(preferences.fontSize)) pt").monospacedDigit().frame(width: 45, alignment: .trailing)
                    }.fixedSize()
                }
                Toggle("Line numbers", isOn: Binding(get: { preferences.showsLineNumbers }, set: { preferences.setShowsLineNumbers($0) }))
                    .help("Shows the gutter with line numbers, folding arrows, and breakpoints")
                Toggle("Indentation guides", isOn: Binding(get: { preferences.showsIndentGuides }, set: { preferences.setShowsIndentGuides($0) }))
            }.formStyle(.grouped).scrollDisabled(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                preview.font(.system(size: preferences.fontSize, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }.padding(.horizontal, 20).padding(.bottom, 18)
            Divider()
            HStack {
                Button("Restore Defaults") { preferences.reset() }
                Spacer()
                Text("Changes apply immediately").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.frame(width: 510, height: 500)
    }
    private func color(_ kind: PythonSyntaxKind) -> Color {
        Color(nsColor: preferences.palette.color(kind, dark: colorScheme == .dark))
    }
    private var preview: Text {
        let comment = Text("# A small calculation\n").foregroundColor(color(.comment))
        let definition = Text("def ").foregroundColor(color(.keyword))
        let function = Text("scale").foregroundColor(color(.function))
        let keyword = Text("return ").foregroundColor(color(.keyword))
        let builtin = Text("sum").foregroundColor(color(.builtin))
        let number = Text("2.0").foregroundColor(color(.number))
        return Text("\(comment)\(definition)\(function)(values):\n    \(keyword)\(builtin)(values) * \(number)")
    }
}
