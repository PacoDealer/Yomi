import SwiftUI

// MARK: - ContinueReadingRow

struct ContinueReadingRow: View {
    @State private var items: [Manga] = []

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Continue Reading")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(items) { manga in
                                ContinueReadingCell(manga: manga)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .task {
            let loaded = await Task.detached(priority: .userInitiated) {
                (try? MangaQueries.fetchRecentlyRead(limit: 10)) ?? []
            }.value
            await MainActor.run { items = loaded }
        }
    }
}

// MARK: - ContinueReadingCell

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
                    AsyncImage(url: manga.coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(.quaternary)
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .overlay {
                                    Image(systemName: "book.closed")
                                        .foregroundStyle(.secondary)
                                }
                        default:
                            Rectangle()
                                .fill(.quaternary)
                                .aspectRatio(2 / 3, contentMode: .fill)
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

    // MARK: - Open reader at last-read chapter

    private func openReader() async {
        isLoading = true
        defer { isLoading = false }

        let sourceId = manga.sourceId
        let mangaPath = manga.path
        let mangaId = manga.id

        // Capture bridge on MainActor before entering Task.detached
        guard let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }),
              let bridge = ExtensionManager.shared.bridge(for: ext) else { return }

        let fetchedChapters = await Task.detached(priority: .userInitiated) {
            bridge.getChapterList(mangaPath: mangaPath, mangaId: mangaId)
        }.value

        guard !fetchedChapters.isEmpty else { return }

        // Merge persisted read/progress state from DB
        let saved = (try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? []
        let savedMap = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        let chapters = fetchedChapters.map { ch -> Chapter in
            guard let persisted = savedMap[ch.id] else { return ch }
            var merged = ch
            merged.isRead = persisted.isRead
            merged.readingSeconds = persisted.readingSeconds
            merged.progress = persisted.progress
            return merged
        }

        // Find most recently touched chapter
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
