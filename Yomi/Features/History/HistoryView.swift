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
//
// Design spec: YOMI Screens.dc.html N.11 (History).

struct HistoryView: View {

    // MARK: - State

    @Environment(\.yomiCanvas) private var canvas
    @State private var items: [HistoryItem] = []
    @State private var chapterSubtitles: [String: String] = [:]
    @State private var isLoading = false
    @State private var selectedNovel: Novel? = nil
    @State private var showNovelDetail = false
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
                if isLoading {
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
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(groupedHistory) { group in
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
                    .refreshable { await loadHistory() }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !items.isEmpty {
                        Button("Clear") { confirmClearAll = true }
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(canvas.textSecondary)
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
            .searchable(text: $searchQuery, prompt: "Search history")
            .onAppear { Task { await loadHistory() } }
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

    // MARK: - Row builder

    @ViewBuilder
    private func itemRow(_ item: HistoryItem) -> some View {
        switch item {
        case .manga(let manga):
            NavigationLink {
                MangaDetailView(manga: manga)
            } label: {
                HistoryRow(
                    title: manga.title,
                    coverURL: manga.coverURL,
                    customCoverPath: manga.resolvedCustomCoverPath,
                    lastReadAt: manga.lastReadAt,
                    subtitle: chapterSubtitles[manga.id],
                    isNovel: false
                )
            }
            .contextMenu {
                Button(role: .destructive) { deleteItem(item) } label: {
                    Label("Remove from History", systemImage: "trash")
                }
            }
        case .novel(let novel):
            Button {
                selectedNovel = novel; showNovelDetail = true
            } label: {
                HistoryRow(
                    title: novel.title,
                    coverURL: novel.coverURL,
                    customCoverPath: novel.resolvedCustomCoverPath,
                    lastReadAt: novel.lastReadAt,
                    subtitle: chapterSubtitles[novel.id],
                    isNovel: true
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) { deleteItem(item) } label: {
                    Label("Remove from History", systemImage: "trash")
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

            var map: [String: String] = [:]
            for manga in mangas {
                guard let chapters = try? ChapterQueries.fetchAll(mangaId: manga.id) else { continue }
                let touched = chapters
                    .filter { $0.isRead || $0.progress > 0 }
                    .sorted { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) }
                    .first
                guard let touched, let number = touched.chapterNumber else { continue }
                map[manga.id] = touched.isRead
                    ? Notation.chapter(number)
                    : Notation.chapterReadTo(chapter: number, fraction: touched.progress)
            }
            for novel in novels {
                guard let chapters = try? NovelQueries.fetchChapters(novelId: novel.id) else { continue }
                // Prefer the in-progress chapter (partially read), then fall back to last fully-read
                let inProgress = chapters.first(where: { !$0.isRead && ($0.lastScrollPercent ?? 0) > 0.01 })
                let lastFullyRead = chapters
                    .filter { $0.readAt != nil }
                    .sorted { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) }
                    .first
                if let inProgress, let number = inProgress.chapterNumber {
                    map[novel.id] = Notation.chapterReadTo(chapter: number, fraction: inProgress.lastScrollPercent ?? 0)
                } else if let lastFullyRead, let number = lastFullyRead.chapterNumber {
                    map[novel.id] = Notation.chapter(number)
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

private struct HistoryRow: View {
    let title: String
    let coverURL: URL?
    let customCoverPath: String?
    let lastReadAt: Date?
    let subtitle: String?
    let isNovel: Bool

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
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

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle {
                    Text(subtitle)
                        .font(YomiTokens.Font.mono(12))
                        .foregroundStyle(canvas.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let lastReadAt {
                    Text(Notation.historyTimestamp(lastReadAt))
                        .font(YomiTokens.Font.mono(11))
                        .foregroundStyle(canvas.textSecondary.opacity(0.6))
                }
                Text(isNovel ? "NOVEL" : "MANGA")
                    .font(YomiTokens.Font.mono(9, bold: true))
                    .tracking(0.4)
                    .foregroundStyle(canvas.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(canvas.surface2, in: RoundedRectangle(cornerRadius: YomiTokens.Radius.badge))
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
