import SwiftUI
import Kingfisher
import CryptoKit

// MARK: - UpdateFeedEntry

struct UpdateFeedEntry: Identifiable {
    enum Kind {
        case manga(Manga, Chapter)
        case novel(Novel, NovelChapter)
    }
    let kind: Kind
    let fetchedAt: Date
    var isRead: Bool

    /// For ordering only. Keiyoushi chapters are stored without a number, so read it from "Chapter 101".
    nonisolated var chapterNumber: Double {
        let (number, name): (Double?, String) = switch kind {
        case .manga(_, let c): (c.chapterNumber, c.name)
        case .novel(_, let c): (c.chapterNumber, c.name)
        }
        if let number { return number }
        return name.firstMatch(of: /(?i)ch(?:apter)?\.?\s*(\d+(?:\.\d+)?)/).flatMap { Double($0.1) } ?? 0
    }

    var id: String {
        switch kind {
        case .manga(_, let c): return "manga-\(c.id)"
        case .novel(_, let c): return "novel-\(c.id)"
        }
    }
}

// MARK: - Reader destinations

private struct MangaReaderDest: Identifiable, Hashable {
    let id = UUID()
    let manga: Manga
    let bridge: JSBridge?   // nil for Keiyoushi titles — the reader goes through the embedded JVM
    let chapters: [Chapter]
    let chapterIndex: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct NovelReaderDest: Identifiable, Hashable {
    let id = UUID()
    let novel: Novel
    let bridge: JSBridge
    let chapters: [NovelChapter]
    let chapterIndex: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - UpdatesViewModel

@Observable final class UpdatesViewModel {

    static let shared = UpdatesViewModel()

    /// One row per chapter a refresh found in the last 30 days (v23 `fetchedAt`), newest first — Tachimanga's
    /// feed (S141, Martin). Replaced "every unread chapter of a recently updated title", which listed 481
    /// "new" chapters for a novel he was simply behind on.
    var entries: [UpdateFeedEntry] = []
    var isRefreshing = false

    /// How many titles' chapter-list fetches failed outright during the last `refresh()`, as
    /// opposed to genuinely having nothing new. Reported in the refresh summary banner.
    var failedSourceChecks = 0

    /// Tab badge: new chapters not read yet.
    var totalCount: Int { entries.filter { !$0.isRead }.count }

    func markRead(_ entry: UpdateFeedEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].isRead = true
        switch entry.kind {
        case .manga(let manga, let chapter):
            let mangaId = manga.id, ids = [chapter.id]
            Task.detached { try? ChapterQueries.setReadBatch(chapterIds: ids, mangaId: mangaId, isRead: true) }
        case .novel(let novel, let chapter):
            let novelId = novel.id, ids = [chapter.id]
            Task.detached { try? NovelQueries.markReadBatch(chapterIds: ids, novelId: novelId) }
        }
    }

    func loadFromDB() async {
        entries = await Task.detached(priority: .userInitiated) {
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            let mangas = Dictionary(((try? MangaQueries.fetchLibrary()) ?? []).map { ($0.id, $0) },
                                    uniquingKeysWith: { a, _ in a })
            let novels = Dictionary(((try? NovelQueries.fetchLibrary()) ?? []).map { ($0.id, $0) },
                                    uniquingKeysWith: { a, _ in a })
            var out: [UpdateFeedEntry] = []
            for (ch, at) in (try? ChapterQueries.fetchRecentlyFetched(since: cutoff)) ?? [] {
                guard let m = mangas[ch.mangaId] else { continue }
                out.append(UpdateFeedEntry(kind: .manga(m, ch), fetchedAt: at, isRead: ch.isRead))
            }
            for (ch, at) in (try? NovelQueries.fetchRecentlyFetched(since: cutoff)) ?? [] {
                guard let n = novels[ch.novelId] else { continue }
                out.append(UpdateFeedEntry(kind: .novel(n, ch), fetchedAt: at, isRead: ch.isRead))
            }
            // Newest first; within one refresh, highest chapter first (a plain sort shuffled 100 above 101).
            return out.sorted { a, b in
                a.fetchedAt != b.fetchedAt ? a.fetchedAt > b.fetchedAt : a.chapterNumber > b.chapterNumber
            }
        }.value
    }

    // MARK: Refresh (S142: Keiyoushi titles + Tachimanga-style summary, #174)

    /// Titles checked so far / titles to check in the running refresh — the progress row in Updates.
    var progressDone = 0
    var progressTotal = 0
    /// The last refresh's per-title results (Completed / Failed), shown in the Updates Summary sheet.
    var lastRun: UpdateRunSummary?

    /// Keiyoushi checks run in the embedded JVM (an interpreter on the phone), so they get a small pool;
    /// JS plugins are cheap and already serialised per source by the bridge lock.
    private static let keiyoushiConcurrency = 3
    private static let pluginConcurrency = 6

    /// Returns the number of newly-discovered unread chapters (manga + novel) found this refresh.
    /// `only` re-checks just those titles (the summary's "Retry failed"). The background task passes
    /// `includeKeiyoushi: false` — starting the JVM inside a ~30 s BGAppRefreshTask isn't worth it.
    @discardableResult
    func refresh(only: [UpdateTarget]? = nil, includeKeiyoushi: Bool = true) async -> Int {
        guard !isRefreshing else { return 0 }
        isRefreshing = true
        progressDone = 0
        progressTotal = 0

        let oldIds = Set(entries.map(\.id))
        let settings = RefreshSettings(
            skipNotStarted: AppSettings.shared.skipUpdateNotStarted,
            skipCompleted: AppSettings.shared.skipUpdateCompleted,
            skipWithUnread: AppSettings.shared.skipUpdateWithUnread,
            excludedIds: Set(AppSettings.shared.excludedCategoryIds),
            notify: AppSettings.shared.sendUpdateNotifications,
            autoDownload: AppSettings.shared.backgroundDownloadEnabled)

        // The skip rules read the DB per title — do that off the main thread, once, before counting.
        let targets: [UpdateTarget]
        if let only {
            targets = only
        } else {
            targets = await Task.detached(priority: .userInitiated) {
                Self.eligibleTargets(settings)
            }.value
        }
        let keiyoushi = includeKeiyoushi ? targets.filter(\.isKeiyoushi) : []
        let plugins = targets.filter { !$0.isKeiyoushi }
        progressTotal = keiyoushi.count + plugins.count

        var results: [UpdateRunSummary.Result] = []
        async let pluginResults = runBounded(plugins, limit: Self.pluginConcurrency) { target in
            await self.check(target, settings: settings)
        }
        async let keiyoushiResults = runKeiyoushi(keiyoushi, settings: settings)
        results = await pluginResults + keiyoushiResults

        // A retry replaces just the retried rows of the previous summary.
        if only != nil, var previous = lastRun {
            let retried = Set(results.map(\.id))
            previous.results.removeAll { retried.contains($0.id) }
            previous.results += results
            previous.date = Date()
            lastRun = previous
        } else {
            lastRun = UpdateRunSummary(date: Date(), results: results)
        }
        failedSourceChecks = results.filter(\.isFailure).count

        await loadFromDB()
        isRefreshing = false

        return Set(entries.map(\.id)).subtracting(oldIds).count
    }

    /// Keiyoushi titles, grouped by extension: the first call to an extension loads (and may convert) its APK,
    /// so each extension's first title goes alone; the rest share the small pool.
    private func runKeiyoushi(_ targets: [UpdateTarget], settings: RefreshSettings) async -> [UpdateRunSummary.Result] {
        guard !targets.isEmpty else { return [] }
        var firstPerExtension: [UpdateTarget] = []
        var rest: [UpdateTarget] = []
        var seen = Set<String>()
        for target in targets {
            let pkg = KeiyoushiRepository.shared
                .installedExtension(forSourceId: KeiyoushiMapping.mihonSourceId(target.sourceId))?.id ?? target.sourceId
            if seen.insert(pkg).inserted { firstPerExtension.append(target) } else { rest.append(target) }
        }
        var results: [UpdateRunSummary.Result] = []
        for target in firstPerExtension {
            results.append(await check(target, settings: settings))
        }
        results += await runBounded(rest, limit: Self.keiyoushiConcurrency) { target in
            await self.check(target, settings: settings)
        }
        return results
    }

    /// Runs `body` over `items` with at most `limit` in flight, counting progress as each finishes.
    private func runBounded(_ items: [UpdateTarget], limit: Int,
                            _ body: @escaping (UpdateTarget) async -> UpdateRunSummary.Result) async
        -> [UpdateRunSummary.Result] {
        var results: [UpdateRunSummary.Result] = []
        var iterator = items.makeIterator()
        await withTaskGroup(of: UpdateRunSummary.Result.self) { group in
            for _ in 0..<limit {
                guard let next = iterator.next() else { break }
                group.addTask { await body(next) }
            }
            for await result in group {
                results.append(result)
                if let next = iterator.next() { group.addTask { await body(next) } }
            }
        }
        return results
    }

    /// Library titles that pass the user's skip settings (Updates → filter button).
    nonisolated private static func eligibleTargets(_ s: RefreshSettings) -> [UpdateTarget] {
        var out: [UpdateTarget] = []
        for manga in (try? MangaQueries.fetchLibrary()) ?? [] {
            if s.skipNotStarted && manga.lastReadAt == nil { continue }
            if s.skipCompleted && manga.status == .completed { continue }
            if s.skipWithUnread, !((try? ChapterQueries.fetchUnread(mangaId: manga.id)) ?? []).isEmpty { continue }
            if !s.excludedIds.isEmpty,
               ((try? CategoryQueries.categoriesForManga(mangaId: manga.id)) ?? []).contains(where: { s.excludedIds.contains($0.id) }) {
                continue
            }
            out.append(.manga(manga))
        }
        for novel in (try? NovelQueries.fetchLibrary()) ?? [] {
            if s.skipNotStarted && novel.lastReadAt == nil { continue }
            if s.skipCompleted && novel.status.lowercased().contains("completed") { continue }
            if s.skipWithUnread,
               ((try? NovelQueries.fetchChapters(novelId: novel.id)) ?? []).contains(where: { !$0.isRead }) {
                continue
            }
            if !s.excludedIds.isEmpty,
               ((try? CategoryQueries.categoriesForNovel(novelId: novel.id)) ?? []).contains(where: { s.excludedIds.contains($0.id) }) {
                continue
            }
            out.append(.novel(novel))
        }
        return out
    }

    private func check(_ target: UpdateTarget, settings: RefreshSettings) async -> UpdateRunSummary.Result {
        let outcome: UpdateRunSummary.Outcome
        switch target {
        case .manga(let manga) where target.isKeiyoushi:
            outcome = await checkKeiyoushiUpdates(for: manga, settings: settings)
        case .manga(let manga):
            outcome = await checkUpdates(for: manga, settings: settings)
        case .novel(let novel):
            outcome = await checkNovelUpdates(for: novel, settings: settings)
        }
        progressDone += 1
        return UpdateRunSummary.Result(target: target, outcome: outcome)
    }

    /// Writes chapters a refresh found. A title with no saved chapters yet (never opened) — or whose every
    /// chapter id changed at once (a source that moved its URLs) — is a baseline, not news: its chapters are
    /// saved but kept out of the feed, which would otherwise list hundreds of "new" chapters.
    nonisolated private static func saveNew(_ newChapters: [Chapter], remoteCount: Int, localCount: Int, manga: Manga) {
        try? ChapterQueries.insertMangaAndChapters(manga: manga, chapters: newChapters)
        try? MangaQueries.touchLastUpdated(mangaId: manga.id)
        guard localCount > 0, newChapters.count < remoteCount else { return }
        try? ChapterQueries.markFetched(ids: newChapters.map(\.id))
    }

    private func notify(title: String, count: Int, id: String, type: String, settings: RefreshSettings) {
        guard settings.notify, count > 0 else { return }
        NotificationManager.shared.scheduleChapterNotification(mangaTitle: title, newCount: count,
                                                               mediaId: id, mediaType: type)
    }

    /// Keiyoushi (Mihon) title: chapter list from the embedded JVM, same mapping as MangaDetailView.
    private func checkKeiyoushiUpdates(for manga: Manga, settings: RefreshSettings) async -> UpdateRunSummary.Outcome {
        let sourceId = KeiyoushiMapping.mihonSourceId(manga.sourceId)
        guard KeiyoushiRepository.shared.installedExtension(forSourceId: sourceId) != nil else {
            return .failed("Extension not installed")
        }
        guard KeiyoushiJVMHost.isAvailable else { return .failed("Keiyoushi needs the iPhone build") }

        let items: [KeiyoushiChapter]
        do {
            items = try await KeiyoushiBridge.shared.chapters(sourceId: sourceId, mangaURL: manga.path)
        } catch {
            let message = error.localizedDescription
            return .failed(message.hasPrefix("CLOUDFLARE:") ? "Cloudflare — open the title once to verify" : message)
        }
        let mangaId = manga.id
        let mangaTitle = manga.title
        var seen = Set<String>()
        let remote = items.map { KeiyoushiMapping.chapter(from: $0, mangaId: mangaId, sourceId: sourceId, mangaTitle: mangaTitle) }
            .filter { seen.insert($0.id).inserted }
        guard !remote.isEmpty else { return .failed("The source returned no chapters") }

        let newChapters = await Task.detached(priority: .utility) {
            let local = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
            let localIds = Set(local.map(\.id))
            let new = remote.filter { !localIds.contains($0.id) }
            try? ChapterQueries.refreshPaths(remote.filter { localIds.contains($0.id) })
            if !new.isEmpty { Self.saveNew(new, remoteCount: remote.count, localCount: local.count, manga: manga) }
            return new
        }.value
        notify(title: manga.title, count: newChapters.count, id: mangaId, type: "manga", settings: settings)
        return .checked(newChapters: newChapters.count)
    }

    private func checkUpdates(for manga: Manga, settings: RefreshSettings) async -> UpdateRunSummary.Outcome {
        let sourceId  = manga.sourceId
        let mangaPath = manga.path
        let mangaId   = manga.id

        guard let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) else {
            return .failed("Extension not installed")
        }

        let bridge = await ExtensionManager.shared.loadBridge(for: ext)
        let remoteChapters = await Task.detached(priority: .background) {
            return bridge?.getChapterList(mangaPath: mangaPath, mangaId: mangaId) ?? []
        }.value

        // A plugin swallows its own JS exceptions and returns an empty list on failure; a library title always
        // has at least one chapter upstream, so empty means the fetch failed (Cloudflare, rate limit, network).
        guard !remoteChapters.isEmpty else { return .failed("The source returned no chapters") }

        let newChapters = await Task.detached(priority: .utility) {
            let local = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
            let localIds = Set(local.map(\.id))
            let new = remoteChapters.filter { !localIds.contains($0.id) }
            if !new.isEmpty {
                Self.saveNew(new, remoteCount: remoteChapters.count, localCount: local.count, manga: manga)
            }
            return new
        }.value

        if settings.autoDownload, let bridge {
            for chapter in newChapters {
                DownloadManager.shared.enqueue(chapter, manga: manga, bridge: bridge)
            }
        }
        notify(title: manga.title, count: newChapters.count, id: mangaId, type: "manga", settings: settings)
        return .checked(newChapters: newChapters.count)
    }

