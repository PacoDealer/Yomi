import SwiftUI

// MARK: - TachiyomiImportView
//
// S147: what a Mihon / Tachiyomi / Tachimanga backup brought in, and the one-tap way to make it work. Each source the
// imported titles use is resolved live against the user's repositories: ready (its extension is added), available
// (a repository has it — "Add"), or missing (kept in the Library; Migrate moves them). Repositories the backup
// carried are only added when the user taps Add (S140 rule: Yomi never adds or suggests a repository on its own).

struct TachiyomiImportView: View {
    let report: BackupManager.TachiyomiImportReport

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas
    @State private var keiyoushi = KeiyoushiRepository.shared
    @State private var settings = AppSettings.shared
    @State private var busy: Set<String> = []
    @State private var errorText: String?
    @State private var showAddRepo = false

    private enum SourceState { case ready, available(KeiyoushiExtension), missing }

    private struct SourceRow: Identifiable {
        let id: String
        let name: String
        let titles: Int
    }

    private var sources: [SourceRow] {
        report.titlesPerSource.map { id, count in
            SourceRow(id: id, name: sourceName(id), titles: count)
        }
        .sorted { $0.titles != $1.titles ? $0.titles > $1.titles
                                         : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func sourceName(_ id: String) -> String {
        if let name = report.sourceNames[id] { return name }
        if let source = keiyoushi.available.lazy.flatMap(\.sources).first(where: { $0.id == id }) { return source.name }
        return "Unknown source"
    }

    private func state(_ id: String) -> SourceState {
        if keiyoushi.installedExtension(forSourceId: id) != nil { return .ready }
        if let ext = keiyoushi.available.first(where: { $0.sources.contains { $0.id == id } }) { return .available(ext) }
        return .missing
    }

    /// Backup repositories the user hasn't added yet (compared by folder, so index.pb vs index.min.json match).
    private var reposToAdd: [String] {
        let have = Set(settings.mihonRepoURLs.map(Self.folder))
        return report.repoURLs.filter { !have.contains(Self.folder($0)) }
    }

    nonisolated private static func folder(_ url: String) -> String {
        let lower = url.lowercased()
        guard lower.hasSuffix(".pb") || lower.hasSuffix(".json") else { return lower }
        return lower.components(separatedBy: "/").dropLast().joined(separator: "/")
    }

    private var hasMissing: Bool {
        sources.contains { if case .missing = state($0.id) { return true }; return false }
    }

    private var addable: [KeiyoushiExtension] {
        var seen = Set<String>()
        return sources.compactMap { row in
            if case .available(let ext) = state(row.id), seen.insert(ext.id).inserted { return ext }
            return nil
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            CalmList {
                summarySection
                if !reposToAdd.isEmpty { reposSection }
                sourcesSection
                if let errorText {
                    Section {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .sheet(isPresented: $showAddRepo) { AddRepoSheet() }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(report.titleCount) title\(report.titleCount == 1 ? "" : "s") imported")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(canvas.textPrimary)
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(canvas.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var summaryLine: String {
        var parts = ["\(report.libraryCount) in your Library"]
        if report.categoryCount > 0 {
            parts.append("\(report.categoryCount) categor\(report.categoryCount == 1 ? "y" : "ies")")
        }
        let ready = sources.filter { if case .ready = state($0.id) { return true }; return false }
            .reduce(0) { $0 + $1.titles }
        parts.append("\(ready) ready to read")
        return parts.joined(separator: " · ")
    }

    private var reposSection: some View {
        Section {
            ForEach(reposToAdd, id: \.self) { url in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PluginCatalogService.repoLabel(from: url))
                            .foregroundStyle(canvas.textPrimary)
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(canvas.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    pill("Add", busyKey: "repo:\(url)") { await addRepo(url) }
                }
            }
        } header: { CalmSectionHeader("Repositories in your backup") } footer: {
            Text("Add the repositories your sources came from to find their extensions.")
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
        }
    }

    private var sourcesSection: some View {
        Section {
            if hasMissing {
                Button { showAddRepo = true } label: {
                    Label("Add a Repository", systemImage: "link")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            if addable.count > 1 {
                Button {
                    Task { for ext in addable { await install(ext) } }
                } label: {
                    Text("Add All \(addable.count) Extensions")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(!busy.isEmpty)
            }
            ForEach(sources) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .foregroundStyle(canvas.textPrimary)
                        Text("\(row.titles) title\(row.titles == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(canvas.textSecondary)
                    }
                    Spacer()
                    switch state(row.id) {
                    case .ready:
                        Image(systemName: "checkmark")
                            .foregroundStyle(canvas.textSecondary)
                            .accessibilityLabel("Ready")
                    case .available(let ext):
                        pill("Add", busyKey: "kei:\(ext.id)") { await install(ext) }
                    case .missing:
                        Text("Not found")
                            .font(.footnote)
                            .foregroundStyle(canvas.textSecondary)
                    }
                }
            }
        } header: { CalmSectionHeader("Sources") } footer: {
            if hasMissing {
                Text("\"Not found\" means none of your repositories has that source yet — paste the link of the repository you used before, and its extensions show up here. Titles stay in your Library with their progress either way; Browse → Migrate moves them to another source.")
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
            }
        }
    }

    private func pill(_ title: String, busyKey: String, action: @escaping () async -> Void) -> some View {
        Group {
            if busy.contains(busyKey) {
                ProgressView()
            } else {
                Button(title) { Task { await action() } }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.accentColor)
                    .disabled(!busy.isEmpty)
            }
        }
    }

    // MARK: Actions

    private func addRepo(_ url: String) async {
        busy.insert("repo:\(url)")
        defer { busy.remove("repo:\(url)") }
        errorText = nil
        do {
            try await keiyoushi.addRepository(url)
        } catch {
            // Older backups name index.min.json; Keiyoushi moved to index.pb (2026-08) — the folder tries both.
            let folder = url.components(separatedBy: "/").dropLast().joined(separator: "/")
            do {
                try await keiyoushi.addRepository(folder)
            } catch {
                errorText = "Couldn't add \(PluginCatalogService.repoLabel(from: url)): \(error.localizedDescription)"
            }
        }
    }

    private func install(_ ext: KeiyoushiExtension) async {
        busy.insert("kei:\(ext.id)")
        defer { busy.remove("kei:\(ext.id)") }
        errorText = nil
        // Only the languages the imported titles use, so Browse isn't filled with every language of a big extension.
        let needed = Set(ext.sources.filter { report.titlesPerSource[$0.id] != nil }.map(\.lang))
        do {
            try await keiyoushi.install(ext, langs: needed.isEmpty ? nil : needed.sorted())
        } catch {
            errorText = "Couldn't add \(ext.name): \(error.localizedDescription)"
        }
    }
}
