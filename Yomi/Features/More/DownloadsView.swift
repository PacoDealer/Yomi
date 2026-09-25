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
// Design spec: YOMI Screens.dc.html N.13 (Downloads).

struct DownloadsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.yomiCanvas) private var canvas
    @State private var vm = DownloadViewModel()
    @State private var confirmDeleteAll = false
    private var dm: DownloadManager { DownloadManager.shared }

    private var ndm: NovelDownloadManager { NovelDownloadManager.shared }

    private var hasDownloading: Bool { dm.isRunning || !dm.queue.isEmpty || !ndm.batches.isEmpty }
    private var hasContent: Bool { hasDownloading || !vm.isEmpty }
    private var downloadingCount: Int {
        dm.queue.count + (dm.isRunning ? 1 : 0) + ndm.batches.reduce(0) { $0 + $1.total - $1.done }
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasContent {
                YomiEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No downloads",
                    message: "Download chapters from a title's chapter list to read them offline."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Downloads")
                            .font(YomiTokens.Font.grotesk(26, weight: .medium))
                            .foregroundStyle(canvas.textPrimary)
                            .padding(.top, 8)

                        if hasDownloading {
                            sectionHeader("Downloading · \(downloadingCount)")

                            if let active = dm.activeChapter {
                                DownloadingRow(
                                    coverURL: dm.activeManga?.coverURL,
                                    customCoverPath: dm.activeManga?.resolvedCustomCoverPath,
                                    title: dm.activeManga?.title ?? "",
                                    note: "\(active.name) · \(Int((dm.progress[active.id] ?? 0) * 100))%",
                                    fraction: dm.progress[active.id] ?? 0,
                                    onCancel: { dm.cancel(chapterId: active.id) }
                                )
                                Divider().padding(.leading, 72)
                            }

                            ForEach(Array(dm.queue.enumerated()), id: \.element.id) { idx, chapter in
                                DownloadingRow(
                                    coverURL: idx < dm.queueMangas.count ? dm.queueMangas[idx].coverURL : nil,
                                    customCoverPath: idx < dm.queueMangas.count ? dm.queueMangas[idx].resolvedCustomCoverPath : nil,
                                    title: idx < dm.queueMangas.count ? dm.queueMangas[idx].title : "",
                                    note: "\(chapter.name) · Queued",
                                    fraction: 0,
                                    onCancel: { dm.cancel(chapterId: chapter.id) }
                                )
                                Divider().padding(.leading, 72)
                            }

                            // Novels: one row per novel — a whole-novel download is hundreds of chapters.
                            ForEach(ndm.batches) { batch in
                                DownloadingRow(
                                    coverURL: batch.novel.coverURL,
                                    customCoverPath: batch.novel.resolvedCustomCoverPath,
                                    title: batch.novel.title,
                                    note: ndm.active?.novel.id == batch.novel.id
                                        ? "\(ndm.active?.chapter.name ?? "") · \(batch.done)/\(batch.total)"
                                        : "\(batch.total - batch.done) chapters · Queued",
                                    fraction: batch.total > 0 ? Double(batch.done) / Double(batch.total) : 0,
                                    onCancel: { ndm.cancel(novelId: batch.novel.id) }
                                )
                                Divider().padding(.leading, 72)
                            }
                        }

                        if !vm.isEmpty {
                            sectionHeader("Downloaded")

                            ForEach(vm.groups) { group in
                                NavigationLink {
                                    MangaDetailView(manga: group.manga)
                                } label: {
                                    DownloadedRow(
                                        title: group.manga.title,
                                        coverURL: group.manga.coverURL,
                                        customCoverPath: group.manga.resolvedCustomCoverPath,
                                        note: "\(group.chapterCount) chapter\(group.chapterCount == 1 ? "" : "s") · \(formatBytes(group.byteSize))"
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await vm.deleteAll(for: group.manga) }
                                    } label: {
                                        Label("Delete all downloads", systemImage: "trash")
                                    }
                                }
                                Divider().padding(.leading, 72)
                            }

                            ForEach(vm.novelGroups) { group in
                                NavigationLink {
                                    NovelDetailView(novel: group.novel)
                                } label: {
                                    DownloadedRow(
                                        title: group.novel.title,
                                        coverURL: group.novel.coverURL,
                                        customCoverPath: group.novel.resolvedCustomCoverPath,
                                        note: "Novel · \(group.chapterCount) chapter\(group.chapterCount == 1 ? "" : "s") · \(formatBytes(group.byteSize))"
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await vm.deleteAll(for: group.novel) }
                                    } label: {
                                        Label("Delete all downloads", systemImage: "trash")
                                    }
                                }
                                Divider().padding(.leading, 72)
                            }

                            Text("\(formatBytes(vm.totalBytes).uppercased()) USED · \(vm.totalChapters) CHAPTER\(vm.totalChapters == 1 ? "" : "S")")
                                .font(YomiTokens.Font.mono(11))
                                .foregroundStyle(canvas.textSecondary.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    .padding(.bottom, 24)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { glassNavBar }
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
            Button("Delete all", role: .destructive) { Task { await vm.deleteEverything() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every downloaded chapter from this device. Titles stay in your library.")
        }
    }

    // MARK: - Glass nav bar (DESIGN_SYSTEM §14 — floating chrome over the backdrop)

    private var glassNavBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .glassChip()

            Spacer()

            if !vm.isEmpty {
                Button { confirmDeleteAll = true } label: {
                    Image(systemName: "trash")
                }
                .glassChip()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
}

// MARK: - Byte formatting

private func formatBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
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
            cover

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Text(note)
                    .font(YomiTokens.Font.mono(12))
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(canvas.textSecondary.opacity(0.16))
                        Capsule().fill(Color.accentColor).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(canvas.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
    }

    private var cover: some View {
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

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(1)
                Text(note)
                    .font(YomiTokens.Font.mono(12))
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canvas.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { DownloadsView() }
}
