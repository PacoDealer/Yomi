import SwiftUI

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

    var totalCount: Int { groups.count + novelGroups.count }

    func markMangaChapterRead(chapterId: String, mangaId: String) {
        Task.detached { try? ChapterQueries.setRead(chapterId: chapterId, isRead: true) }
        if let i = groups.firstIndex(where: { $0.manga.id == mangaId }) {
            groups[i].chapters.removeAll { $0.id == chapterId }
            if groups[i].chapters.isEmpty { groups.remove(at: i) }
        }
    }

    func markAllMangaChaptersRead(mangaId: String) {
        guard let i = groups.firstIndex(where: { $0.manga.id == mangaId }) else { return }
        let ids = groups[i].chapters.map { $0.id }
        groups.remove(at: i)
        Task.detached { ids.forEach { try? ChapterQueries.setRead(chapterId: $0, isRead: true) } }
    }

    func markNovelChapterRead(chapterId: String, novelId: String) {
        Task.detached { try? NovelQueries.markRead(chapterId: chapterId) }
        if let i = novelGroups.firstIndex(where: { $0.novel.id == novelId }) {
            novelGroups[i].chapters.removeAll { $0.id == chapterId }
            if novelGroups[i].chapters.isEmpty { novelGroups.remove(at: i) }
        }
    }

    func markAllNovelChaptersRead(novelId: String) {
        guard let i = novelGroups.firstIndex(where: { $0.novel.id == novelId }) else { return }
        let ids = novelGroups[i].chapters.map { $0.id }
        novelGroups.remove(at: i)
        Task.detached { ids.forEach { try? NovelQueries.markRead(chapterId: $0) } }
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

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        let (library, novelLibrary) = await Task.detached(priority: .userInitiated) {
            let manga = (try? MangaQueries.fetchLibrary()) ?? []
            let novels = (try? NovelQueries.fetchLibrary()) ?? []
            return (manga, novels)
        }.value

        await withTaskGroup(of: Void.self) { group in
            for manga in library {
                group.addTask { await self.checkUpdates(for: manga) }
            }
            for novel in novelLibrary {
                group.addTask { await self.checkNovelUpdates(for: novel) }
            }
        }

        await loadFromDB()
        isRefreshing = false
    }

    private func checkUpdates(for manga: Manga) async {
        let settings = AppSettings.shared

        // Smart skip conditions
        if settings.skipUpdateNotStarted && manga.lastReadAt == nil { return }
        if settings.skipUpdateCompleted && manga.status == .completed { return }
        if settings.skipUpdateWithUnread {
            let unread = (try? ChapterQueries.fetchUnread(mangaId: manga.id)) ?? []
            if !unread.isEmpty { return }
        }
        if !settings.excludedCategoryIds.isEmpty {
            let assigned = (try? CategoryQueries.categoriesForManga(mangaId: manga.id)) ?? []
            if assigned.contains(where: { settings.excludedCategoryIds.contains($0.id) }) { return }
        }

        let sourceId  = manga.sourceId
        let mangaPath = manga.path
        let mangaId   = manga.id

        let allInstalled = await MainActor.run { ExtensionManager.shared.installed }
        let ext = allInstalled.first(where: { $0.id == sourceId })
        guard let ext else { return }

        let bridge = await MainActor.run { ExtensionManager.shared.bridge(for: ext) }
        let remoteChapters = await Task.detached(priority: .background) {
            return bridge?.getChapterList(mangaPath: mangaPath, mangaId: mangaId) ?? []
        }.value

        guard !remoteChapters.isEmpty else { return }

        let localChapters = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        let localIds = Set(localChapters.map { $0.id })
        let newChapters = remoteChapters.filter { !localIds.contains($0.id) }

        guard !newChapters.isEmpty else { return }

        try? ChapterQueries.insertMangaAndChapters(manga: manga, chapters: newChapters)
        try? MangaQueries.touchLastUpdated(mangaId: mangaId)

        let title = manga.title
        let count = newChapters.count
        if AppSettings.shared.sendUpdateNotifications {
            await MainActor.run {
                NotificationManager.shared.scheduleChapterNotification(mangaTitle: title, newCount: count)
            }
        }
    }

    private func checkNovelUpdates(for novel: Novel) async {
        let sourceId  = novel.sourceId
        let novelPath = novel.path
        let novelId   = novel.id

        let allInstalled = await MainActor.run { ExtensionManager.shared.installed }
        let ext = allInstalled.first(where: { $0.id == sourceId })
        guard let ext else { return }

        let bridge = await MainActor.run { ExtensionManager.shared.bridge(for: ext) }
        let source = await Task.detached(priority: .background) {
            bridge?.parseNovel(path: novelPath)
        }.value

        guard let source, !source.chapters.isEmpty else { return }

        let localChapters = (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
        let localPaths = Set(localChapters.map { $0.path })

        let newChapters: [NovelChapter] = source.chapters
            .filter { !localPaths.contains($0.path) }
            .enumerated()
            .map { offset, ch in
                NovelChapter(
                    id: "\(novelId)-ch-\(localChapters.count + offset)",
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

        guard !newChapters.isEmpty else { return }

        try? NovelQueries.insertAllIgnoringConflicts(newChapters)
        try? NovelQueries.touchLastUpdated(novelId: novelId)

        let title = novel.title
        let count = newChapters.count
        if AppSettings.shared.sendUpdateNotifications {
            await MainActor.run {
                NotificationManager.shared.scheduleChapterNotification(mangaTitle: title, newCount: count)
            }
        }
    }
}

// MARK: - UpdatesView

struct UpdatesView: View {
    @State private var vm = UpdatesViewModel.shared

    @State private var mangaReaderDest: MangaReaderDest? = nil
    @State private var novelReaderDest: NovelReaderDest? = nil
    @State private var isLoadingReader = false

    private var hasContent: Bool { !vm.groups.isEmpty || !vm.novelGroups.isEmpty }

    var body: some View {
        List {
            if !hasContent && !vm.isRefreshing {
                ContentUnavailableView(
                    "No updates yet",
                    systemImage: "bell.badge",
                    description: Text("Add titles to your library and refresh to check for new chapters.")
                )
            } else {
                ForEach(vm.groups, id: \.manga.id) { group in
                    Section {
                        ForEach(group.chapters) { chapter in
                            Button {
                                guard !isLoadingReader else { return }
                                Task { await loadMangaReader(manga: group.manga, chapter: chapter) }
                            } label: {
                                UpdateChapterRow(chapter: chapter)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    vm.markMangaChapterRead(chapterId: chapter.id, mangaId: group.manga.id)
                                } label: {
                                    Label("Mark read", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                        }
                    } header: {
                        MangaUpdateHeader(manga: group.manga, count: group.chapters.count) {
                            vm.markAllMangaChaptersRead(mangaId: group.manga.id)
                        }
                    }
                }

                ForEach(vm.novelGroups, id: \.novel.id) { group in
                    Section {
                        ForEach(group.chapters) { chapter in
                            Button {
                                guard !isLoadingReader else { return }
                                Task { await loadNovelReader(novel: group.novel, chapter: chapter) }
                            } label: {
                                UpdateNovelChapterRow(chapter: chapter)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    vm.markNovelChapterRead(chapterId: chapter.id, novelId: group.novel.id)
                                } label: {
                                    Label("Mark read", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                        }
                    } header: {
                        NovelUpdateHeader(novel: group.novel, count: group.chapters.count) {
                            vm.markAllNovelChaptersRead(novelId: group.novel.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Updates")
        .refreshable { await vm.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isRefreshing || isLoadingReader {
                    ProgressView()
                } else {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
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

// MARK: - MangaUpdateHeader

private struct MangaUpdateHeader: View {
    let manga: Manga
    let count: Int
    let onMarkAllRead: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let path = manga.customCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage).resizable().aspectRatio(2 / 3, contentMode: .fill)
                } else {
                    AsyncImage(url: manga.coverURL) { image in
                        image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.3))
                    }
                }
            }
            .frame(width: 20, height: 30)
            .cornerRadius(3)
            .clipped()

            NavigationLink {
                MangaDetailView(manga: manga)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(manga.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(count) new chapter\(count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                        if let updated = manga.lastUpdatedAt {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(updated, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onMarkAllRead) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

// MARK: - NovelUpdateHeader

private struct NovelUpdateHeader: View {
    let novel: Novel
    let count: Int
    let onMarkAllRead: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let path = novel.customCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage).resizable().aspectRatio(2 / 3, contentMode: .fill)
                } else {
                    AsyncImage(url: novel.coverURL) { image in
                        image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.3))
                    }
                }
            }
            .frame(width: 20, height: 30)
            .cornerRadius(3)
            .clipped()

            NavigationLink {
                NovelDetailView(novel: novel)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(novel.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(count) new chapter\(count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Novel")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let updated = novel.lastUpdatedAt {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(updated, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onMarkAllRead) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

// MARK: - UpdateChapterRow

private struct UpdateChapterRow: View {
    let chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chapter.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if let num = chapter.chapterNumber {
                let numStr = num.truncatingRemainder(dividingBy: 1) == 0
                    ? "Chapter \(Int(num))"
                    : String(format: "Chapter %.1f", num)
                Text(numStr)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - UpdateNovelChapterRow

private struct UpdateNovelChapterRow: View {
    let chapter: NovelChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chapter.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if let num = chapter.chapterNumber {
                let numStr = num.truncatingRemainder(dividingBy: 1) == 0
                    ? "Chapter \(Int(num))"
                    : String(format: "Chapter %.1f", num)
                Text(numStr)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { UpdatesView() }
}
