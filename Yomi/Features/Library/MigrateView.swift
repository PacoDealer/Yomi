import SwiftUI

// MARK: - SourceStatus
//
// S147: whether a title's source can serve it on this phone. A Mihon/Tachimanga import keeps titles whose source
// the user hasn't added (or that no repository has); those show "Source not installed" and are offered for migration.

enum SourceStatus {
    /// True when the source a title was saved from is installed (or needs nothing installed).
    static func isInstalled(_ manga: Manga) -> Bool {
        if manga.isLocal || SuwayomiService.isSuwayomiSourceId(manga.sourceId) { return true }
        if KeiyoushiMapping.isKeiyoushiSourceId(manga.sourceId) {
            return KeiyoushiRepository.shared.installedExtension(
                forSourceId: KeiyoushiMapping.mihonSourceId(manga.sourceId)) != nil
        }
        return ExtensionManager.shared.installed.contains { $0.id == manga.sourceId }
    }

    /// An extension in the user's repositories that provides this title's source, when it isn't installed yet.
    static func addableExtension(for manga: Manga) -> KeiyoushiExtension? {
        guard KeiyoushiMapping.isKeiyoushiSourceId(manga.sourceId), !isInstalled(manga) else { return nil }
        let id = KeiyoushiMapping.mihonSourceId(manga.sourceId)
        return KeiyoushiRepository.shared.available.first { $0.sources.contains { $0.id == id } }
    }

    /// Source names a Mihon/Tachimanga backup recorded (Mihon id → name) — the only name Yomi knows for a source
    /// no repository lists.
    nonisolated static let importedNamesKey = "importedSourceNames"
    static var importedNames: [String: String] {
        UserDefaults.standard.dictionary(forKey: importedNamesKey) as? [String: String] ?? [:]
    }

    /// The installed source's display name for a stored source id (a plugin id or `keiyoushi_<id>`).
    static func sourceName(_ sourceId: String) -> String {
        if let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) { return ext.name }
        if KeiyoushiMapping.isKeiyoushiSourceId(sourceId) {
            let keiyoushiId = KeiyoushiMapping.mihonSourceId(sourceId)
            if let ext = KeiyoushiRepository.shared.installedExtension(forSourceId: keiyoushiId),
               let source = ext.info.sources.first(where: { $0.id == keiyoushiId }) {
                return ext.info.sources.count > 1 ? "\(source.name) · \(source.lang.uppercased())" : source.name
            }
            if let source = KeiyoushiRepository.shared.available.lazy.flatMap(\.sources)
                .first(where: { $0.id == keiyoushiId }) {
                return source.name
            }
            if let name = importedNames[keiyoushiId] { return name }
        }
        return "Unknown source"
    }
}

// MARK: - MigrateView
//
// Tachimanga parity: pick a library manga, then find it on another installed source and move
// it over — preserving reading progress/categories/status. Browse's Migrate tab.
// S147: calm style; titles whose source isn't installed come first; Keiyoushi sources are searched too.

struct MigrateView: View {
    /// Shown as Browse's Migrate tab (Browse owns the title).
    var embedded = false

    @Environment(\.yomiCanvas) private var canvas
    @State private var library: [Manga] = []
    @State private var isLoading = true