    private func checkNovelUpdates(for novel: Novel, settings: RefreshSettings) async -> UpdateRunSummary.Outcome {
        let sourceId  = novel.sourceId
        let novelPath = novel.path
        let novelId   = novel.id

        guard let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) else {
            return .failed("Extension not installed")
        }

        let bridge = await ExtensionManager.shared.loadBridge(for: ext)
        let source = await Task.detached(priority: .background) {
            bridge?.parseNovel(path: novelPath)
        }.value

        // Same reasoning as the manga path: no chapters back for a library title means the fetch failed.
        guard let source, !source.chapters.isEmpty else { return .failed("The source returned no chapters") }

        let localChapters = await Task.detached(priority: .utility) {
            (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
        }.value
        let localPaths = Set(localChapters.map { $0.path })

        let newChapters: [NovelChapter] = source.chapters
            .filter { !localPaths.contains($0.path) }
            .map { ch in
                NovelChapter(
                    id: NovelChapter.pathId(novelId: novelId, path: ch.path),
                    novelId: novelId,
                    path: ch.path,
                    name: ch.name,
                    chapterNumber: ch.chapterNumber,
                    isRead: false,
                    readAt: nil,
                    releaseTime: ch.releaseTime,
                    readingSeconds: 0
                )
            }

        guard !newChapters.isEmpty else { return .checked(newChapters: 0) }

        // Same baseline rule as manga (`saveNew`): first sight of a title, or every path changed at once.
        let isNews = !localChapters.isEmpty && newChapters.count < source.chapters.count
        await Task.detached(priority: .utility) {
            try? NovelQueries.insertAllIgnoringConflicts(newChapters)
            try? NovelQueries.touchLastUpdated(novelId: novelId)
            if isNews { try? NovelQueries.markFetched(ids: newChapters.map(\.id)) }
        }.value

        notify(title: novel.title, count: newChapters.count, id: novelId, type: "novel", settings: settings)
        return .checked(newChapters: newChapters.count)
    }
}

