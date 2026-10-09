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

    /// What kind of source an id is — shown next to the name when two sources share one (Asura Scans as a Keiyoushi
    /// extension and as a Yomi plugin, S148).
    static func kindLabel(_ sourceId: String) -> String {
        if KeiyoushiMapping.isKeiyoushiSourceId(sourceId) { return "Keiyoushi" }
        if SuwayomiService.isSuwayomiSourceId(sourceId) { return "Suwayomi" }
        return "Plugin"
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
// Browse's Migrate tab. S148 (Martin): migrate by SOURCE — sources with title counts, missing sources first →
// a source's titles → pick some or all → choose where to move them → review → migrate together (Mihon's mass
// migration, Tachimanga's Bulk Migrate). No delete here: migrated titles only leave the Library.

struct MigrateView: View {
    /// Shown as Browse's Migrate tab (Browse owns the title).
    var embedded = false

    struct SourceGroup: Identifiable {
        let id: String
        let name: String
        let titles: [Manga]
        let isMissing: Bool
    }

    @Environment(\.yomiCanvas) private var canvas
    @State private var groups: [SourceGroup] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                YomiEmptyState(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "Nothing to migrate",
                    message: "Add manga to your library first — Migrate moves titles to a different source."
                )
            } else {
                CalmList {
                    let missing = groups.filter(\.isMissing)
                    if !missing.isEmpty {
                        Section {
                            ForEach(missing) { row($0) }
                        } header: { CalmSectionHeader("Source missing") } footer: {
                            Text("These sources aren't on this iPhone. Move their titles to a source you have.")
                                .font(.footnote)
                                .foregroundStyle(canvas.textSecondary)
                        }
                    }
                    Section {
                        ForEach(groups.filter { !$0.isMissing }) { row($0) }
                    } header: {
                        if !missing.isEmpty { CalmSectionHeader("Sources") }
                    }
                }
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(embedded ? "Browse" : "Migrate")
        .navigationBarTitleDisplayMode(.inline)
        // Every appearance: titles migrated on a pushed screen have left their source by the time we're back.
        .onAppear { Task { await load() } }
    }

    private func row(_ group: SourceGroup) -> some View {
        NavigationLink {
            MigrateTitlesView(sourceId: group.id, sourceName: group.name)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Text("\(group.titles.count) title\(group.titles.count == 1 ? "" : "s")"
                     + (groups.filter { $0.name == group.name }.count > 1 ? " · \(SourceStatus.kindLabel(group.id))" : ""))
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func load() async {
        let library = (try? await Task.detached(priority: .userInitiated) { try MangaQueries.fetchLibrary() }.value) ?? []
        let bySource = Dictionary(grouping: library.filter { !$0.isLocal }, by: \.sourceId)
        groups = bySource.map { id, titles in
            SourceGroup(id: id, name: SourceStatus.sourceName(id), titles: titles,
                        isMissing: !SourceStatus.isInstalled(titles[0]))
        }
        .sorted {
            $0.titles.count != $1.titles.count ? $0.titles.count > $1.titles.count
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        isLoading = false
    }
}

// MARK: - MigrateTitlesView

/// One source's library titles; pick some or all, then "Migrate".
struct MigrateTitlesView: View {
    let sourceId: String
    let sourceName: String

    @Environment(\.yomiCanvas) private var canvas
    @State private var titles: [Manga] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var showFlow = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if titles.isEmpty {
                YomiEmptyState(systemImage: "checkmark.circle", title: "All moved",
                               message: "No titles from \(sourceName) are left in your library.")
            } else {
                CalmList {
                    ForEach(titles) { manga in
                        Button { toggle(manga.id) } label: { row(manga) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(selected.isEmpty ? sourceName : "\(selected.count) selected")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !titles.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    let all = selected.count == titles.count
                    Button(all ? "Deselect All" : "Select All") {
                        selected = all ? [] : Set(titles.map(\.id))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                Button {
                    showFlow = true
                } label: {
                    Text("Migrate \(selected.count) Title\(selected.count == 1 ? "" : "s")")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showFlow, onDismiss: { Task { await load() } }) {
            MigrationFlowSheet(
                sourceId: sourceId,
                sourceName: sourceName,
                titles: titles.filter { selected.contains($0.id) }
            )
        }
        .task { await load() }
    }

    private func row(_ manga: Manga) -> some View {
        let isOn = selected.contains(manga.id)
        return HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? Color.accentColor : canvas.textSecondary)
            CoverImage(url: manga.coverURL)
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(manga.title)
                .foregroundStyle(canvas.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func load() async {
        let id = sourceId
        let library = (try? await Task.detached(priority: .userInitiated) { try MangaQueries.fetchLibrary() }.value) ?? []
        titles = library.filter { $0.sourceId == id }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        selected.formIntersection(titles.map(\.id))
        isLoading = false
    }
}

// MARK: - MigrationFlowSheet

/// Target choice → review → result, in a sheet: Done (or a swipe down) closes the whole flow at once.
struct MigrationFlowSheet: View {
    let sourceId: String
    let sourceName: String
    let titles: [Manga]

    @Environment(\.dismiss) private var dismiss
    @State private var run: MassMigration?

    var body: some View {
        NavigationStack {
            MigrateTargetView(sourceId: sourceId, sourceName: sourceName, titles: titles, run: $run,
                              close: { dismiss() })
        }
        .onDisappear { run?.cancel() }
    }
}

// MARK: - MigrateTargetView

struct MigrateTargetView: View {
    let sourceId: String
    let sourceName: String
    let titles: [Manga]
    @Binding var run: MassMigration?
    /// Closes the whole sheet (a pushed screen's `dismiss` would only pop itself).
    let close: () -> Void

    nonisolated static let orderKey = "migrationTargetOrder"

    @Environment(\.yomiCanvas) private var canvas
    @State private var available: [MigrationTarget] = []
    @State private var order: [String] = []
    @State private var mostChapters = false
    @State private var options = MigrationService.Options()
    @State private var isLoading = true
    @State private var showReview = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if available.isEmpty {
                YomiEmptyState(systemImage: "puzzlepiece.extension", title: "No other sources",
                               message: "Add an extension in Browse → Extensions, then come back.")
            } else {
                CalmList {
                    Section {
                        ForEach(available) { target in
                            Button { toggle(target.id) } label: { targetRow(target) }
                                .buttonStyle(.plain)
                        }
                    } header: { CalmSectionHeader("Search on") } footer: {
                        Text(order.count > 1 && !mostChapters
                             ? "Searched in the order you picked them — the first source with a match wins."
                             : "Tap sources in the order you want them searched.")
                            .font(.footnote)
                            .foregroundStyle(canvas.textSecondary)
                    }
                    if order.count > 1 {
                        Section {
                            Toggle("Most chapters", isOn: $mostChapters)
                        } footer: {
                            Text("Search every picked source and keep the match with the most chapters. Slower.")
                                .font(.footnote)
                                .foregroundStyle(canvas.textSecondary)
                        }
                    }
                    Section {
                        Toggle("Read chapters", isOn: $options.chapters)
                        Toggle("Categories", isOn: $options.categories)
                        Toggle("Custom cover", isOn: $options.customCover)
                        Toggle("Notes", isOn: $options.notes)
                    } header: { CalmSectionHeader("Carry over") } footer: {
                        Text("The titles leave the Library from \(sourceName). Nothing is deleted — they stay saved with their chapters and downloads.")
                            .font(.footnote)
                            .foregroundStyle(canvas.textSecondary)
                    }
                }
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle("Migrate \(titles.count) Title\(titles.count == 1 ? "" : "s")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { close() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !available.isEmpty {
                Button {
                    UserDefaults.standard.set(order, forKey: Self.orderKey)
                    let targets = order.compactMap { id in available.first { $0.id == id } }
                    let model = MassMigration(titles: titles, targets: targets, mostChapters: mostChapters,
                                              options: options)
                    run?.cancel()
                    run = model
                    model.start()
                    showReview = true
                } label: {
                    Text("Search").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(order.isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .navigationDestination(isPresented: $showReview) {
            if let run { MigrationReviewView(model: run, sourceName: sourceName, close: close) }
        }
        .task {
            available = await MigrationTarget.available(excluding: sourceId)
            let saved = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
            order = saved.filter { id in available.contains { $0.id == id } }
            isLoading = false
        }
    }

    private func targetRow(_ target: MigrationTarget) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .foregroundStyle(canvas.textPrimary)
                if available.filter({ $0.name == target.name }).count > 1 {
                    Text(SourceStatus.kindLabel(target.id))
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            Spacer()
            if let position = order.firstIndex(of: target.id) {
                Text("\(position + 1)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
            } else {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(canvas.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func toggle(_ id: String) {
        if let i = order.firstIndex(of: id) { order.remove(at: i) } else { order.append(id) }
    }
}

// MARK: - MigrationReviewView

struct MigrationReviewView: View {
    let model: MassMigration
    let sourceName: String
    let close: () -> Void

    @Environment(\.yomiCanvas) private var canvas
    @State private var actionItem: MassMigration.Item?
    @State private var manualItem: MassMigration.Item?
    @State private var confirm = false

    var body: some View {
        Group {
            if let summary = model.summary {
                summaryView(summary)
            } else {
                list
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(model.summary == nil ? "Review" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isMigrating || model.summary != nil)
        .safeAreaInset(edge: .bottom) {
            if model.summary == nil {
                Button { confirm = true } label: {
                    Text(model.readyCount == 0 ? "Migrate" : "Migrate \(model.readyCount) Title\(model.readyCount == 1 ? "" : "s")")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(model.readyCount == 0 || model.isMigrating)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog(
            "Migrate \(model.readyCount) title\(model.readyCount == 1 ? "" : "s")?",
            isPresented: $confirm, titleVisibility: .visible
        ) {
            Button("Migrate") { Task { await model.migrateReady() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.isSearching
                 ? "Titles still searching stay where they are. Moved titles leave the Library from \(sourceName); nothing is deleted."
                 : "They leave the Library from \(sourceName) and move to the matches shown. Nothing is deleted.")
        }
        .confirmationDialog(
            actionItem?.old.title ?? "",
            isPresented: Binding(get: { actionItem != nil }, set: { if !$0 { actionItem = nil } }),
            titleVisibility: .visible
        ) {
            if let item = actionItem {
                Button("Search Manually") { manualItem = item }
                Button(item.skipped ? "Include" : "Skip") { model.toggleSkip(item.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(item: $manualItem) { item in
            MigrateSourcePickerView(oldManga: item.old, targets: model.targets) { match, target in
                try await model.choose(match, on: target, for: item.id)
            }
        }
        .overlay {
            if model.isMigrating {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Migrating \(model.migratedCount + 1) of \(model.readyCount + model.migratedCount)…")
                        .tint(.white).foregroundStyle(.white)
                }
            }
        }
    }

    private var list: some View {
        CalmList {
            Section {
                ForEach(model.items) { item in
                    Button { actionItem = item } label: { row(item) }
                        .buttonStyle(.plain)
                        .disabled(model.isMigrating)
                }
            } header: {
                if model.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching \(model.searchedCount) of \(model.items.count)…")
                            .font(.footnote)
                            .foregroundStyle(canvas.textSecondary)
                    }
                    .textCase(nil)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func row(_ item: MassMigration.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CoverImage(url: item.old.coverURL)
                    .frame(width: 36, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.old.title)
                        .foregroundStyle(canvas.textPrimary)
                        .lineLimit(1)
                    Text(item.oldLatest.map { "Up to \(Notation.chapter($0))" } ?? sourceName)
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(canvas.textSecondary)
                    .frame(width: 36)
                matchView(item)
            }
        }
        .opacity(item.skipped ? 0.45 : 1)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func matchView(_ item: MassMigration.Item) -> some View {
        switch item.state {
        case .waiting, .searching:
            Text("Searching…").font(.footnote).foregroundStyle(canvas.textSecondary)
        case .notFound:
            Text("Not found — tap to search").font(.footnote).foregroundStyle(canvas.textSecondary)
        case .found(let match, let target, let chapters):
            HStack(spacing: 12) {
                CoverImage(url: match.coverURL)
                    .frame(width: 36, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.title)
                        .foregroundStyle(canvas.textPrimary)
                        .lineLimit(1)
                    Text(status(item, target: target, chapters: chapters))
                        .font(.footnote)
                        .foregroundStyle(item.error == nil ? canvas.textSecondary : Color.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private func status(_ item: MassMigration.Item, target: MigrationTarget, chapters: [Chapter]) -> String {
        if let error = item.error { return error }
        if item.migrated { return "Migrated · \(target.name)" }
        if item.skipped { return "Skipped" }
        let latest = chapters.compactMap(\.chapterNumber).max().map { " · up to \(Notation.chapter($0))" } ?? ""
        return "\(target.name) · \(chapters.count) chapter\(chapters.count == 1 ? "" : "s")\(latest)"
    }

    private func summaryView(_ summary: MassMigration.Summary) -> some View {
        let notFound = model.items.filter { if case .notFound = $0.state { return true }; return false }.count
        let left = model.items.count - summary.migrated
        return VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Migrated \(summary.migrated) title\(summary.migrated == 1 ? "" : "s")")
                .font(.title2.weight(.bold))
                .foregroundStyle(canvas.textPrimary)
            Text("\(summary.readChapters) read chapter\(summary.readChapters == 1 ? "" : "s") carried over.")
                .font(.footnote)
                .foregroundStyle(canvas.textSecondary)
            if left > 0 {
                Text("\(left) still in the Library from \(sourceName)\(notFound > 0 ? " (\(notFound) not found)" : "").")
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
            }
            if !summary.failed.isEmpty {
                Text("Failed: \(summary.failed.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("Done") { close() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MigrateSourcePickerView
//
// Search every source (or the given ones) for one title. Two uses: from a title's detail screen ("Find on Another
// Source") it migrates the title itself; from the mass-migration review (`onPick`) it only picks the match.

struct MigrateSourcePickerView: View {
    let oldManga: Manga
    /// Sources to search; nil = every installed source except the title's own.
    var targets: [MigrationTarget]? = nil
    /// Pick mode: called with the chosen match, then the screen closes. Nil = migrate right here.
    var onPick: ((Manga, MigrationTarget) async throws -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas
    @State private var query: String
    @State private var sections: [MatchSection] = []
    @State private var pendingCount = 0
    @State private var isSearching = false
    @State private var searchGeneration = 0

    @State private var chosen: (manga: Manga, target: MigrationTarget)? = nil
    @State private var isWorking = false
    @State private var migrationResult: MigrationService.Result? = nil
    @State private var migrationError: String? = nil

    struct MatchSection: Identifiable {
        let target: MigrationTarget
        let matches: [Manga]
        var id: String { target.id }
    }

    init(oldManga: Manga, targets: [MigrationTarget]? = nil,
         onPick: ((Manga, MigrationTarget) async throws -> Void)? = nil) {
        self.oldManga = oldManga
        self.targets = targets
        self.onPick = onPick
        _query = State(initialValue: oldManga.title)
    }

    var body: some View {
        Group {
            if let result = migrationResult {
                migratedConfirmation(result)
            } else if isSearching && sections.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching \(pendingCount) source\(pendingCount == 1 ? "" : "s")…")
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                YomiEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No matches found",
                    message: "None of your other sources returned a match for \"\(query)\". Try editing the search text below."
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
            onPick == nil ? "Migrate to this source?" : "Use this match?",
            isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
            titleVisibility: .visible
        ) {
            // Capture `target` by value — the auto-dismiss setter clears `chosen` in the same transaction as the tap,
            // so reading it again after a suspension point would race and see nil.
            if let target = chosen {
                Button(onPick == nil ? "Migrate" : "Use This Match") { Task { await confirm(target) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let target = chosen {
                Text(onPick == nil
                     ? "Read chapters, status, and categories carry over to \"\(target.manga.title)\" on \(target.target.name). The old entry leaves the Library; nothing is deleted."
                     : "\"\(target.manga.title)\" on \(target.target.name).")
            }
        }
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView(onPick == nil ? "Migrating…" : "Loading chapters…").tint(.white).foregroundStyle(.white)
                }
            }
        }
        .alert(onPick == nil ? "Migration failed" : "Couldn't use this match",
               isPresented: Binding(get: { migrationError != nil }, set: { if !$0 { migrationError = nil } })) {
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
                            Text(section.target.name)
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
                                        chosen = (match, section.target)
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
                 ? "\(result.readChapters) chapter\(result.readChapters == 1 ? "" : "s") marked read (you had read \(result.oldReadChapters))."
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
        isSearching = true
        let sources: [MigrationTarget]
        if let targets { sources = targets } else { sources = await MigrationTarget.available(excluding: oldManga.sourceId) }
        guard generation == searchGeneration else { return }
        pendingCount = sources.count
        let oldPath = oldManga.path

        await withTaskGroup(of: MatchSection?.self) { group in
            for target in sources {
                group.addTask {
                    let items = await target.search(query).filter { $0.path != oldPath }
                    return items.isEmpty ? nil : MatchSection(target: target, matches: items)
                }
            }
            for await result in group {
                guard generation == searchGeneration else { continue }
                pendingCount = max(0, pendingCount - 1)
                if let section = result { sections.append(section) }
            }
        }
        if generation == searchGeneration { isSearching = false }
    }

    // MARK: - Confirm

    private func confirm(_ choice: (manga: Manga, target: MigrationTarget)) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if let onPick {
                try await onPick(choice.manga, choice.target)
                dismiss()
                return
            }
            let old = oldManga
            let new = choice.manga
            let newChapters = try await choice.target.chapters(for: new)
            migrationResult = try await Task.detached(priority: .userInitiated) {
                try MigrationService.migrate(from: old, to: new, newChapters: newChapters)
            }.value
        } catch {
            migrationError = error.localizedDescription
        }
    }
}
