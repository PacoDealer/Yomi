import SwiftUI

// MARK: - PluginFilter
//
// An LNReader plugin's own filters (`plugin.filters`: genres, status, sort…), shown in Browse → a novel source →
// filter button (S170, group G; Tachimanga/LNReader parity). Types are LNReader's `FilterTypes`
// (lnreader-plugins src/types/filters.ts): Text, Picker, Checkbox, Switch, XCheckbox. The chosen values go back to
// `popularNovels(page, { filters })` with each filter's `value` replaced (`JSBridge.popularNovels(page:filters:)`).

nonisolated struct PluginFilter: Identifiable, Equatable, Sendable {
    struct Option: Equatable, Sendable, Hashable {
        let label: String
        let value: String
    }

    enum Kind: Equatable, Sendable {
        case text(String)
        case picker(options: [Option], value: String)
        case checkbox(options: [Option], values: [String])
        case toggle(Bool)
        case excludable(options: [Option], include: [String], exclude: [String])
    }

    let key: String
    let label: String
    var kind: Kind
    var id: String { key }

    /// The filters as `JSBridge.lnreaderFiltersJSON` lists them; filters of an unknown type are left out.
    static func parse(_ json: String) -> [PluginFilter] {
        guard let items = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let key = item["key"] as? String, let type = item["type"] as? String else { return nil }
            let label = (item["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
            let options = ((item["options"] as? [[String: Any]]) ?? []).compactMap { option -> Option? in
                guard let value = option["value"] else { return nil }
                return Option(label: option["label"] as? String ?? "\(value)", value: "\(value)")
            }
            let value = item["value"]
            let kind: Kind
            switch type {
            case "Text": kind = .text(value as? String ?? "")
            case "Picker": kind = .picker(options: options, value: value.map { "\($0)" } ?? options.first?.value ?? "")
            case "Checkbox": kind = .checkbox(options: options, values: (value as? [Any])?.map { "\($0)" } ?? [])
            case "Switch": kind = .toggle(value as? Bool ?? false)
            case "XCheckbox":
                let dict = value as? [String: Any]
                kind = .excludable(options: options,
                                   include: (dict?["include"] as? [Any])?.map { "\($0)" } ?? [],
                                   exclude: (dict?["exclude"] as? [Any])?.map { "\($0)" } ?? [])
            default: return nil
            }
            return PluginFilter(key: key, label: label, kind: kind)
        }
    }

    /// `{ key: value }` for the plugin, as JSON.
    static func valuesJSON(_ filters: [PluginFilter]) -> String {
        var values: [String: Any] = [:]
        for filter in filters {
            switch filter.kind {
            case .text(let text): values[filter.key] = text
            case .picker(_, let value): values[filter.key] = value
            case .checkbox(_, let chosen): values[filter.key] = chosen
            case .toggle(let on): values[filter.key] = on
            case .excludable(_, let include, let exclude): values[filter.key] = ["include": include, "exclude": exclude]
            }
        }
        let data = (try? JSONSerialization.data(withJSONObject: values)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - PluginFilterSheet

struct PluginFilterSheet: View {
    let defaults: [PluginFilter]
    @State var draft: [PluginFilter]
    let onApply: ([PluginFilter]) -> Void

    @Environment(\.yomiCanvas) private var canvas
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CalmList {
                Section {
                    ForEach($draft) { $filter in
                        PluginFilterRow(filter: $filter)
                    }
                } footer: {
                    Text("These filters come from the source, not from Yomi.")
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { draft = defaults }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - PluginFilterRow

private struct PluginFilterRow: View {
    @Binding var filter: PluginFilter
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        switch filter.kind {
        case .text(let text):
            LabeledContent(filter.label) {
                TextField("Any", text: Binding(get: { text }, set: { filter.kind = .text($0) }))
                    .multilineTextAlignment(.trailing)
            }
        case .picker(let options, let value):
            Picker(filter.label, selection: Binding(get: { value }, set: { filter.kind = .picker(options: options, value: $0) })) {
                ForEach(options, id: \.self) { Text($0.label).tag($0.value) }
            }
        case .toggle(let on):
            Toggle(filter.label, isOn: Binding(get: { on }, set: { filter.kind = .toggle($0) }))
        case .checkbox(_, let values):
            NavigationLink {
                PluginOptionsView(filter: $filter)
            } label: {
                LabeledContent(filter.label) { if !values.isEmpty { Text("\(values.count) chosen") } }
            }
        case .excludable(_, let include, let exclude):
            NavigationLink {
                PluginOptionsView(filter: $filter)
            } label: {
                LabeledContent(filter.label) {
                    if !include.isEmpty || !exclude.isEmpty { Text("\(include.count + exclude.count) chosen") }
                }
            }
        }
    }
}

// MARK: - PluginOptionsView

/// The options of a checkbox group on their own screen (genre lists run to dozens). In an excludable group a tap
/// cycles include → exclude → off, like Tachimanga's tri-state boxes.
private struct PluginOptionsView: View {
    @Binding var filter: PluginFilter
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        CalmList {
            Section {
                ForEach(options, id: \.self) { option in
                    Button { toggle(option.value) } label: {
                        HStack {
                            Text(option.label).foregroundStyle(canvas.textPrimary)
                            Spacer()
                            mark(option.value)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                if case .excludable = filter.kind {
                    Text("Tap once to include, twice to exclude, three times to clear.")
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
        }
        .navigationTitle(filter.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var options: [PluginFilter.Option] {
        switch filter.kind {
        case .checkbox(let options, _), .excludable(let options, _, _): options
        default: []
        }
    }

    @ViewBuilder
    private func mark(_ value: String) -> some View {
        switch filter.kind {
        case .checkbox(_, let values) where values.contains(value):
            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
        case .excludable(_, let include, _) where include.contains(value):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                .accessibilityLabel("Included")
        case .excludable(_, _, let exclude) where exclude.contains(value):
            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                .accessibilityLabel("Excluded")
        default:
            EmptyView()
        }
    }

    private func toggle(_ value: String) {
        switch filter.kind {
        case .checkbox(let options, var values):
            if let index = values.firstIndex(of: value) { values.remove(at: index) } else { values.append(value) }
            filter.kind = .checkbox(options: options, values: values)
        case .excludable(let options, var include, var exclude):
            if include.contains(value) {
                include.removeAll { $0 == value }
                exclude.append(value)
            } else if exclude.contains(value) {
                exclude.removeAll { $0 == value }
            } else {
                include.append(value)
            }
            filter.kind = .excludable(options: options, include: include, exclude: exclude)
        default:
            break
        }
    }
}