// MARK: - Refresh model

/// One library title a refresh checks.
enum UpdateTarget: Identifiable {
    case manga(Manga)
    case novel(Novel)

    var id: String {
        switch self {
        case .manga(let m): "manga-\(m.id)"
        case .novel(let n): "novel-\(n.id)"
        }
    }
    var sourceId: String {
        switch self {
        case .manga(let m): m.sourceId
        case .novel(let n): n.sourceId
        }
    }
    var title: String {
        switch self {
        case .manga(let m): m.title
        case .novel(let n): n.title
        }
    }
    var coverURL: URL? {
        switch self {
        case .manga(let m): m.coverURL
        case .novel(let n): n.coverURL
        }
    }
    var customCoverPath: String? {
        switch self {
        case .manga(let m): m.resolvedCustomCoverPath
        case .novel(let n): n.resolvedCustomCoverPath
        }
    }
    var isKeiyoushi: Bool { KeiyoushiMapping.isKeiyoushiSourceId(sourceId) }
}

/// What the last refresh did per title — Tachimanga's "Updates Summary" (Completed / Failed).
struct UpdateRunSummary {
    enum Outcome {
        case checked(newChapters: Int)
        case failed(String)
    }
    struct Result: Identifiable {
        let target: UpdateTarget
        let outcome: Outcome
        var id: String { target.id }
        var isFailure: Bool { if case .failed = outcome { true } else { false } }
    }
    var date: Date
    var results: [Result]

