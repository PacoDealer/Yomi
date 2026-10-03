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

                HStack(alignment: .top, spacing: YomiTokens.Layout.coverGutter) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { Task { await loadItems() } }
    }

    /// At most two titles: the last manga and the last novel read, most recent first (KNOWN_ISSUES #165 —
    /// Martin wants "what I'm reading now", not a history row).
    private func loadItems() async {
        async let mangaFetch = Task.detached(priority: .userInitiated) {
            (try? MangaQueries.fetchRecentlyRead(limit: 1)) ?? []
        }.value
        async let novelFetch = Task.detached(priority: .userInitiated) {
            (try? NovelQueries.fetchRecentlyRead(limit: 1)) ?? []
        }.value
        let (mangas, novels) = await (mangaFetch, novelFetch)

        let merged: [ContinueItem] = (mangas.map { .manga($0) } + novels.map { .novel($0) })
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }

        await MainActor.run { items = merged }
    }
}

// MARK: - ResumeReading

/// "Take me back to where I was" for one title — the chapter last touched, at its saved page/scroll position (the
/// readers restore those). Shared by the Continue shelf and History (S141: Martin wants History taps to go
/// straight into the chapter). Nil = nothing to resume from here (no saved chapters, plugin missing) → callers
/// open the detail page instead, which loads the chapters.
enum ResumeReading {
    struct MangaTarget { let bridge: JSBridge?; let chapters: [Chapter]; let index: Int }
    struct NovelTarget { let bridge: JSBridge; let chapters: [NovelChapter]; let index: Int }

    static func manga(_ manga: Manga) async -> MangaTarget? {
        let mangaId = manga.id
        var chapters = await Task.detached(priority: .userInitiated) {
            ((try? ChapterQueries.fetchAll(mangaId: mangaId)) ?? [])
                .sorted { ($0.chapterNumber ?? .greatestFiniteMagnitude) < ($1.chapterNumber ?? .greatestFiniteMagnitude) }
        }.value
        guard !chapters.isEmpty else { return nil }
        // Same list the detail page reads from, so Next/Prev don't step through other groups' copies.
        if UserDefaults.standard.object(forKey: "oneTranslationPerChapter") as? Bool ?? true {
            chapters = MangaDetailView.oneTranslationPerChapter(
                chapters, preferred: UserDefaults.standard.string(forKey: "preferredScanlator.\(mangaId)"))
        }
        let touched = chapters.filter { $0.isRead || $0.lastPageRead > 0 || $0.progress > 0 }
        let last = touched.max { ($0.readAt ?? .distantPast) < ($1.readAt ?? .distantPast) }
            ?? chapters.first { !$0.isRead }
        let index = last.flatMap { l in chapters.firstIndex { $0.id == l.id } } ?? chapters.count - 1

        // Keiyoushi titles read through the embedded JVM, not a JS plugin — the reader takes no bridge.
        if KeiyoushiMapping.isKeiyoushiSourceId(manga.sourceId) {
            return MangaTarget(bridge: nil, chapters: chapters, index: index)
        }
        guard let ext = ExtensionManager.shared.installed.first(where: { $0.id == manga.sourceId }),
              let bridge = await ExtensionManager.shared.loadBridge(for: ext) else { return nil }
        return MangaTarget(bridge: bridge, chapters: chapters, index: index)
    }

    static func novel(_ novel: Novel) async -> NovelTarget? {
        let novelId = novel.id
        let chapters = await Task.detached(priority: .userInitiated) {
            (try? NovelQueries.fetchChapters(novelId: novelId)) ?? []
        }.value
        guard !chapters.isEmpty,
              let ext = ExtensionManager.shared.installed.first(where: { $0.id == novel.sourceId }),
              let bridge = await ExtensionManager.shared.loadBridge(for: ext) else { return nil }
        // In progress, else first unread, else the last chapter — the detail page's Continue button.
        let resume = chapters.first { !$0.isRead && ($0.lastScrollPercent ?? 0) > 0.01 }
            ?? chapters.first { !$0.isRead }
            ?? chapters.last
        let index = resume.flatMap { r in chapters.firstIndex { $0.id == r.id } } ?? 0
        return NovelTarget(bridge: bridge, chapters: chapters, index: index)
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
        return [chapterName.map(Notation.shortChapter), percent].compactMap { $0 }.joined(separator: " · ")
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

            // Always one line, even empty, so both shelf cells end at the same height (S141: a novel
            // opened outside the library has no saved chapters and its bar sat a line higher).
            Text(meta.isEmpty ? " " : meta)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(canvas.textSecondary)
                .lineLimit(1)
                .padding(.top, 2)

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
    @State private var navigateToDetail = false
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
            ChapterReaderView(
                manga: manga,
                bridge: readerBridge,
                chapters: readerChapters,
                chapterIndex: readerChapterIndex
            )
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            MangaDetailView(manga: manga)
        }
    }

    private func openReader() async {
        isLoading = true
        defer { isLoading = false }
        guard let target = await ResumeReading.manga(manga) else {
            navigateToDetail = true
            return
        }
        readerBridge = target.bridge
        readerChapters = target.chapters
        readerChapterIndex = target.index
        navigateToReader = true
    }
}

// MARK: - ContinueReadingNovelCell

private struct ContinueReadingNovelCell: View {
    let novel: Novel

    @Environment(\.yomiCanvas) private var canvas
    @State private var isLoading = false
    @State private var navigateToReader = false
    @State private var navigateToDetail = false
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
        .navigationDestination(isPresented: $navigateToDetail) {
            NovelDetailView(novel: novel)
        }
    }

    private func openReader() async {
        isLoading = true
        defer { isLoading = false }
        // Read outside the library: no chapters were saved, so let the detail page load them (S141 — the
        // cell used to do nothing).
        guard let target = await ResumeReading.novel(novel) else {
            navigateToDetail = true
            return
        }
        readerBridge = target.bridge
        readerChapters = target.chapters
        readerChapterIndex = target.index
        navigateToReader = true
    }
}
