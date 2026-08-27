import SwiftUI

// MARK: - MigrateView
//
// Tachimanga parity: pick a library manga, then find it on another installed source and move
// it over — preserving reading progress/categories/status. Reachable from Browse's segmented
// control ("Sources" / "Global search" / "Migrate").

struct MigrateView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var library: [Manga] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.isEmpty {
                YomiEmptyState(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "Nothing to migrate",
                    message: "Add manga to your library first — Migrate moves an existing title to a different installed source."
                )
            } else {
                List(library) { manga in
                    NavigationLink {
                        MigrateSourcePickerView(oldManga: manga)
                    } label: {
                        HStack(spacing: 12) {
                            CoverImage(url: manga.coverURL)
                                .frame(width: 44, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manga.title)
                                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                                    .lineLimit(1)
                                Text(manga.sourceId)
                                    .font(YomiTokens.Font.mono(11))
                                    .foregroundStyle(canvas.textSecondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Migrate")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            library = (try? MangaQueries.fetchLibrary()) ?? []
            isLoading = false
        }
    }
}

// MARK: - MigrateSourcePickerView

private struct MigrateSourcePickerView: View {
    let oldManga: Manga

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas
    @State private var extensionManager = ExtensionManager.shared
    @State private var query: String
    @State private var sections: [MatchSection] = []
    @State private var pendingCount = 0
    @State private var isSearching = false

    @State private var migrationTarget: (manga: Manga, bridge: JSBridge)? = nil
    @State private var isMigrating = false
    @State private var migrationResult: MigrationService.Result? = nil
    @State private var migrationError: String? = nil

    struct MatchSection: Identifiable {
        let id: String
        let sourceName: String
        let matches: [Manga]
        let bridge: JSBridge
    }

    init(oldManga: Manga) {
        self.oldManga = oldManga
        _query = State(initialValue: oldManga.title)
    }

    var body: some View {
        Group {
            if let result = migrationResult {
                migratedConfirmation(result)
            } else if isSearching && sections.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching \(pendingCount) other source\(pendingCount == 1 ? "" : "s")…")
                        .font(YomiTokens.Font.mono(12))
                        .foregroundStyle(canvas.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                YomiEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No matches found",
                    message: "None of your other installed sources returned a match for \"\(query)\". Try editing the search text below."
                )
            } else {
                resultsList
            }
        }
        .safeAreaInset(edge: .bottom) {
            if migrationResult == nil {
                searchField
            }
        }
        .navigationTitle(oldManga.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { runSearch() }
        .confirmationDialog(
            "Migrate to this source?",
            isPresented: Binding(get: { migrationTarget != nil }, set: { if !$0 { migrationTarget = nil } }),
            titleVisibility: .visible
        ) {
            // Capture `target` by value in each closure — `isPresented`'s auto-dismiss setter
            // clears migrationTarget as part of the same transaction as the button tap, so
            // reading migrationTarget again inside the Task (after a suspension point) would
            // race and silently see nil. Closing over a local `target` avoids that.
            if let target = migrationTarget {
                Button("Migrate and remove old entry") {
                    Task { await performMigration(target: target, removeOld: true) }
                }
                Button("Migrate and keep old entry") {
                    Task { await performMigration(target: target, removeOld: false) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let target = migrationTarget {
                Text("Reading progress, status, and categories will carry over to \"\(target.manga.title)\".")
            }
        }
        .overlay {
            if isMigrating {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Migrating…").tint(.white).foregroundStyle(.white)
                }
            }
        }
        .alert("Migration failed", isPresented: Binding(get: { migrationError != nil }, set: { if !$0 { migrationError = nil } })) {
            Button("OK") { migrationError = nil }
        } message: {
            Text(migrationError ?? "")
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(section.sourceName)
                                .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.headline, weight: .medium))
                            Spacer()
                            Text("\(section.matches.count) match\(section.matches.count == 1 ? "" : "es")")
                                .font(YomiTokens.Font.mono(11))
                                .foregroundStyle(canvas.textSecondary)
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(section.matches) { match in
                                    Button {
                                        migrationTarget = (match, section.bridge)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            CoverImage(url: match.coverURL)
                                                .frame(width: 100, height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            Text(match.title)
                                                .font(YomiTokens.Font.grotesk(12))
                                                .lineLimit(2)
                                                .foregroundStyle(canvas.textPrimary)
                                                .frame(width: 100, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                if pendingCount > 0 {
                    HStack {
                        ProgressView()
                        Text("Searching \(pendingCount) more…")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(canvas.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func migratedConfirmation(_ result: MigrationService.Result) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Migrated")
                .font(YomiTokens.Font.grotesk(20, weight: .medium))
            // Always state the new source's real chapter count — a migration that "succeeded"
            // with far fewer chapters than expected is the user's only signal something is off.
            Text("\(result.newChapterCount) chapter\(result.newChapterCount == 1 ? "" : "s") from the new source.")
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(result.oldReadChapters > 0
                 ? "Carried over \(result.matchedChapters) of \(result.oldReadChapters) read chapters, matched by chapter number."
                 : "No prior reading progress to carry over.")
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack {
            TextField("Search title", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runSearch() }
            Button("Search") { runSearch() }
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Search

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        sections = []
        Task { await runParallelSearch(query: trimmed) }
    }

    private func runParallelSearch(query: String) async {
        let oldSourceId = oldManga.sourceId
        let otherSources = extensionManager.installed.filter { $0.id != oldSourceId }
        isSearching = true
        pendingCount = otherSources.count

        await withTaskGroup(of: MatchSection?.self) { group in
            for ext in otherSources {
                let extId = ext.id
                let extName = ext.name
                group.addTask {
                    await Task.detached(priority: .userInitiated) { () -> MatchSection? in
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let url = docs
                            .appendingPathComponent("Extensions", isDirectory: true)
                            .appendingPathComponent("\(extId).js")
                        guard let bridge = JSBridge(scriptURL: url), !bridge.isLNReaderPlugin else { return nil }
                        let items = bridge.searchManga(query: query, page: 1, sourceId: extId)
                        guard !items.isEmpty else { return nil }
                        return MatchSection(id: extId, sourceName: extName, matches: items, bridge: bridge)
                    }.value
                }
            }
            for await result in group {
                pendingCount = max(0, pendingCount - 1)
                if let section = result {
                    sections.append(section)
                }
            }
        }
        isSearching = false
    }

    // MARK: - Migration

    private func performMigration(target: (manga: Manga, bridge: JSBridge), removeOld: Bool) async {
        isMigrating = true
        let old = oldManga
        let new = target.manga
        let bridge = target.bridge
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try MigrationService.migrate(from: old, to: new, bridge: bridge, removeOld: removeOld)
            }.value
            isMigrating = false
            migrationResult = result
        } catch {
            isMigrating = false
            migrationError = error.localizedDescription
        }
    }
}