    var completed: [Result] {
        results.filter { !$0.isFailure }.sorted { a, b in
            let (na, nb) = (a.newCount, b.newCount)
            return na != nb ? na > nb : a.target.title.localizedCaseInsensitiveCompare(b.target.title) == .orderedAscending
        }
    }
    var failed: [Result] {
        results.filter(\.isFailure).sorted { $0.target.title.localizedCaseInsensitiveCompare($1.target.title) == .orderedAscending }
    }
}

extension UpdateRunSummary.Result {
    var newCount: Int { if case .checked(let n) = outcome { n } else { 0 } }
}

private struct RefreshSettings: Sendable {
    let skipNotStarted: Bool
    let skipCompleted: Bool
    let skipWithUnread: Bool
    let excludedIds: Set<String>
    let notify: Bool
    let autoDownload: Bool
}

private struct UpdateFeedGroup: Identifiable {
    let label: String
    var items: [UpdateFeedEntry]
    var id: String { label }
}

// MARK: - UpdatesView

struct UpdatesView: View {
    @Environment(\.yomiCanvas) private var canvas
    @State private var vm = UpdatesViewModel.shared

    @State private var mangaReaderDest: MangaReaderDest? = nil
    @State private var novelReaderDest: NovelReaderDest? = nil
    @State private var isLoadingReader = false
    @State private var refreshSummary: String? = nil
    @State private var showSummary = false
    private var hasContent: Bool { !vm.entries.isEmpty || vm.lastRun != nil }

