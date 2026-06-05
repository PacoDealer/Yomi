import SwiftUI
import Kingfisher

// MARK: - ContinueItem

private enum ContinueItem: Identifiable {
    case manga(Manga)
    case novel(Novel)

    var id: String {
        switch self {
        case .manga(let m): return "manga-\(m.id)"
        case .novel(let n): return "novel-\(n.id)"
        }
    }

    var lastReadAt: Date? {
        switch self {
        case .manga(let m): return m.lastReadAt
        case .novel(let n): return n.lastReadAt
        }
    }

    var coverURL: URL? {
        switch self {
        case .manga(let m): return m.coverURL
        case .novel(let n): return n.coverURL
        }
    }

    var title: String {
        switch self {
        case .manga(let m): return m.title
        case .novel(let n): return n.title
        }
    }
}

// MARK: - ContinueReadingRow

struct ContinueReadingRow: View {
    @State private var items: [ContinueItem] = []

    var body: some View {
        // Outer VStack always present so .onAppear fires even when items is empty.
        // A Group containing EmptyView() has no layout presence — onAppear never fires.
        VStack(spacing: 0) {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Continue Reading")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(items) { item in
                                switch item {
                                case .manga(let manga):
                                    ContinueReadingCell(manga: manga)
                                case .novel(let novel):
                                    ContinueReadingNovelCell(novel: novel)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .onAppear { Task { await loadItems() } }
    }

    private func loadItems() async {
        async let mangaFetch = Task.detached(priority: .userInitiated) {
            (try? MangaQueries.fetchRecentlyRead(limit: 10)) ?? []
        }.value
        async let novelFetch = Task.detached(priority: .userInitiated) {
            (try? NovelQueries.fetchRecentlyRead(limit: 10)) ?? []
        }.value
        let (mangas, novels) = await (mangaFetch, novelFetch)

        let merged: [ContinueItem] = (mangas.map { .manga($0) } + novels.map { .novel($0) })
            .sorted {
                switch ($0.lastReadAt, $1.lastReadAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                default: return false
                }
            }
            .prefix(10)
            .map { $0 }

        await MainActor.run { items = merged }
    }
}

// MARK: - ContinueReadingCell (manga)

private struct ContinueReadingCell: View {
    let manga: Manga

    @State private var isLoading = false
    @State private var navigateToReader = false
    @State private var readerBridge: JSBridge? = nil
    @State private var readerChapters: [Chapter] = []
    @State private var readerChapterIndex: Int = 0
    @State private var lastChapterName: String? = nil
    @State private var readProgress: Double = 0

    var body: some View {
        Button {
            guard !isLoading else { return }
            Task { await openReader() }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Group {
                        if let path = manga.resolvedCustomCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                        } else {
                            CoverImage(url: manga.coverURL)
                        }
                    }
                    .frame(width: 90)
                    .cornerRadius(7)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if readProgress > 0 && readProgress < 1 {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * readProgress, height: 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 3)
                        }
                    }

                    Text(manga.title)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 90)
                        .foregroundStyle(.primary)

