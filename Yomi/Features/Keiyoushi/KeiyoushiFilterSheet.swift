import SwiftUI

// MARK: - KeiyoushiFilterSheet
//
// S157: a source's own search filters (sort, status, genres…), opened from the filter button in
// `KeiyoushiBrowseView`. Nothing is searched until "Search" — the choices are a draft. "Reset" asks the
// extension for its list again, which is also how a list the extension loads late (Asura's genres) arrives.

struct KeiyoushiFilterSheet: View {
    /// The extension's list with nothing chosen.
    @State var defaults: [KeiyoushiFilter]
    @State var draft: [KeiyoushiFilter]
    /// Asks the extension again; nil when that failed.
    let reload: () async -> [KeiyoushiFilter]?
    let onSearch: (_ filters: [KeiyoushiFilter], _ defaults: [KeiyoushiFilter]) -> Void

    @Environment(\.yomiCanvas) private var canvas
    @Environment(\.dismiss) private var dismiss
    @State private var isReloading = false

    var body: some View {
        NavigationStack {
            CalmList {
                Section {
                    ForEach($draft) { $filter in
                        if case .group = filter.kind {
                            if filter.isEditable { groupLink($filter) }
                        } else {
                            KeiyoushiFilterRow(filter: $filter)
                        }
                    }
                } footer: {
                    Text("These filters come from the extension, not from Yomi.")
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { Task { await reset() } }
                        .disabled(isReloading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search") {
                        onSearch(draft, defaults)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func groupLink(_ filter: Binding<KeiyoushiFilter>) -> some View {
        let original = defaults.first { $0.id == filter.wrappedValue.id }
        let chosen = original.map { filter.wrappedValue.changes(from: $0) } ?? 0
        return NavigationLink {
            KeiyoushiFilterGroupView(group: filter)
        } label: {
            LabeledContent(filter.wrappedValue.name) {
                if chosen > 0 { Text("\(chosen) chosen") }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func reset() async {
        isReloading = true
        defer { isReloading = false }
        if let fresh = await reload() { defaults = fresh }
        draft = defaults
    }
}

// MARK: - KeiyoushiFilterGroupView

/// The boxes of one group (e.g. MangaFire's genres) on their own screen — these lists run to dozens of rows.
private struct KeiyoushiFilterGroupView: View {
    @Binding var group: KeiyoushiFilter

    private var children: Binding<[KeiyoushiFilter]> {
        Binding(get: {
            if case .group(let children) = group.kind { children } else { [] }
        }, set: {
            group.kind = .group($0)
        })
    }

    var body: some View {
        CalmList {
            Section {
                ForEach(children) { $child in
                    if child.isEditableInGroup || child.kind == .header { KeiyoushiFilterRow(filter: $child) }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - KeiyoushiFilterRow

/// One filter that isn't a group.
private struct KeiyoushiFilterRow: View {
    @Binding var filter: KeiyoushiFilter
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        switch filter.kind {
        case .header:
            Text(filter.name)
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
        case .separator, .group:
            EmptyView()
        case .select(let options, let index):
            Picker(filter.name, selection: Binding(get: { index }, set: {
                filter.kind = .select(options: options, index: $0)
            })) {
                ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
            }
        case .text(let text):
            LabeledContent(filter.name) {
                TextField("Any", text: Binding(get: { text }, set: { filter.kind = .text($0) }))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .checkbox(let on):
            Toggle(filter.name, isOn: Binding(get: { on }, set: { filter.kind = .checkbox($0) }))
        case .triState(let state):
            // One tap = include, a second = exclude, a third = back to ignored (Mihon's order).
            Button {
                filter.kind = .triState((state + 1) % 3)
            } label: {
                HStack {
                    Text(filter.name)
                    Spacer()
                    // Not told apart by colour alone: the accent may be red too.
                    switch state {
                    case 1:
                        Text("Included")
                        Image(systemName: "checkmark")
                    case 2:
                        Text("Excluded")
                        Image(systemName: "minus.circle")
                    default:
                        EmptyView()
                    }
                }
                .foregroundStyle(state == 1 ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(filter.name)
            .accessibilityValue(state == 1 ? "Included" : state == 2 ? "Excluded" : "Ignored")
        case .sort(let options, let index, let ascending):
            Picker(filter.name, selection: Binding(get: { index }, set: {
                filter.kind = .sort(options: options, index: $0, ascending: ascending)
            })) {
                if index == nil { Text("Default").tag(Int?.none) }
                ForEach(options.indices, id: \.self) { Text(options[$0]).tag(Int?.some($0)) }
            }
            if index != nil {
                Toggle("Ascending", isOn: Binding(get: { ascending }, set: {
                    filter.kind = .sort(options: options, index: index, ascending: $0)
                }))
            }
        }
    }
}

#if DEBUG
/// Sample filters of every kind, for the preview.
struct KeiyoushiFilterSheetSample: View {
    var body: some View {
        let json = """
        [{"name":"Sort By","state":{"index":0,"ascending":false},"values":["Latest Update","Popular","Rating","A-Z"]},
         {"name":"Status","state":0,"values":["All","Ongoing","Completed"]},
         {"name":"Min Chapters","state":""},
         {"name":"","state":0},
         {"name":"Completed only","state":false},
         {"name":"Type","state":[{"name":"Manga","state":false},{"name":"Manhwa","state":false}]},
         {"name":"Genres","state":[{"name":"Action","state":0,"isIgnored":true},{"name":"Isekai","state":0,"isIgnored":true},
                                   {"name":"Comedy","state":0,"isIgnored":true}]},
         {"name":"Tap 'Reset' to load filters","state":0}]
        """
        let filters = KeiyoushiFilter.numbered(
            (try? JSONDecoder().decode([KeiyoushiFilter].self, from: Data(json.utf8))) ?? [])
        KeiyoushiFilterSheet(defaults: filters, draft: filters) { nil } onSearch: { _, _ in }
    }
}

#Preview { KeiyoushiFilterSheetSample() }
#endif
