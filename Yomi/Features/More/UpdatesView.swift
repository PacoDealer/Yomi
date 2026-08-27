import SwiftUI
import Kingfisher
import CryptoKit

// MARK: - UpdateEntry

struct UpdateEntry: Identifiable {
    let id: String   // manga.id + ":" + chapter.id
    let manga: Manga
    let chapter: Chapter
}

// MARK: - Reader destinations

private struct MangaReaderDest: Identifiable, Hashable {
    let id = UUID()
    let manga: Manga
    let bridge: JSBridge
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

    var groups: [(manga: Manga, chapters: [Chapter])] = []
    var novelGroups: [(novel: Novel, chapters: [NovelChapter])] = []
    var isRefreshing = false

    /// How many titles' chapter-list fetches failed outright during the last `refresh()`, as
    /// opposed to genuinely having nothing new. Reported in the refresh summary banner.
    var failedSourceChecks = 0

    var totalCount: Int { groups.count + novelGroups.count }

    func markMangaChapterRead(chapterId: String, mangaId: String) {
        Task.detached { try? ChapterQueries.setRead(chapterId: chapterId, mangaId: mangaId, isRead: true) }
        if let i = groups.firstIndex(where: { $0.manga.id == mangaId }) {
            groups[i].chapters.removeAll { $0.id == chapterId }
            if groups[i].chapters.isEmpty { groups.remove(at: i) }
        }
    }

    func markAllMangaChaptersRead(mangaId: String) {
        guard let i = groups.firstIndex(where: { $0.manga.id == mangaId }) else { return }
        let ids = groups[i].chapters.map { $0.id }
        groups.remove(at: i)
        Task.detached { ids.forEach { try? ChapterQueries.setRead(chapterId: $0, mangaId: mangaId, isRead: true) } }
    }

    func markNovelChapterRead(chapterId: String, novelId: String) {
        Task.detached { try? NovelQueries.markRead(chapterId: chapterId, novelId: novelId) }
        if let i = novelGroups.firstIndex(where: { $0.novel.id == novelId }) {
            novelGroups[i].chapters.removeAll { $0.id == chapterId }
            if novelGroups[i].chapters.isEmpty { novelGroups.remove(at: i) }
        }
    }

    func markAllNovelChaptersRead(novelId: String) {
        guard let i = novelGroups.firstIndex(where: { $0.novel.id == novelId }) else { return }
        let ids = novelGroups[i].chapters.map { $0.id }
        novelGroups.remove(at: i)
        Task.detached { ids.forEach { try? NovelQueries.markRead(chapterId: $0, novelId: novelId) } }
    }

    func loadFromDB() async {
        let (mangaResult, novelResult) = await Task.detached(priority: .userInitiated) {
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast

            // --- Manga ---
            let mangas = (try? MangaQueries.fetchLibraryByLastUpdated()) ?? []
            let recentMangas = mangas.filter { ($0.lastUpdatedAt ?? .distantPast) >= cutoff }
            var mangaGroups: [(manga: Manga, chapters: [Chapter])] = []
            for manga in recentMangas {
                let unread = (try? ChapterQueries.fetchUnread(mangaId: manga.id)) ?? []
                if !unread.isEmpty {
                    let sorted = unread.sorted { ($0.chapterNumber ?? 0) > ($1.chapterNumber ?? 0) }
                    mangaGroups.append((manga: manga, chapters: sorted))
                }
            }

            // --- Novels ---
            let novels = (try? NovelQueries.fetchLibrary()) ?? []
            let recentNovels = novels.filter { ($0.lastUpdatedAt ?? .distantPast) >= cutoff }
            var novelGroups: [(novel: Novel, chapters: [NovelChapter])] = []
            for novel in recentNovels {
                let all = (try? NovelQueries.fetchChapters(novelId: novel.id)) ?? []
                let unread = all.filter { !$0.isRead }
                if !unread.isEmpty {
                    let sorted = unread.sorted { ($0.chapterNumber ?? 0) > ($1.chapterNumber ?? 0) }
                    novelGroups.append((novel: novel, chapters: sorted))
                }
            }

            return (mangaGroups, novelGroups)
        }.value

        groups = mangaResult
        novelGroups = novelResult
    }