    private var groupedFeed: [UpdateFeedGroup] {
        var buckets: [String: [UpdateFeedEntry]] = [:]
        for entry in vm.entries {
            buckets[Notation.dateGroupLabel(for: entry.fetchedAt), default: []].append(entry)
        }
        return Notation.dateGroupOrder.compactMap { key in
            buckets[key].map { UpdateFeedGroup(label: key, items: $0) }
        }
    }

    var body: some View {
        Group {
            if !hasContent && !vm.isRefreshing {
                YomiEmptyState(
                    systemImage: "bell.badge",
                    title: "No updates yet",
                    message: "Add titles to your library and refresh to check for new chapters."
                )
            } else {
                // S141 calm pass: same plain list as History; swipe → Mark Read.
                List {
                    statusRow
                    ForEach(groupedFeed) { group in
                        Section {
                            sectionHeader(group.label)
                            ForEach(group.items) { item in
                                itemRow(item)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .yomiListCanvas()
                .refreshable { await runRefresh() }
            }
        }
        .navigationTitle("Updates")
        .overlay(alignment: .top) {
            if let summary = refreshSummary {
                Button { showSummary = true } label: {
                    Text(summary)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(canvas.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: refreshSummary)
        .sheet(isPresented: $showSummary) {
            UpdatesSummaryView(vm: vm)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isRefreshing || isLoadingReader {
                    ProgressView()
                } else {
                    Button {
                        Task { await runRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    UpdatesSettingsView()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
        }
        .task { await vm.loadFromDB() }
        .navigationDestination(item: $mangaReaderDest) { dest in
            ChapterReaderView(manga: dest.manga, bridge: dest.bridge,
                              chapters: dest.chapters, chapterIndex: dest.chapterIndex)
        }
        .navigationDestination(item: $novelReaderDest) { dest in
            TextReaderView(novel: dest.novel, bridge: dest.bridge,
                           chapters: dest.chapters, startIndex: dest.chapterIndex)
        }
    }

    // MARK: - Status row

    /// While a refresh runs: "Checking 12 of 48" + a bar (Keiyoushi titles go through the JVM and take a while).
    /// Afterwards: "Checked 48 titles · 19:20 · 2 failed" → the Updates Summary.
    @ViewBuilder
    private var statusRow: some View {
        if vm.isRefreshing {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.progressTotal == 0 ? "Preparing…" : "Checking \(vm.progressDone) of \(vm.progressTotal)")
                    .font(.subheadline)
                    .foregroundStyle(canvas.textSecondary)
                    .monospacedDigit()
                ProgressView(value: Double(vm.progressDone), total: Double(max(vm.progressTotal, 1)))
                    .tint(canvas.textSecondary)
            }
            .padding(.vertical, 4)
            .statusRowStyle()
        } else if let run = vm.lastRun {
            Button { showSummary = true } label: {
                HStack(spacing: 6) {
                    Text(Self.statusLine(run))
                        .font(.subheadline)
                        .foregroundStyle(canvas.textSecondary)
                    if !run.failed.isEmpty {
                        Text("· \(run.failed.count) failed")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(canvas.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .statusRowStyle()
        }
    }

    private static func statusLine(_ run: UpdateRunSummary) -> String {
        let n = run.results.count
        return "Checked \(n) title\(n == 1 ? "" : "s") · \(Notation.time(run.date, use24Hour: AppSettings.shared.use24HourClock))"
    }

    // MARK: - Section header

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.title2.bold())
            .foregroundStyle(canvas.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 24, leading: YomiTokens.Layout.screenMargin,
                                      bottom: 4, trailing: YomiTokens.Layout.screenMargin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: - Row

    /// Tap = read that chapter (S141, Martin: Tachimanga's feed takes you straight in). Swipe → Mark Read.
    @ViewBuilder
    private func itemRow(_ entry: UpdateFeedEntry) -> some View {
        Group {
            switch entry.kind {
            case .manga(let manga, let chapter):
                Button {
                    guard !isLoadingReader else { return }
                    Task { await loadMangaReader(manga: manga, chapter: chapter) }
                } label: {
                    UpdateRow(title: manga.title, coverURL: manga.coverURL,
                              customCoverPath: manga.resolvedCustomCoverPath,
                              chapter: Notation.chapterTitle(chapter.name, number: chapter.chapterNumber),
                              isRead: entry.isRead)
                }
            case .novel(let novel, let chapter):
                Button {
                    guard !isLoadingReader else { return }
                    Task { await loadNovelReader(novel: novel, chapter: chapter) }
                } label: {
                    UpdateRow(title: novel.title, coverURL: novel.coverURL,
                              customCoverPath: novel.resolvedCustomCoverPath,
                              chapter: Notation.chapterTitle(chapter.name, number: chapter.chapterNumber),
                              isRead: entry.isRead)
                }
            }
        }
        .buttonStyle(.plain)
        // On the row itself — inside the Button's label the List ignored them and drew separators (S141).
        .listRowInsets(EdgeInsets(top: 6, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 6, trailing: YomiTokens.Layout.screenMargin))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !entry.isRead {
                Button { vm.markRead(entry) } label: {
                    Label("Mark Read", systemImage: "checkmark")
                }
                .tint(.gray)
            }
        }
    }

    // MARK: - Refresh summary

    private func runRefresh() async {
        let newCount = await vm.refresh()
        let failed = vm.failedSourceChecks
        // "No new chapters" used to be shown identically whether nothing was new or every source
        // failed — always say when a check couldn't actually complete. Tapping it opens the summary.
        var summary = newCount == 0
            ? "No new chapters"
            : "\(newCount) new chapter\(newCount == 1 ? "" : "s") found"
        if failed > 0 {
            summary += " · \(failed) failed"
        }
        refreshSummary = summary
        try? await Task.sleep(for: .seconds(3))
        if refreshSummary == summary { refreshSummary = nil }
    }

    // MARK: - Reader loading

    private func loadMangaReader(manga: Manga, chapter: Chapter) async {
        isLoadingReader = true
        defer { isLoadingReader = false }

        let sourceId = manga.sourceId
        let mangaId  = manga.id

        let (bridge, allChapters) = await Task.detached(priority: .userInitiated) {
            let installed  = await MainActor.run { ExtensionManager.shared.installed }
            let bridgeFn   = await MainActor.run { ExtensionManager.shared.bridge(for:) }
            let ext        = installed.first(where: { $0.id == sourceId })
            let br         = ext.flatMap { bridgeFn($0) }
            let chapters   = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
            return (br, chapters)
        }.value

        guard bridge != nil || KeiyoushiMapping.isKeiyoushiSourceId(sourceId) else { return }
        let sorted = allChapters.sorted { ($0.chapterNumber ?? 0) < ($1.chapterNumber ?? 0) }
        let index  = sorted.firstIndex(where: { $0.id == chapter.id }) ?? 0
        mangaReaderDest = MangaReaderDest(manga: manga, bridge: bridge, chapters: sorted, chapterIndex: index)
    }

    private func loadNovelReader(novel: Novel, chapter: NovelChapter) async {
        isLoadingReader = true
        defer { isLoadingReader = false }

        let sourceId = novel.sourceId
        let novelId  = novel.id

        let (bridge, allChapters) = await Task.detached(priority: .userInitiated) {
            let installed  = await MainActor.run { ExtensionManager.shared.installed }
            let bridgeFn   = await MainActor.run { ExtensionManager.shared.bridge(for:) }
            let ext        = installed.first(where: { $0.id == sourceId })
            let br         = ext.flatMap { bridgeFn($0) }
            let chapters   = (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
            return (br, chapters)
        }.value

        guard let bridge else { return }
        let index = allChapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
        novelReaderDest = NovelReaderDest(novel: novel, bridge: bridge, chapters: allChapters, chapterIndex: index)
    }
}

private extension View {
    func statusRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: YomiTokens.Layout.screenMargin,
                                 bottom: 0, trailing: YomiTokens.Layout.screenMargin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Updates Summary

/// Tachimanga's "Updates Summary": every title the last refresh checked, Failed (with why, and Retry) first,
/// then Completed (new-chapter counts first). Same calm rows as Updates — no separators.
private struct UpdatesSummaryView: View {
    let vm: UpdatesViewModel
    @Environment(\.yomiCanvas) private var canvas
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let run = vm.lastRun {
                    List {
                        if vm.isRefreshing {
                            Text("Checking \(vm.progressDone) of \(vm.progressTotal)")
                                .font(.subheadline)
                                .foregroundStyle(canvas.textSecondary)
                                .monospacedDigit()
                                .summaryRowStyle()
                        }
                        if !run.failed.isEmpty {
                            header("Failed", count: run.failed.count)
                            ForEach(run.failed) { row($0) }
                        }
                        if !run.completed.isEmpty {
                            header("Completed", count: run.completed.count)
                            ForEach(run.completed) { row($0) }
                        }
                    }
                    .listStyle(.plain)
                    .yomiListCanvas()
                } else {
                    YomiEmptyState(systemImage: "bell.badge", title: "No refresh yet",
                                   message: "Pull down in Updates to check your library.")
                }
            }
            .navigationTitle("Updates Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if let failed = vm.lastRun?.failed, !failed.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Retry Failed") {
                            Task { await vm.refresh(only: failed.map(\.target)) }
                        }
                        .disabled(vm.isRefreshing)
                    }
                }
            }
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)")
            .font(.title3.bold())
            .foregroundStyle(canvas.textPrimary)
            .padding(.top, 16)
            .summaryRowStyle()
    }

    private func row(_ result: UpdateRunSummary.Result) -> some View {
        HStack(spacing: 14) {
            Group {
                if let path = result.target.customCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage).resizable().aspectRatio(2 / 3, contentMode: .fill).coverAspectSized()
                } else {
                    CoverImage(url: result.target.coverURL)
                }
            }
            .frame(width: 36)
            .clipShape(RoundedRectangle(cornerRadius: YomiTokens.Radius.thumb))
            .coverHairline(cornerRadius: YomiTokens.Radius.thumb)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.target.title)
                    .font(.body)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Group {
                    switch result.outcome {
                    case .failed(let why):
                        Text(why).foregroundStyle(.red)
                    case .checked(let n):
                        Text(n == 0 ? "No new chapters" : "\(n) new chapter\(n == 1 ? "" : "s")")
                            .foregroundStyle(canvas.textSecondary)
                    }
                }
                .font(.subheadline)
                .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .summaryRowStyle()
    }
}

private extension View {
    func summaryRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: YomiTokens.Layout.screenMargin,
                                 bottom: 6, trailing: YomiTokens.Layout.screenMargin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - UpdateRow

/// Cover, title, "Chapter 28" — dimmed once read, like Tachimanga. No separators (Martin, S141).
private struct UpdateRow: View {
    let title: String
    let coverURL: URL?
    let customCoverPath: String?
    let chapter: String
    let isRead: Bool

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let path = customCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .coverAspectSized()
                } else {
                    CoverImage(url: coverURL)
                }
            }
            .frame(width: 44)
            .clipShape(RoundedRectangle(cornerRadius: YomiTokens.Radius.thumb))
            .coverHairline(cornerRadius: YomiTokens.Radius.thumb)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Text(chapter)
                    .font(.subheadline)
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .opacity(isRead ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { UpdatesView() }
}