    private var missing: [Manga] { library.filter { !SourceStatus.isInstalled($0) } }
    private var installed: [Manga] { library.filter { SourceStatus.isInstalled($0) } }

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
                CalmList {
                    if !missing.isEmpty {
                        Section {
                            ForEach(missing) { row($0, subtitle: "Source not installed") }
                        } header: { CalmSectionHeader("Source not installed") } footer: {
                            Text("These titles' sources aren't on this iPhone. Move each one to a source you have.")
                                .font(.footnote)
                                .foregroundStyle(canvas.textSecondary)
                        }
                    }
                    Section {
                        ForEach(installed) { row($0, subtitle: SourceStatus.sourceName($0.sourceId)) }
                    } header: {
                        if !missing.isEmpty { CalmSectionHeader("Library") }
                    }
                }
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(embedded ? "Browse" : "Migrate")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            library = (try? await Task.detached(priority: .userInitiated) { try MangaQueries.fetchLibrary() }.value) ?? []
            isLoading = false
        }
    }

    private func row(_ manga: Manga, subtitle: String) -> some View {
        NavigationLink {
            MigrateSourcePickerView(oldManga: manga)
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: manga.coverURL)
                    .frame(width: 44, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(manga.title)
                        .foregroundStyle(canvas.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - MigrateSourcePickerView

struct MigrateSourcePickerView: View {
    let oldManga: Manga

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas
    @State private var query: String
    @State private var sections: [MatchSection] = []
    @State private var pendingCount = 0
    @State private var isSearching = false
    @State private var searchGeneration = 0

    @State private var migrationTarget: (manga: Manga, source: MatchSource)? = nil
    @State private var isMigrating = false
    @State private var migrationResult: MigrationService.Result? = nil
    @State private var migrationError: String? = nil

    /// Where a match came from — the chapter list is fetched differently for each.
    enum MatchSource {
        case js(JSBridge)
        case keiyoushi(sourceId: String)
    }

    struct MatchSection: Identifiable {
        let id: String
        let sourceName: String
        let matches: [Manga]
        let source: MatchSource
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
                        .font(.footnote)
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
        .background(canvas.bg.ignoresSafeArea())
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
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.sourceName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(canvas.textPrimary)
                            Spacer()
                            Text("\(section.matches.count) match\(section.matches.count == 1 ? "" : "es")")
                                .font(.footnote)
                                .foregroundStyle(canvas.textSecondary)
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(section.matches) { match in
                                    Button {
                                        migrationTarget = (match, section.source)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            CoverImage(url: match.coverURL)
                                                .frame(width: 100, height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            Text(match.title)
                                                .font(.footnote)
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
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching \(pendingCount) more…")
                            .font(.footnote)
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
                .font(.title2.weight(.bold))
                .foregroundStyle(canvas.textPrimary)
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
        searchGeneration += 1
        let generation = searchGeneration
        Task { await runParallelSearch(query: trimmed, generation: generation) }
    }

    private func runParallelSearch(query: String, generation: Int) async {
        let oldSourceId = oldManga.sourceId
        let jsSources = ExtensionManager.shared.installed.filter { $0.id != oldSourceId }
        let keiyoushiSources = KeiyoushiJVMHost.isAvailable
            ? KeiyoushiRepository.shared.installedSources
                .filter { KeiyoushiMapping.sourcePrefix + $0.source.id != oldSourceId }
                .map { (id: $0.source.id,
                        name: $0.ext.info.sources.count > 1
                            ? "\($0.source.name) · \($0.source.lang.uppercased())" : $0.source.name) }
            : []
        isSearching = true
        pendingCount = jsSources.count + keiyoushiSources.count

        await withTaskGroup(of: MatchSection?.self) { group in
            for ext in jsSources {
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
                        return MatchSection(id: extId, sourceName: extName, matches: items, source: .js(bridge))
                    }.value
                }
            }
            for source in keiyoushiSources {
                group.addTask { @MainActor in
                    guard let page = try? await KeiyoushiBridge.shared.search(sourceId: source.id, query: query, page: 1)
                    else { return nil }
                    let items = (page.mangas ?? []).map { KeiyoushiMapping.manga(from: $0, sourceId: source.id) }
                    guard !items.isEmpty else { return nil }
                    return MatchSection(id: KeiyoushiMapping.sourcePrefix + source.id, sourceName: source.name,
                                        matches: items, source: .keiyoushi(sourceId: source.id))
                }
            }
            for await result in group {
                guard generation == searchGeneration else { continue }
                pendingCount = max(0, pendingCount - 1)
                if let section = result {
                    sections.append(section)
                }
            }
        }
        if generation == searchGeneration { isSearching = false }
    }

    // MARK: - Migration

    private func performMigration(target: (manga: Manga, source: MatchSource), removeOld: Bool) async {
        isMigrating = true
        let old = oldManga
        let new = target.manga
        do {
            let newChapters: [Chapter]
            switch target.source {
            case .js(let bridge):
                newChapters = await Task.detached(priority: .userInitiated) {
                    bridge.getChapterList(mangaPath: new.path, mangaId: new.id)
                }.value
            case .keiyoushi(let sourceId):
                var seen = Set<String>()
                newChapters = try await KeiyoushiBridge.shared.chapters(sourceId: sourceId, mangaURL: new.path)
                    .map { KeiyoushiMapping.chapter(from: $0, mangaId: new.id, sourceId: sourceId, mangaTitle: new.title) }
                    .filter { seen.insert($0.id).inserted }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try MigrationService.migrate(from: old, to: new, newChapters: newChapters, removeOld: removeOld)
            }.value
            isMigrating = false
            migrationResult = result
        } catch {
            isMigrating = false
            migrationError = error.localizedDescription
        }
    }
}
