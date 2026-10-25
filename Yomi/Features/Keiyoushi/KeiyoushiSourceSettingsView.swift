import SwiftUI

// MARK: - KeiyoushiSourceSettingsView
//
// S156: an extension's own settings for one source (Mihon's "source preferences" — e.g. Asura's "Hide premium
// chapters"). The extension declares them; the bridge lists them with their values and stores every change
// (`KeiyoushiBridge.preferences` / `setPreference`). Opened from the gear in `KeiyoushiBrowseView`. Calm style.

struct KeiyoushiSourceSettingsView: View {
    let source: KeiyoushiSource

    @Environment(\.yomiCanvas) private var canvas
    @State private var preferences: [KeiyoushiPreference]?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var editing: KeiyoushiPreference?
    @State private var draft = ""

    var body: some View {
        Group {
            if let preferences {
                if preferences.isEmpty {
                    YomiEmptyState(systemImage: "gearshape", title: "No settings",
                                   message: "\(source.name) has no settings of its own.")
                } else {
                    list(preferences)
                }
            } else if let loadError {
                YomiEmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't load the settings",
                               message: "\(loadError)", actionLabel: "Try again", actionIcon: "arrow.clockwise") {
                    Task { await load() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(editing?.title ?? "", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
               presenting: editing) { preference in
            TextField(preference.title, text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { change(preference, to: .text(draft)) }
            Button("Cancel", role: .cancel) {}
        } message: { preference in
            if !preference.summary.isEmpty { Text(preference.summary) }
        }
        .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func list(_ preferences: [KeiyoushiPreference]) -> some View {
        CalmList {
            Section {
                ForEach(preferences) { row($0) }
            } header: {
                CalmSectionHeader("Extension settings")
            } footer: {
                Text("These come from the extension, not from Yomi. A change to how chapters are listed shows after the title's chapter list is refreshed.")
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func row(_ preference: KeiyoushiPreference) -> some View {
        switch preference.value {
        case .toggle(let on):
            Toggle(isOn: Binding(get: { on }, set: { change(preference, to: .toggle($0)) })) {
                label(preference)
            }
        case .text(let text):
            Button {
                draft = text
                editing = preference
            } label: {
                LabeledContent {
                    Text(text.isEmpty ? String(localized: "Not set") : text).lineLimit(1)
                } label: {
                    label(preference)
                }
            }
            .buttonStyle(.plain)
        case .choice(let index, let entries, let entryValues):
            Picker(selection: Binding(get: { index }, set: {
                change(preference, to: .choice(index: $0, entries: entries, entryValues: entryValues))
            })) {
                if !entries.indices.contains(index) { Text("Not set").tag(index) }
                ForEach(entries.indices, id: \.self) { Text(entries[$0]).tag($0) }
            } label: {
                label(preference)
            }
        case .multiChoice(let selected, let entries, let entryValues):
            NavigationLink {
                KeiyoushiMultiChoiceView(title: preference.title, entries: entries, entryValues: entryValues,
                                         selected: selected) {
                    change(preference, to: .multiChoice(selected: $0, entries: entries, entryValues: entryValues))
                }
            } label: {
                LabeledContent {
                    Text(selected.isEmpty ? "None" : "\(selected.count) of \(entries.count)")
                } label: {
                    label(preference)
                }
            }
        }
    }

    @ViewBuilder
    private func label(_ preference: KeiyoushiPreference) -> some View {
        Text(preference.title)
        if !preference.summary.isEmpty { Text(preference.summary) }
    }

    // MARK: - Actions

    private func load() async {
        loadError = nil
        do {
            preferences = try await KeiyoushiBridge.shared.preferences(sourceId: source.id)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Shows the new value at once, then takes the bridge's answer as the truth (or puts the old list back).
    private func change(_ preference: KeiyoushiPreference, to value: KeiyoushiPreference.Value) {
        guard value != preference.value else { return }
        let before = preferences
        if let i = preferences?.firstIndex(where: { $0.key == preference.key }) { preferences?[i].value = value }
        Task {
            do {
                preferences = try await KeiyoushiBridge.shared.setPreference(preference, to: value, sourceId: source.id)
            } catch {
                preferences = before
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - KeiyoushiMultiChoiceView

/// A "pick any" extension setting (e.g. MangaFire's content rating): one switch per entry, saved on every change.
private struct KeiyoushiMultiChoiceView: View {
    let title: String
    let entries: [String]
    let entryValues: [String]
    @State var selected: Set<String>
    let onChange: (Set<String>) -> Void

    var body: some View {
        CalmList {
            Section {
                ForEach(Array(zip(entries, entryValues)), id: \.1) { entry, value in
                    Toggle(entry, isOn: Binding(get: { selected.contains(value) }, set: { on in
                        if on { selected.insert(value) } else { selected.remove(value) }
                        onChange(selected)
                    }))
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