    /// Returns the number of newly-discovered unread chapters (manga + novel) found this refresh.
    @discardableResult
    func refresh() async -> Int {
        guard !isRefreshing else { return 0 }
        isRefreshing = true

        let oldChapterIds = Set(groups.flatMap { $0.chapters.map(\.id) })
        let oldNovelChapterIds = Set(novelGroups.flatMap { $0.chapters.map(\.id) })

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

        let newChapterIds = Set(groups.flatMap { $0.chapters.map(\.id) })
        let newNovelChapterIds = Set(novelGroups.flatMap { $0.chapters.map(\.id) })
        return newChapterIds.subtracting(oldChapterIds).count
            + newNovelChapterIds.subtracting(oldNovelChapterIds).count
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

        let bridge = await MainActor.run { ExtensionManager.shared.bridge(for: ext) }
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

        let bridge = await MainActor.run { ExtensionManager.shared.bridge(for: ext) }
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

// MARK: - UpdateFeedItem
//
// One row per title (manga or novel) with new chapters — consolidates the
// old per-chapter row list into a single summary row, matching N.12.

private struct UpdateFeedItem: Identifiable {
    enum Kind {
        case manga(Manga, [Chapter])   // chapters sorted by chapterNumber descending
        case novel(Novel, [NovelChapter])
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .manga(let m, _): return "manga-\(m.id)"
        case .novel(let n, _): return "novel-\(n.id)"
        }
    }

    var title: String {
        switch kind {
        case .manga(let m, _): return m.title
        case .novel(let n, _): return n.title
        }
    }

    var lastUpdatedAt: Date? {
        switch kind {
        case .manga(let m, _): return m.lastUpdatedAt
        case .novel(let n, _): return n.lastUpdatedAt
        }
    }

    var count: Int {
        switch kind {
        case .manga(_, let chapters): return chapters.count
        case .novel(_, let chapters): return chapters.count
        }
    }

    /// "CH. 042" or "CH. 042–044" — chapters arrive sorted descending, so
    /// `last` is the oldest new chapter and `first` the newest.
    var note: String {
        switch kind {
        case .manga(_, let chapters):
            guard let low = chapters.last?.chapterNumber, let high = chapters.first?.chapterNumber else {
                return "\(count) new"
            }
            return Notation.chapterRange(low: low, high: high)
        case .novel(_, let chapters):
            guard let low = chapters.last?.chapterNumber, let high = chapters.first?.chapterNumber else {
                return "\(count) new"
            }
            return Notation.chapterRange(low: low, high: high)
        }
    }

    var isNovel: Bool {
        if case .novel = kind { return true }
        return false
    }
}

private struct UpdateFeedGroup: Identifiable {
    let label: String
    var items: [UpdateFeedItem]
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

    private var hasContent: Bool { !vm.groups.isEmpty || !vm.novelGroups.isEmpty }

    private var groupedFeed: [UpdateFeedGroup] {
        var buckets: [String: [UpdateFeedItem]] = [:]
        for g in vm.groups {
            let item = UpdateFeedItem(kind: .manga(g.manga, g.chapters))
            buckets[Notation.dateGroupLabel(for: g.manga.lastUpdatedAt), default: []].append(item)
        }
        for g in vm.novelGroups {
            let item = UpdateFeedItem(kind: .novel(g.novel, g.chapters))
            buckets[Notation.dateGroupLabel(for: g.novel.lastUpdatedAt), default: []].append(item)
        }
        return Notation.dateGroupOrder.compactMap { key in
            guard let arr = buckets[key], !arr.isEmpty else { return nil }
            let sorted = arr.sorted { ($0.lastUpdatedAt ?? .distantPast) > ($1.lastUpdatedAt ?? .distantPast) }
            return UpdateFeedGroup(label: key, items: sorted)
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedFeed) { group in
                            sectionHeader(group.label)
                            ForEach(group.items) { item in
                                itemRow(item)
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
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
        Text(label.uppercased())
            .font(YomiTokens.Font.mono(11))
            .tracking(0.6)
            .foregroundStyle(canvas.textSecondary)
            .padding(.top, 18)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Row

    @ViewBuilder
    private func itemRow(_ item: UpdateFeedItem) -> some View {
        switch item.kind {
        case .manga(let manga, let chapters):
            UpdateRow(
                title: item.title, coverURL: manga.coverURL, customCoverPath: manga.resolvedCustomCoverPath,
                note: item.note, count: item.count, isLoadingReader: isLoadingReader,
                destination: { MangaDetailView(manga: manga) },
                onStartReading: {
                    guard !isLoadingReader, let target = chapters.last else { return }
                    Task { await loadMangaReader(manga: manga, chapter: target) }
                }
            )
            .contextMenu {
                Button {
                    vm.markAllMangaChaptersRead(mangaId: manga.id)
                } label: {
                    Label("Mark all read", systemImage: "checkmark.circle.fill")
                }
            }
        case .novel(let novel, let chapters):
            UpdateRow(
                title: item.title, coverURL: novel.coverURL, customCoverPath: novel.resolvedCustomCoverPath,
                note: item.note, count: item.count, isLoadingReader: isLoadingReader,
                destination: { NovelDetailView(novel: novel) },
                onStartReading: {
                    guard !isLoadingReader, let target = chapters.last else { return }
                    Task { await loadNovelReader(novel: novel, chapter: target) }
                }
            )
            .contextMenu {
                Button {
                    vm.markAllNovelChaptersRead(novelId: novel.id)
                } label: {
                    Label("Mark all read", systemImage: "checkmark.circle.fill")
                }
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

        guard let bridge else { return }
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

private struct UpdateRow<Destination: View>: View {
    let title: String
    let coverURL: URL?
    let customCoverPath: String?
    let note: String
    let count: Int
    let isLoadingReader: Bool
    @ViewBuilder let destination: () -> Destination
    let onStartReading: () -> Void

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 12) {
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
                    .cornerRadius(YomiTokens.Radius.thumb)
                    .clipped()

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                            .foregroundStyle(canvas.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(note)
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(canvas.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                Text("\(count)")
                    .font(YomiTokens.Font.mono(11, bold: true))
                    .foregroundStyle(AppSettings.shared.accentForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())

                Button(action: onStartReading) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(canvas.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingReader)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { UpdatesView() }
}
