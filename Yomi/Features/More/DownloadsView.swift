import SwiftUI
import Foundation
import Kingfisher

// MARK: - DownloadViewModel

@Observable final class DownloadViewModel {

    struct MangaDownloadGroup: Identifiable {
        let manga: Manga
        let chapterCount: Int
        let byteSize: Int64
        var id: String { manga.id }
    }

    struct NovelDownloadGroup: Identifiable {
        let novel: Novel
        let chapterCount: Int
        let byteSize: Int64
        var id: String { novel.id }
    }

    var groups: [MangaDownloadGroup] = []
    var novelGroups: [NovelDownloadGroup] = []
    var isLoading = false

    var totalChapters: Int {
        groups.reduce(0) { $0 + $1.chapterCount } + novelGroups.reduce(0) { $0 + $1.chapterCount }
    }
    var totalBytes: Int64 {
        groups.reduce(0) { $0 + $1.byteSize } + novelGroups.reduce(0) { $0 + $1.byteSize }
    }
    var isEmpty: Bool { groups.isEmpty && novelGroups.isEmpty }

    func load() async {
        isLoading = true
        let manager = DownloadManager.shared
        let result = await Task.detached(priority: .userInitiated) { () -> [MangaDownloadGroup] in
            let chapters = (try? DownloadQueries.fetchAllDownloaded()) ?? []
            let mangaIds = Array(Set(chapters.map { $0.mangaId }))
            let mangas = mangaIds.compactMap { try? MangaQueries.fetchOne(id: $0) }
            return mangas.map { manga in
                let count = chapters.filter { $0.mangaId == manga.id }.count
                let size = manager.directorySize(mangaId: manga.id)
                return MangaDownloadGroup(manga: manga, chapterCount: count, byteSize: size)
            }.sorted { $0.manga.title < $1.manga.title }
        }.value
        groups = result
        let novelResult = await Task.detached(priority: .userInitiated) {
            NovelDownloadStore.allGroups().map { g -> NovelDownloadGroup in
                // The DB row when there is one (library novels); otherwise the saved metadata is
                // enough to open the novel from its source again.
                let novel = (try? NovelQueries.fetchOne(id: g.meta.id)) ?? Novel(
                    id: g.meta.id, path: g.meta.path, sourceId: g.meta.sourceId, title: g.meta.title,
                    coverURL: g.meta.coverURL.flatMap(URL.init(string:)), summary: nil, author: nil,
                    status: "", genres: [], inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
                    readingSeconds: 0, readingStatus: .none, notes: nil
                )
                return NovelDownloadGroup(novel: novel, chapterCount: g.chapterCount, byteSize: g.byteSize)
            }.sorted { $0.novel.title < $1.novel.title }
        }.value
        novelGroups = novelResult
        isLoading = false
    }

    func deleteAll(for novel: Novel) async {
        NovelDownloadManager.shared.deleteAll(novelId: novel.id)
        await load()
    }

    func deleteAll(for manga: Manga) async {
        await Task.detached(priority: .userInitiated) {
            let chapters = (try? DownloadQueries.fetchDownloaded(mangaId: manga.id)) ?? []
            for ch in chapters { await DownloadManager.shared.deleteDownload(chapter: ch) }
        }.value
        await load()
    }

    func deleteEverything() async {
        for group in groups { await deleteAll(for: group.manga) }
        for group in novelGroups { NovelDownloadManager.shared.deleteAll(novelId: group.novel.id) }
        await load()
    }
}

// MARK: - DownloadsView
//
// S146 calm pass (RESEARCH §26): system nav bar, bold sentence-case section titles, plain rows on the canvas,
// no separators (Martin, S141). Delete = swipe → red trash, like Extensions and Repositories.

struct DownloadsView: View {

    @Environment(\.yomiCanvas) private var canvas
    @State private var vm = DownloadViewModel()
    @State private var confirmDeleteAll = false
    private var dm: DownloadManager { DownloadManager.shared }

    private var ndm: NovelDownloadManager { NovelDownloadManager.shared }
    private var network: NetworkMonitor { NetworkMonitor.shared }
    private var isHeldBack: Bool { dm.isWaitingForNetwork || ndm.isWaitingForNetwork }
    /// "Queued" normally; the real reason when the network setting is holding downloads back.
    private var queuedNote: String { isHeldBack ? (network.waitReason ?? "Queued") : "Queued" }

    private var hasDownloading: Bool { dm.isRunning || !dm.queue.isEmpty || !ndm.batches.isEmpty }
    private var hasContent: Bool { hasDownloading || !vm.isEmpty }

