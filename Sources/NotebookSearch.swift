import SwiftUI

struct NotebookSearchView: View {
    @ObservedObject var notebooks: NotebookCollection
    let onSelect: (NotebookSearchResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var allNotebooks = true
    @State private var caseSensitive = false
    @State private var selection: String?
    @FocusState private var searchFocused: Bool

    private var page: NotebookSearchPage {
        let tabs = allNotebooks ? notebooks.tabs : [notebooks.selected]
        return NotebookSearchIndex.search(tabs.map { tab in
            NotebookSearchDocument(id: tab.id, title: tab.title, cells: tab.store.cells.map {
                NotebookSearchCell(id: $0.id, name: $0.name, source: $0.source)
            })
        }, query: query, caseSensitive: caseSensitive)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Find in Notebooks", systemImage: "doc.text.magnifyingglass").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            HStack(spacing: 10) {
                TextField("Search code or cell names", text: $query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                    .onSubmit(openSelected)
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                Toggle("Match Case", isOn: $caseSensitive).toggleStyle(.button)
            }.padding(.horizontal, 16).padding(.bottom, 10)
            HStack {
                Picker("Search", selection: $allNotebooks) {
                    Text("All Open Notebooks").tag(true)
                    Text("Current Notebook").tag(false)
                }.pickerStyle(.segmented).frame(width: 320)
                Spacer()
                Text(page.truncated ? "First 200 matches" : "\(page.results.count) results").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            if page.results.isEmpty {
                ContentUnavailableView.search(text: query).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selection) {
                    ForEach(page.results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(result.cellName).fontWeight(.semibold)
                                Text("· \(result.notebookTitle) · Line \(result.line)").foregroundStyle(.secondary)
                            }.font(.callout).lineLimit(1)
                            Text(result.preview).font(.system(.caption, design: .monospaced)).lineLimit(2)
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 3).tag(result.id)
                            .contentShape(Rectangle()).onTapGesture(count: 2) { choose(result) }
                            .accessibilityAction(named: "Open matching cell") { choose(result) }
                    }
                    }.onSubmit(openSelected)
                        .onChange(of: selection) { _, id in
                            if let id { proxy.scrollTo(id, anchor: .center) }
                        }
                }
            }
            Divider()
            HStack {
                Text("Searches open notebooks in this project").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Go to Cell", action: openSelected).buttonStyle(.glassProminent)
                    .disabled(page.results.isEmpty)
            }.padding(14)
        }.frame(width: 660, height: 480)
            .onAppear { searchFocused = true; selection = page.results.first?.id }
            .onChange(of: page.results.map(\.id)) { _, ids in
                if !ids.contains(selection ?? "") { selection = ids.first }
            }

    }

    private func move(_ delta: Int) {
        let rows = page.results
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? 0
        selection = rows[min(max(current + delta, 0), rows.count - 1)].id
    }

    private func choose(_ result: NotebookSearchResult) { onSelect(result); dismiss() }
    private func openSelected() {
        if let result = page.results.first(where: { $0.id == selection }) ?? page.results.first { choose(result) }
    }
}
