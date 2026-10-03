import SwiftUI
import Kingfisher

// MARK: - HistoryItem

private enum HistoryItem: Identifiable {
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

    var title: String {
        switch self {
        case .manga(let m): return m.title
        case .novel(let n): return n.title
        }
    }
}

// MARK: - HistoryGroup

private struct HistoryGroup: Identifiable {
    let label: String
    var items: [HistoryItem]
    var id: String { label }
}

// MARK: - HistoryView

struct HistoryView: View {

    // MARK: - State

    @Environment(\.yomiCanvas) private var canvas
    @State private var items: [HistoryItem] = []
    @State private var chapterSubtitles: [String: String] = [:]
    @State private var isLoading = false
    @State private var selectedNovel: Novel? = nil
    @State private var showNovelDetail = false
    @State private var selectedManga: Manga? = nil
    @State private var showMangaDetail = false
    /// Tapping a row resumes reading (S141, Martin): the chapter last read, at its saved page/scroll.
    @State private var openingId: String? = nil
    @State private var mangaTarget: ResumeReading.MangaTarget? = nil
    @State private var novelTarget: ResumeReading.NovelTarget? = nil
    @State private var showMangaReader = false
    @State private var showNovelReader = false
    @State private var confirmClearAll = false
    @State private var searchQuery = ""

    // MARK: - Grouping

    private var filteredItems: [HistoryItem] {
        guard !searchQuery.isEmpty else { return items }
        return items.filter { $0.title.localizedStandardContains(searchQuery) }
    }

