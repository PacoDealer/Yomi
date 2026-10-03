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
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        // Outer VStack always present so .onAppear fires even when items is empty.
        // A Group containing EmptyView() has no layout presence — onAppear never fires.
        // S138: one Apple Music-style shelf replaces the hero card + "Up next" (RESEARCH §26).
        VStack(alignment: .leading, spacing: 0) {
            if !items.isEmpty {
                Text("Continue reading")
                    .font(.title2.bold())
                    .foregroundStyle(canvas.textPrimary)
                    .padding(.horizontal, YomiTokens.Layout.screenMargin)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: YomiTokens.Layout.coverGutter) {
                        ForEach(items) { item in
                            switch item {
                            case .manga(let manga):
                                ContinueReadingCell(manga: manga)
                            case .novel(let novel):
                                ContinueReadingNovelCell(novel: novel)
                            }
                        }
                    }
                    .padding(.horizontal, YomiTokens.Layout.screenMargin)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - ContinueShelfLabel

/// Cover, title, "Chapter 25 · 3%" and a thin progress bar — shared by the manga and novel
/// shelf cells (S138 calm design; the old cells had a "NOVEL" pill and centred 11 pt text).
private struct ContinueShelfLabel: View {
    let customCoverPath: String?
    let coverURL: URL?
    let title: String
    let chapterName: String?
    let progress: Double
    let isLoading: Bool
    @Environment(\.yomiCanvas) private var canvas

    static let width: CGFloat = 150

    private var meta: String {
        let percent = progress > 0 ? Notation.progress(progress) : nil
        return [chapterName.map(Self.shortChapter), percent].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Chapter 25: 5th Cycle's Dawn" / "Ch. 25" → "Chapter 25", so the percentage still fits on the line.
    nonisolated static func shortChapter(_ name: String) -> String {
        if let match = name.firstMatch(of: /^(Chapter|Ch\.?)\s*([\d.]+)/.ignoresCase()) {
            return Double(match.output.2).map(Notation.chapter) ?? String(match.output.0)
        }
        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let customCoverPath, let uiImage = UIImage(contentsOfFile: customCoverPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .coverAspectSized()
                } else {
                    CoverImage(url: coverURL)
                }
            }
            .frame(width: Self.width)
            .clipShape(RoundedRectangle(cornerRadius: YomiTokens.Radius.cover))
            .coverHairline()
            .overlay {
                if isLoading {
                    ProgressView()
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Text(title)
                .font(.subheadline)
                .foregroundStyle(canvas.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 7)

            if !meta.isEmpty {
                Text(meta)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }

            Capsule()
                .fill(canvas.surface2)
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(canvas.textSecondary)
                            .frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                }
                .padding(.top, 8)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - ContinueReadingCell (manga)

private struct ContinueReadingCell: View {
    let manga: Manga

    @Environment(\.yomiCanvas) private var canvas
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
            ContinueShelfLabel(
                customCoverPath: manga.resolvedCustomCoverPath,
                coverURL: manga.coverURL,
                title: manga.title,
                chapterName: lastChapterName,
                progress: readProgress,
                isLoading: isLoading
            )
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
              let bridge = await ExtensionManager.shared.loadBridge(for: ext) else { return }

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
            // See the manga branch above — `fetchedChapters` isn't guaranteed ascending.
            chapters = fetchedChapters.map { ch -> Chapter in
                guard let persisted = savedMap[ch.id] else { return ch }
                var merged = ch
                merged.isRead = persisted.isRead
                merged.readingSeconds = persisted.readingSeconds
                merged.progress = persisted.progress
                return merged
            }.sorted { ($0.chapterNumber ?? .greatestFiniteMagnitude) < ($1.chapterNumber ?? .greatestFiniteMagnitude) }
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

    @Environment(\.yomiCanvas) private var canvas
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
            ContinueShelfLabel(
                customCoverPath: novel.resolvedCustomCoverPath,
                coverURL: novel.coverURL,
                title: novel.title,
                chapterName: lastChapterName,
                progress: readProgress,
                isLoading: isLoading
            )
        }
        .buttonStyle(.plain)
        .task(id: novel.id) {
            let chapters = await Task.detached {
                (try? NovelQueries.fetchChapters(novelId: novel.id)) ?? []
            }.value
            // Same chapter tapping opens: in progress, else first unread, else the last one.
            // (Most-recent readAt picked the prologue when chapters were bulk-marked read.)
            let resume = chapters.first(where: { !$0.isRead && ($0.lastScrollPercent ?? 0) > 0.01 })
                ?? chapters.first(where: { !$0.isRead })
                ?? chapters.last
            lastChapterName = resume?.name
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
            bridge = await ExtensionManager.shared.loadBridge(for: ext)
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
