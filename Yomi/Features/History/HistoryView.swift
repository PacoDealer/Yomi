import SwiftUI

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

    @State private var items: [HistoryItem] = []
    @State private var lastChapterNames: [String: String] = [:]
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
        let cal = Calendar.current
        let now = Date()
        var buckets: [String: [HistoryItem]] = [:]
        for item in filteredItems {
            let key = dateGroupLabel(for: item.lastReadAt, calendar: cal, now: now)
            buckets[key, default: []].append(item)
        }
        let order = ["Today", "Yesterday", "This week", "This month", "Earlier"]
        return order.compactMap { key in
            guard let arr = buckets[key], !arr.isEmpty else { return nil }
            return HistoryGroup(label: key, items: arr)
        }
    }

    private func dateGroupLabel(for date: Date?, calendar: Calendar, now: Date) -> String {
        guard let date else { return "Earlier" }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days < 7  { return "This week" }
        if days < 30 { return "This month" }
        return "Earlier"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "No history",
                        systemImage: "clock",
                        description: Text("Titles you've read will appear here.")
                    )
                } else if groupedHistory.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
                    List {
                        ForEach(groupedHistory) { group in
                            Section(group.label) {
                                ForEach(group.items) { item in
                                    itemRow(item)
                                }
                                .onDelete { offsets in
                                    deleteFromGroup(label: group.label, offsets: offsets)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await loadHistory() }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !items.isEmpty {
                        Button(role: .destructive) {
                            confirmClearAll = true
                        } label: {
                            Image(systemName: "trash")
                        }
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
            .task { await loadHistory() }
        }
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
                    lastReadAt: manga.lastReadAt,
                    sourceName: ExtensionManager.shared.installed
                        .first { $0.id == manga.sourceId }?.name ?? manga.sourceId,
                    subtitle: lastChapterNames[manga.id],
                    isNovel: false
                )
            }
        case .novel(let novel):
            Button {
                selectedNovel = novel; showNovelDetail = true
            } label: {
                HistoryRow(
                    title: novel.title,
                    coverURL: novel.coverURL,
                    lastReadAt: novel.lastReadAt,
                    sourceName: ExtensionManager.shared.installed
                        .first { $0.id == novel.sourceId }?.name ?? novel.sourceId,
                    subtitle: lastChapterNames[novel.id],
                    isNovel: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Delete

    private func deleteFromGroup(label: String, offsets: IndexSet) {
        guard let groupItems = groupedHistory.first(where: { $0.label == label })?.items else { return }
        let toRemove = offsets.map { groupItems[$0] }
        items.removeAll { item in toRemove.contains(where: { $0.id == item.id }) }
        Task.detached {
            for item in toRemove {
                switch item {
                case .manga(let m): try? MangaQueries.clearLastRead(mangaId: m.id)
                case .novel(let n): try? NovelQueries.clearLastRead(novelId: n.id)
                }
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
        let (result, lastChaps) = await Task.detached {
            let mangas = (try? MangaQueries.fetchHistory()) ?? []
            let novels = (try? NovelQueries.fetchHistory()) ?? []

            var map: [String: String] = [:]
            for manga in mangas {
                if let chapters = try? ChapterQueries.fetchAll(mangaId: manga.id),
                   let lastRead = chapters.filter({ $0.readAt != nil })
                       .sorted(by: { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) })
                       .first {
                    map[manga.id] = lastRead.name
                }
            }
            for novel in novels {
                if let chapters = try? NovelQueries.fetchChapters(novelId: novel.id),
                   let lastRead = chapters.filter({ $0.readAt != nil })
                       .sorted(by: { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) })
                       .first {
                    map[novel.id] = lastRead.name
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
            lastChapterNames = lastChaps
            isLoading = false
        }
    }

}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let title: String
    let coverURL: URL?
    let lastReadAt: Date?
    let sourceName: String
    let subtitle: String?
    let isNovel: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(2 / 3, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .aspectRatio(2 / 3, contentMode: .fit)
            }
            .frame(width: 48)
            .cornerRadius(6)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    if let d = lastReadAt {
                        Text(d, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(sourceName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if isNovel {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("Novel")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