    private var groupedHistory: [HistoryGroup] {
        var buckets: [String: [HistoryItem]] = [:]
        for item in filteredItems {
            let key = Notation.dateGroupLabel(for: item.lastReadAt)
            buckets[key, default: []].append(item)
        }
        return Notation.dateGroupOrder.compactMap { key in
            guard let arr = buckets[key], !arr.isEmpty else { return nil }
            return HistoryGroup(label: key, items: arr)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    YomiEmptyState(
                        systemImage: "clock",
                        title: "No history",
                        message: "Titles you've read will appear here."
                    )
                } else if groupedHistory.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
                    // S141 calm pass: the Extensions list's plain rows + title2 headers; swipe → red trash.
                    List {
                        ForEach(groupedHistory) { group in
                            Section {
                                sectionHeader(group.label)
                                ForEach(group.items) { item in
                                    itemRow(item)
                                        .modifier(DeleteSwipe(title: "Remove") { deleteItem(item) })
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .yomiListCanvas()
                    .refreshable { await loadHistory() }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !items.isEmpty {
                        Button("Clear") { confirmClearAll = true }
                    }
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClearAll, titleVisibility: .visible) {
                Button("Clear all", role: .destructive) { clearAllHistory() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all reading history. Your library and read progress are not affected.")
            }
            .navigationDestination(isPresented: $showNovelDetail) {
                if let novel = selectedNovel {
                    NovelDetailView(novel: novel)
                }
            }
            .navigationDestination(isPresented: $showMangaDetail) {
                if let manga = selectedManga {
                    MangaDetailView(manga: manga)
                }
            }
            .navigationDestination(isPresented: $showMangaReader) {
                if let manga = selectedManga, let t = mangaTarget {
                    ChapterReaderView(manga: manga, bridge: t.bridge, chapters: t.chapters, chapterIndex: t.index)
                }
            }
            .navigationDestination(isPresented: $showNovelReader) {
                if let novel = selectedNovel, let t = novelTarget {
                    TextReaderView(novel: novel, bridge: t.bridge, chapters: t.chapters, startIndex: t.index)
                }
            }
            .searchable(text: $searchQuery, prompt: "Search history")
            .onAppear { Task { await loadHistory() } }
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

    // MARK: - Row builder

    @ViewBuilder
    private func itemRow(_ item: HistoryItem) -> some View {
        switch item {
        case .manga(let manga):
            Button {
                resume(item)
            } label: {
                HistoryRow(
                    title: manga.title,
                    coverURL: manga.coverURL,
                    customCoverPath: manga.resolvedCustomCoverPath,
                    lastReadAt: manga.lastReadAt,
                    subtitle: chapterSubtitles[manga.id],
                    isOpening: openingId == item.id
                )
            }
            .buttonStyle(.plain)
        case .novel(let novel):
            Button {
                resume(item)
            } label: {
                HistoryRow(
                    title: novel.title,
                    coverURL: novel.coverURL,
                    customCoverPath: novel.resolvedCustomCoverPath,
                    lastReadAt: novel.lastReadAt,
                    subtitle: chapterSubtitles[novel.id],
                    isOpening: openingId == item.id
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Resume

    /// Opens the reader where the user left off; the detail page when there's nothing saved to resume from.
    private func resume(_ item: HistoryItem) {
        guard openingId == nil else { return }
        openingId = item.id
        Task {
            defer { openingId = nil }
            switch item {
            case .manga(let manga):
                selectedManga = manga
                if let t = await ResumeReading.manga(manga) {
                    mangaTarget = t; showMangaReader = true
                } else {
                    showMangaDetail = true
                }
            case .novel(let novel):
                selectedNovel = novel
                if let t = await ResumeReading.novel(novel) {
                    novelTarget = t; showNovelReader = true
                } else {
                    showNovelDetail = true
                }
            }
        }
    }

    // MARK: - Delete

    private func deleteItem(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        Task.detached {
            switch item {
            case .manga(let m): try? MangaQueries.clearLastRead(mangaId: m.id)
            case .novel(let n): try? NovelQueries.clearLastRead(novelId: n.id)
            }
        }
    }

    // MARK: - Clear all

    private func clearAllHistory() {
        let snapshot = items
        items = []
        Task.detached {
            for item in snapshot {
                switch item {
                case .manga(let m): try? MangaQueries.clearLastRead(mangaId: m.id)
                case .novel(let n): try? NovelQueries.clearLastRead(novelId: n.id)
                }
            }
        }
    }

    // MARK: - Load

    private func loadHistory() async {
        isLoading = true
        let (result, subtitles) = await Task.detached {
            let mangas = (try? MangaQueries.fetchHistory()) ?? []
            let novels = (try? NovelQueries.fetchHistory()) ?? []

            // "Chapter 722 · 32%" — same wording as the Continue shelf. Falls back to the chapter's NAME
            // when the source gives no number (S141: several rows showed no chapter at all).
            func line(name: String, number: Double?, fraction: Double, finished: Bool) -> String {
                let chapter = number.map(Notation.chapter) ?? Notation.shortChapter(name)
                return finished || fraction <= 0.01 ? chapter : "\(chapter) · \(Notation.progress(fraction))"
            }
            var map: [String: String] = [:]
            for manga in mangas {
                guard let chapters = try? ChapterQueries.fetchAll(mangaId: manga.id),
                      let touched = chapters
                        .filter({ $0.isRead || $0.progress > 0 })
                        .max(by: { ($0.readAt ?? .distantPast) < ($1.readAt ?? .distantPast) }) else { continue }
                map[manga.id] = line(name: touched.name, number: touched.chapterNumber,
                                     fraction: touched.progress, finished: touched.isRead)
            }
            for novel in novels {
                guard let chapters = try? NovelQueries.fetchChapters(novelId: novel.id) else { continue }
                // Prefer the in-progress chapter (partially read), then fall back to last fully-read
                let inProgress = chapters.first(where: { !$0.isRead && ($0.lastScrollPercent ?? 0) > 0.01 })
                let lastFullyRead = chapters
                    .filter { $0.readAt != nil }
                    .max { ($0.readAt ?? .distantPast) < ($1.readAt ?? .distantPast) }
                if let ch = inProgress ?? lastFullyRead {
                    map[novel.id] = line(name: ch.name, number: ch.chapterNumber,
                                         fraction: ch.lastScrollPercent ?? 0, finished: ch.isRead)
                }
            }

            // Merge (sort deferred to MainActor to avoid isolation warning)
            let mangaItems = mangas.map { HistoryItem.manga($0) }
            let novelItems = novels.map { HistoryItem.novel($0) }
            return (mangaItems + novelItems, map)
        }.value
        await MainActor.run {
            // Sort on MainActor — avoids "lastReadAt referenced from nonisolated context" warning
            items = result.sorted {
                ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
            }
            chapterSubtitles = subtitles
            isLoading = false
        }
    }

}

// MARK: - HistoryRow

/// Cover, title, "Chapter 722 · 32%", time — Apple Music's song-row rhythm (RESEARCH §26).
private struct HistoryRow: View {
    let title: String
    let coverURL: URL?
    let customCoverPath: String?
    let lastReadAt: Date?
    let subtitle: String?
    var isOpening = false

    @Environment(\.yomiCanvas) private var canvas
    @State private var settings = AppSettings.shared

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
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(canvas.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isOpening {
                ProgressView()
            } else if let lastReadAt {
                Text(Notation.historyTimestamp(
                    lastReadAt,
                    use24Hour: settings.use24HourClock,
                    dayFirst: settings.dateOrderDayFirst
                ))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(canvas.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 8, leading: YomiTokens.Layout.screenMargin,
                                  bottom: 8, trailing: YomiTokens.Layout.screenMargin))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(canvas.hairline)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 58 }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
