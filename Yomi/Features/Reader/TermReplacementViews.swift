import SwiftUI

// MARK: - Term replacement screens (S177)
//
// "Replace…" in the novel reader's text-selection menu opens the editor with the selected text; the reader panel's
// Reading tab lists every rule for the novel. Rules live in `term_replacement` (v30); `TermReplacer` applies them.

/// Add or edit one rule.
struct TermReplacementEditor: View {
    @State var rule: TermReplacement
    let novelId: String
    let isNew: Bool
    /// Called after a save or delete, so the reader can reload the chapter.
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var replaceFocused: Bool

    private var findTrimmed: String { rule.find.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Find", text: $rule.find, axis: .vertical)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Replace with (empty removes it)", text: $rule.replacement, axis: .vertical)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($replaceFocused)
                } footer: {
                    Text("Whole words only, so “Li” doesn’t change “Like”.")
                }
                Section {
                    Picker("Apply to", selection: scope) {
                        Text("This novel").tag(true)
                        Text("All novels").tag(false)
                    }
                    Toggle("Match case", isOn: $rule.matchCase)
                }
                if !isNew {
                    Section {
                        Button("Delete Replacement", role: .destructive) {
                            try? TermReplacementQueries.delete(id: rule.id)
                            onChange()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Replace Term" : "Edit Replacement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        rule.find = findTrimmed
                        try? TermReplacementQueries.save(rule)
                        onChange()
                        dismiss()
                    }
                    .disabled(findTrimmed.isEmpty)
                }
            }
            .onAppear { if isNew && !findTrimmed.isEmpty { replaceFocused = true } }
        }
        .presentationDetents([.medium, .large])
    }

    private var scope: Binding<Bool> {
        Binding(get: { rule.novelId != nil }, set: { rule.novelId = $0 ? novelId : nil })
    }
}

/// Every rule that applies to this novel.
struct TermReplacementList: View {
    let novelId: String
    let onChange: () -> Void
    @State private var rules: [TermReplacement] = []
    @State private var editing: TermReplacement?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if rules.isEmpty {
                    ContentUnavailableView {
                        Label("No Replacements", systemImage: "character.cursor.ibeam")
                    } description: {
                        Text("Select text in a chapter and choose Replace… — or add one here. Fixes names a translation spells differently from chapter to chapter.")
                    }
                    .listRowBackground(Color.clear)
                }
                section("This novel", rules.filter { $0.novelId != nil })
                section("All novels", rules.filter { $0.novelId == nil })
            }
            .navigationTitle("Replacements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { editing = .new(novelId: novelId) }
                }
            }
            .sheet(item: $editing) { rule in
                TermReplacementEditor(rule: rule, novelId: novelId, isNew: !rules.contains { $0.id == rule.id }) {
                    reload()
                    onChange()
                }
            }
            .onAppear(perform: reload)
        }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, _ list: [TermReplacement]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { rule in
                    Button { editing = rule } label: {
                        HStack(spacing: 8) {
                            Text(rule.find).foregroundStyle(.primary)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            Text(rule.replacement.isEmpty ? "removed" : rule.replacement)
                                .foregroundStyle(rule.replacement.isEmpty ? .secondary : .primary)
                                .italic(rule.replacement.isEmpty)
                        }
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(rule.find) becomes \(rule.replacement.isEmpty ? "nothing" : rule.replacement)")
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            try? TermReplacementQueries.delete(id: rule.id)
                            reload()
                            onChange()
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        rules = (try? TermReplacementQueries.all(novelId: novelId)) ?? []
    }
}