                    if let chName = lastChapterName {
                        Text(chName)
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(width: 90)
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: manga.id) {
            let chapters = await Task.detached {
                (try? ChapterQueries.fetchAll(mangaId: manga.id)) ?? []
            }.value
            let touched = chapters
                .filter { $0.isRead || $0.progress > 0 }
                .sorted { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) }
            lastChapterName = touched.first?.name
            if !chapters.isEmpty {
                let readCount = chapters.filter { $0.isRead }.count
                readProgress = Double(readCount) / Double(chapters.count)
            }
        }
        .navigationDestination(isPresented: $navigateToReader) {
            if let bridge = readerBridge {
                ChapterReaderView(
                    manga: manga,
                    bridge: bridge,
                    chapters: readerChapters,
                    chapterIndex: readerChapterIndex
                )
            }
        }
    }

    private func openReader() async {
        isLoading = true
        defer { isLoading = false }

        let sourceId = manga.sourceId
        let mangaPath = manga.path
        let mangaId = manga.id

        guard let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }),
              let bridge = ExtensionManager.shared.bridge(for: ext) else { return }

        let fetchedChapters = await Task.detached(priority: .userInitiated) {
            bridge.getChapterList(mangaPath: mangaPath, mangaId: mangaId)
        }.value

        let saved = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        guard !fetchedChapters.isEmpty || !saved.isEmpty else { return }

        let chapters: [Chapter]
        if fetchedChapters.isEmpty {
            // Network failed — fall back to DB chapters
            chapters = saved
        } else {
            let savedMap = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
            chapters = fetchedChapters.map { ch -> Chapter in
                guard let persisted = savedMap[ch.id] else { return ch }
                var merged = ch
                merged.isRead = persisted.isRead
                merged.readingSeconds = persisted.readingSeconds
                merged.progress = persisted.progress
                return merged
            }
        }

        let lastTouched = saved
            .filter { $0.isRead || $0.progress > 0 }
            .sorted { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) }
            .first

        let chapterIndex: Int
        if let last = lastTouched,
           let idx = chapters.firstIndex(where: { $0.id == last.id }) {
            chapterIndex = idx
        } else {
            chapterIndex = chapters.count - 1
        }

        readerBridge = bridge
        readerChapters = chapters
        readerChapterIndex = chapterIndex
        navigateToReader = true
    }
}

// MARK: - ContinueReadingNovelCell

private struct ContinueReadingNovelCell: View {
    let novel: Novel

    @State private var isLoading = false
    @State private var navigateToReader = false
    @State private var readerBridge: JSBridge? = nil
    @State private var readerChapters: [NovelChapter] = []
    @State private var readerChapterIndex: Int = 0
    @State private var lastChapterName: String? = nil
    @State private var readProgress: Double = 0

    var body: some View {
        Button {
            guard !isLoading else { return }
            Task { await openReader() }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Group {
                        if let path = novel.resolvedCustomCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                        } else {
                            CoverImage(url: novel.coverURL)
                        }
                    }
                    .frame(width: 90)
                    .cornerRadius(7)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if readProgress > 0 && readProgress < 1 {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * readProgress, height: 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 3)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        Text("N")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                    }

                    Text(novel.title)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 90)
                        .foregroundStyle(.primary)

                    if let chName = lastChapterName {
                        Text(chName)
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(width: 90)
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: novel.id) {
            let chapters = await Task.detached {
                (try? NovelQueries.fetchChapters(novelId: novel.id)) ?? []
            }.value
            let touched = chapters
                .filter { $0.isRead || ($0.lastScrollPercent ?? 0) > 0.01 }
                .sorted { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) }
            lastChapterName = touched.first?.name
            if !chapters.isEmpty {
                let readCount = chapters.filter { $0.isRead }.count
                readProgress = Double(readCount) / Double(chapters.count)
            }
        }
        .navigationDestination(isPresented: $navigateToReader) {
            if let bridge = readerBridge {
                TextReaderView(novel: novel, bridge: bridge, chapters: readerChapters, startIndex: readerChapterIndex)
            }
        }
    }

    private func openReader() async {
        isLoading = true
        defer { isLoading = false }

        let novelId = novel.id
        let sourceId = novel.sourceId

        let chapters = await Task.detached(priority: .userInitiated) {
            (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
        }.value

        guard !chapters.isEmpty else { return }

        let bridge: JSBridge?
        if let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) {
            bridge = ExtensionManager.shared.bridge(for: ext)
        } else {
            bridge = nil
        }
        guard let b = bridge else { return }

        // Resume: in-progress first, then first unread, then last chapter
        let resumeChapter: NovelChapter?
        if let inProgress = chapters.first(where: { !$0.isRead && ($0.lastScrollPercent ?? 0) > 0.01 }) {
            resumeChapter = inProgress
        } else if let firstUnread = chapters.first(where: { !$0.isRead }) {
            resumeChapter = firstUnread
        } else {
            resumeChapter = chapters.last
        }

        let idx: Int
        if let resume = resumeChapter,
           let found = chapters.firstIndex(where: { $0.id == resume.id }) {
            idx = found
        } else {
            idx = max(0, chapters.count - 1)
        }

        readerBridge = b
        readerChapters = chapters
        readerChapterIndex = idx
        navigateToReader = true
    }
}
