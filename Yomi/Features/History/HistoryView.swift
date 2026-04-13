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
}

// MARK: - HistoryView

struct HistoryView: View {

    // MARK: - State

    @State private var items: [HistoryItem] = []
    @State private var lastChapterNames: [String: String] = [:]
    @State private var isLoading = false
    @State private var selectedNovel: Novel? = nil
    @State private var novelBridgeForNav: JSBridge? = nil
    @State private var showNovelDetail = false

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
                } else {
                    List {
                        ForEach(items) { item in
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
                                    loadNovelDetail(novel)
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
                        .onDelete { offsets in
                            let toRemove = offsets.map { items[$0] }
                            items.remove(atOffsets: offsets)
                            Task.detached {
                                for item in toRemove {
                                    switch item {
                                    case .manga(let m): try? MangaQueries.clearLastRead(mangaId: m.id)
                                    case .novel(let n): try? NovelQueries.clearLastRead(novelId: n.id)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await loadHistory() }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .navigationDestination(isPresented: $showNovelDetail) {
                if let novel = selectedNovel, let bridge = novelBridgeForNav {
                    NovelDetailView(novel: novel, bridge: bridge)
                }
            }
            .task { await loadHistory() }
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

            // Merge and sort by lastReadAt descending
            let mangaItems = mangas.map { HistoryItem.manga($0) }
            let novelItems = novels.map { HistoryItem.novel($0) }
            let merged = (mangaItems + novelItems).sorted {
                ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
            }
            return (merged, map)
        }.value
        await MainActor.run {
            items = result
            lastChapterNames = lastChaps
            isLoading = false
        }
    }

    // MARK: - Novel navigation

    private func loadNovelDetail(_ novel: Novel) {
        let sourceId = novel.sourceId
        let installed = ExtensionManager.shared.installed
        let bridgeFn = ExtensionManager.shared.bridge(for:)
        Task {
            let bridge = await Task.detached(priority: .userInitiated) {
                guard let ext = installed.first(where: { $0.id == sourceId }) else { return nil as JSBridge? }
                return bridgeFn(ext)
            }.value
            guard let bridge else { return }
            selectedNovel = novel
            novelBridgeForNav = bridge
            showNovelDetail = true
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