    var body: some View {
        Group {
            if vm.isLoading && !hasContent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasContent {
                YomiEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No downloads",
                    message: "Download chapters from a title's chapter list to read them offline."
                )
            } else {
                list
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !vm.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmDeleteAll = true } label: {
                            Label("Delete All Downloads", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .task { await vm.load() }
        .onChange(of: dm.completedDownloadCount) { _, _ in
            Task { await vm.load() }
        }
        .onChange(of: ndm.finishedBatchCount) { _, _ in
            Task { await vm.load() }
        }
        .yomiToast(Binding(
            get: { DownloadManager.shared.failureMessage },
            set: { DownloadManager.shared.failureMessage = $0 }
        ))
        .confirmationDialog("Delete all downloads?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { Task { await vm.deleteEverything() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every downloaded chapter from this device. Titles stay in your library.")
        }
    }

    private var list: some View {
        CalmList {
            if hasDownloading {
                Section {
                    if isHeldBack, let reason = network.waitReason {
                        waitNote(reason: reason)
                    }

                    if let active = dm.activeChapter {
                        DownloadingRow(
                            coverURL: dm.activeManga?.coverURL,
                            customCoverPath: dm.activeManga?.resolvedCustomCoverPath,
                            title: dm.activeManga?.title ?? "",
                            note: "\(active.name) · \(Int((dm.progress[active.id] ?? 0) * 100))%",
                            fraction: dm.progress[active.id] ?? 0,
                            onCancel: { dm.cancel(chapterId: active.id) }
                        )
                    }

                    ForEach(Array(dm.queue.enumerated()), id: \.element.id) { idx, chapter in
                        DownloadingRow(
                            coverURL: idx < dm.queueMangas.count ? dm.queueMangas[idx].coverURL : nil,
                            customCoverPath: idx < dm.queueMangas.count ? dm.queueMangas[idx].resolvedCustomCoverPath : nil,
                            title: idx < dm.queueMangas.count ? dm.queueMangas[idx].title : "",
                            note: "\(chapter.name) · \(queuedNote)",
                            fraction: 0,
                            onCancel: { dm.cancel(chapterId: chapter.id) }
                        )
                    }

                    // Novels: one row per novel — a whole-novel download is hundreds of chapters.
                    ForEach(ndm.batches) { batch in
                        DownloadingRow(
                            coverURL: batch.novel.coverURL,
                            customCoverPath: batch.novel.resolvedCustomCoverPath,
                            title: batch.novel.title,
                            note: ndm.active?.novel.id == batch.novel.id
                                ? "\(ndm.active?.chapter.name ?? "") · \(batch.done)/\(batch.total)"
                                : "\(batch.total - batch.done) chapters · \(queuedNote)",
                            fraction: batch.total > 0 ? Double(batch.done) / Double(batch.total) : 0,
                            onCancel: { ndm.cancel(novelId: batch.novel.id) }
                        )
                    }
                } header: { CalmSectionHeader("Downloading") }
            }

            if !vm.isEmpty {
                Section {
                    ForEach(vm.groups) { group in
                        NavigationLink {
                            MangaDetailView(manga: group.manga)
                        } label: {
                            DownloadedRow(
                                title: group.manga.title,
                                coverURL: group.manga.coverURL,
                                customCoverPath: group.manga.resolvedCustomCoverPath,
                                note: "\(chapterCount(group.chapterCount)) · \(formatBytes(group.byteSize))"
                            )
                        }
                        .swipeToDelete { Task { await vm.deleteAll(for: group.manga) } }
                    }

                    ForEach(vm.novelGroups) { group in
                        NavigationLink {
                            NovelDetailView(novel: group.novel)
                        } label: {
                            DownloadedRow(
                                title: group.novel.title,
                                coverURL: group.novel.coverURL,
                                customCoverPath: group.novel.resolvedCustomCoverPath,
                                note: "Novel · \(chapterCount(group.chapterCount)) · \(formatBytes(group.byteSize))"
                            )
                        }
                        .swipeToDelete { Task { await vm.deleteAll(for: group.novel) } }
                    }
                } header: { CalmSectionHeader("Downloaded") } footer: {
                    Text("\(formatBytes(vm.totalBytes)) on this iPhone · \(chapterCount(vm.totalChapters))")
                        .font(.footnote)
                        .foregroundStyle(canvas.textSecondary)
                        .monospacedDigit()
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Waiting note

    private func waitNote(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(reason, systemImage: network.isConnected ? "wifi" : "wifi.slash")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(canvas.textPrimary)
            if network.isWaitingForWiFi {
                Text("Downloads continue automatically on Wi-Fi.")
                    .font(.footnote)
                    .foregroundStyle(canvas.textSecondary)
                // One-off: covers what's queued now, then the setting applies again.
                Button("Download on Cellular Now") {
                    network.allowCellularForCurrentQueue()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func chapterCount(_ n: Int) -> String {
        "\(n) chapter\(n == 1 ? "" : "s")"
    }
}

// MARK: - Byte formatting

private func formatBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

private extension View {
    func swipeToDelete(_ action: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: action) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red) // the app-wide accent tint would otherwise paint it blue
        }
    }
}

// MARK: - Download cover

/// Small cover thumbnail shared by both row kinds — custom cover first, then the source's.
private struct DownloadCover: View {
    let coverURL: URL?
    let customCoverPath: String?

    var body: some View {
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
    }
}

// MARK: - DownloadingRow

private struct DownloadingRow: View {
    let coverURL: URL?
    let customCoverPath: String?
    let title: String
    let note: String
    let fraction: Double
    let onCancel: () -> Void

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        HStack(spacing: 12) {
            DownloadCover(coverURL: coverURL, customCoverPath: customCoverPath)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(canvas.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                ProgressView(value: fraction)
                    .tint(Color.accentColor)
                    .padding(.top, 2)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(canvas.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel download")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DownloadedRow

private struct DownloadedRow: View {
    let title: String
    let coverURL: URL?
    let customCoverPath: String?
    let note: String

    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        HStack(spacing: 12) {
            DownloadCover(coverURL: coverURL, customCoverPath: customCoverPath)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(canvas.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { DownloadsView() }
}
