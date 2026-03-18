import SwiftUI
import Foundation

// MARK: - DownloadViewModel

@Observable final class DownloadViewModel {
    var downloadedByManga: [(manga: Manga, chapters: [Chapter])] = []
    var isLoading = false

    func load() async {
        isLoading = true
        await Task.detached(priority: .userInitiated) {
            let chapters = (try? DownloadQueries.fetchAllDownloaded()) ?? []
            let mangaIds = Array(Set(chapters.map { $0.mangaId }))
            let mangas = mangaIds.compactMap { try? MangaQueries.fetchOne(id: $0) }
            let grouped = mangas.map { manga in
                (manga: manga,
                 chapters: chapters
                    .filter { $0.mangaId == manga.id }
                    .sorted { ($0.chapterNumber ?? 0) < ($1.chapterNumber ?? 0) })
            }.sorted { $0.manga.title < $1.manga.title }
            await MainActor.run {
                self.downloadedByManga = grouped
                self.isLoading = false
            }
        }.value
    }

    func deleteAll(for manga: Manga) async {
        await Task.detached(priority: .userInitiated) {
            let chapters = (try? DownloadQueries.fetchDownloaded(mangaId: manga.id)) ?? []
            for ch in chapters { await DownloadManager.shared.deleteDownload(chapter: ch) }
        }.value
        await load()
    }
}

// MARK: - DownloadsView

struct DownloadsView: View {

    @State private var vm = DownloadViewModel()
    private var dm: DownloadManager { DownloadManager.shared }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !dm.isRunning && vm.downloadedByManga.isEmpty {
                    ContentUnavailableView(
                        "No downloads",
                        systemImage: "arrow.down.circle"
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await vm.load() }
    }

    // MARK: List

    private var list: some View {
        List {
            // MARK: Active Queue
            if dm.isRunning || !dm.queue.isEmpty {
                Section("Downloading") {
                    if let active = dm.activeChapter {
                        HStack {
                            Text(active.name)
                            Spacer()
                            ProgressView(value: dm.progress[active.id] ?? 0)
                                .frame(width: 80)
                        }
                    }
                    ForEach(dm.queue) { chapter in
                        HStack {
                            Text(chapter.name)
                            Spacer()
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: Downloaded
            ForEach(vm.downloadedByManga, id: \.manga.id) { entry in
                Section {
                    ForEach(entry.chapters) { chapter in
                        HStack {
                            Text(chapter.name)
                                .font(.subheadline)
                            Spacer()
                            if let date = chapter.downloadedAt {
                                Text(date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                DownloadManager.shared.deleteDownload(chapter: chapter)
                                Task { await vm.load() }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    MangaSectionHeader(manga: entry.manga) {
                        Task { await vm.deleteAll(for: entry.manga) }
                    }
                }
            }
        }
    }
}

// MARK: - MangaSectionHeader

private struct MangaSectionHeader: View {
    let manga: Manga
    let onDeleteAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: manga.coverURL) { image in
                image.resizable().aspectRatio(2 / 3, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.secondary.opacity(0.3))
            }
            .frame(width: 32, height: 48)
            .cornerRadius(4)
            .clipped()

            Text(manga.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Button(role: .destructive, action: onDeleteAll) {
                Text("Delete all")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
        .textCase(nil)
    }
}

// MARK: - Preview

#Preview {
    DownloadsView()
}
