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
    var chapterNumber: Double {
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

    /// Returns the number of newly-discovered unread chapters (manga + novel) found this refresh.
    @discardableResult
    func refresh() async -> Int {
        guard !isRefreshing else { return 0 }
        isRefreshing = true

        let oldIds = Set(entries.map(\.id))

        let (library, novelLibrary) = await Task.detached(priority: .userInitiated) {
            let manga = (try? MangaQueries.fetchLibrary()) ?? []
            let novels = (try? NovelQueries.fetchLibrary()) ?? []
            return (manga, novels)
        }.value

        // A plugin swallows its own JS exceptions and returns an empty chapter list on failure,
        // which is indistinguishable from "nothing new" at the call site — so each check reports
        // whether its fetch actually failed, and the count is surfaced in the refresh summary.
        var failures = 0
        await withTaskGroup(of: Bool.self) { group in
            for manga in library {
                group.addTask { await self.checkUpdates(for: manga) }
            }
            for novel in novelLibrary {
                group.addTask { await self.checkNovelUpdates(for: novel) }
            }
            for await didFail in group where didFail { failures += 1 }
        }
        failedSourceChecks = failures

        await loadFromDB()
        isRefreshing = false

        return Set(entries.map(\.id)).subtracting(oldIds).count
    }

    /// Returns `true` if the source's chapter-list fetch failed (as opposed to simply finding
    /// nothing new, or the title being skipped by the user's own update-skip settings).
    private func checkUpdates(for manga: Manga) async -> Bool {
        let (skipNotStarted, skipCompleted, skipWithUnread, excludedIds, sendNotifications, autoDownload) =
            await MainActor.run {
                (AppSettings.shared.skipUpdateNotStarted,
                 AppSettings.shared.skipUpdateCompleted,
                 AppSettings.shared.skipUpdateWithUnread,
                 AppSettings.shared.excludedCategoryIds,
                 AppSettings.shared.sendUpdateNotifications,
                 AppSettings.shared.backgroundDownloadEnabled)
            }

        if skipNotStarted && manga.lastReadAt == nil { return false }
        if skipCompleted && manga.status == .completed { return false }
        if skipWithUnread {
            let unread = (try? ChapterQueries.fetchUnread(mangaId: manga.id)) ?? []
            if !unread.isEmpty { return false }
        }
        if !excludedIds.isEmpty {
            let assigned = (try? CategoryQueries.categoriesForManga(mangaId: manga.id)) ?? []
            if assigned.contains(where: { excludedIds.contains($0.id) }) { return false }
        }

        let sourceId  = manga.sourceId
        let mangaPath = manga.path
        let mangaId   = manga.id

        let allInstalled = await MainActor.run { ExtensionManager.shared.installed }
        let ext = allInstalled.first(where: { $0.id == sourceId })
        // Source no longer installed — the check can't run, but that's a user-made state, not a
        // fetch failure, so it isn't reported as one.
        guard let ext else { return false }

        let bridge = await ExtensionManager.shared.loadBridge(for: ext)
        let remoteChapters = await Task.detached(priority: .background) {
            return bridge?.getChapterList(mangaPath: mangaPath, mangaId: mangaId) ?? []
        }.value

        // A library title always has at least one chapter upstream, so an empty list here means
        // the fetch itself failed (Cloudflare block, rate-limit, network error, plugin exception).
        guard !remoteChapters.isEmpty else { return true }

        let localChapters = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        let localIds = Set(localChapters.map { $0.id })
        let newChapters = remoteChapters.filter { !localIds.contains($0.id) }

        guard !newChapters.isEmpty else { return false }

        try? ChapterQueries.insertMangaAndChapters(manga: manga, chapters: newChapters)
        try? MangaQueries.touchLastUpdated(mangaId: mangaId)
        try? ChapterQueries.markFetched(ids: newChapters.map(\.id))

        if autoDownload, let bridge {
            await MainActor.run {
                for chapter in newChapters {
                    DownloadManager.shared.enqueue(chapter, manga: manga, bridge: bridge)
                }
            }
        }

        let title = manga.title
        let count = newChapters.count
        if sendNotifications {
            await MainActor.run {
                NotificationManager.shared.scheduleChapterNotification(
                    mangaTitle: title, newCount: count,
                    mediaId: mangaId, mediaType: "manga"
                )
            }
        }
        return false
    }

    /// Returns `true` if the source's chapter-list fetch failed — see `checkUpdates(for:)`.
    private func checkNovelUpdates(for novel: Novel) async -> Bool {
        let (skipNotStarted, skipCompleted, skipWithUnread, excludedIds, sendNotifications) =
            await MainActor.run {
                (AppSettings.shared.skipUpdateNotStarted,
                 AppSettings.shared.skipUpdateCompleted,
                 AppSettings.shared.skipUpdateWithUnread,
                 AppSettings.shared.excludedCategoryIds,
                 AppSettings.shared.sendUpdateNotifications)
            }

        if skipNotStarted && novel.lastReadAt == nil { return false }
        if skipCompleted && novel.status.lowercased().contains("completed") { return false }
        if skipWithUnread {
            let all    = (try? NovelQueries.fetchChapters(novelId: novel.id)) ?? []
            let unread = all.filter { !$0.isRead }
            if !unread.isEmpty { return false }
        }
        if !excludedIds.isEmpty {
            let assigned = (try? CategoryQueries.categoriesForNovel(novelId: novel.id)) ?? []
            if assigned.contains(where: { excludedIds.contains($0.id) }) { return false }
        }

        let sourceId  = novel.sourceId
        let novelPath = novel.path
        let novelId   = novel.id

        let allInstalled = await MainActor.run { ExtensionManager.shared.installed }
        let ext = allInstalled.first(where: { $0.id == sourceId })
        guard let ext else { return false }

        let bridge = await ExtensionManager.shared.loadBridge(for: ext)
        let source = await Task.detached(priority: .background) {
            bridge?.parseNovel(path: novelPath)
        }.value

        // Same reasoning as the manga path: no chapters back for a library title means the fetch
        // failed, not that the novel genuinely has none.
        guard let source, !source.chapters.isEmpty else { return true }

        let localChapters = (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
        let localPaths = Set(localChapters.map { $0.path })

        let newChapters: [NovelChapter] = source.chapters
            .filter { !localPaths.contains($0.path) }
            .map { ch in
                let hashBytes = SHA256.hash(data: Data((novelId + ch.path).utf8))
                let stableId = hashBytes.prefix(8).map { String(format: "%02x", $0) }.joined()
                return NovelChapter(
                    id: stableId,
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

        guard !newChapters.isEmpty else { return false }

        try? NovelQueries.insertAllIgnoringConflicts(newChapters)
        try? NovelQueries.touchLastUpdated(novelId: novelId)
        try? NovelQueries.markFetched(ids: newChapters.map(\.id))

        let title = novel.title
        let count = newChapters.count
        if sendNotifications {
            await MainActor.run {
                NotificationManager.shared.scheduleChapterNotification(
                    mangaTitle: title, newCount: count,
                    mediaId: novelId, mediaType: "novel"
                )
            }
        }
        return false
    }
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
    private var hasContent: Bool { !vm.entries.isEmpty }

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
                Text(summary)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: refreshSummary)
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
        // failed — always say when a check couldn't actually complete.
        var summary = newCount == 0
            ? "No new chapters"
            : "\(newCount) new chapter\(newCount == 1 ? "" : "s") found"
        if failed > 0 {
            summary += " · \(failed) source\(failed == 1 ? "" : "s") failed"
        }
        refreshSummary = summary
        try? await Task.sleep(for: .seconds(2))
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
