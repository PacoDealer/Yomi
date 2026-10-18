import SwiftUI
import StoreKit
import Kingfisher

// MARK: - ReaderMode

enum ReaderMode: String, CaseIterable {
    case horizontalRTL  = "Manga (RTL)"
    case horizontalLTR  = "Manhwa (LTR)"
    case verticalScroll = "Webtoon"
    case verticalPaged  = "Paged (Vertical)"
    case continuousRTL  = "Continuous (RTL)"
    case continuousLTR  = "Continuous (LTR)"
}

// MARK: - ChapterReaderView

struct ChapterReaderView: View {
    let manga: Manga
    /// `nil` for a Suwayomi-sourced manga: that backend has no JS plugin, so pages are resolved
    /// over REST from the chapter's own `suwayomi://` path instead (Known Issue #131).
    let bridge: JSBridge?
    let chapters: [Chapter]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = AppSettings.shared
    @State private var shouldRequestReview = false
    @State private var currentChapterIndex: Int
    /// Named for `PageNames` as they come in: Keiyoushi pages get a new address every launch (S182).
    @State private var pages: [String] = [] { didSet { PageNames.name(pages, chapterId: activeChapter.id) } }
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var readerMode: ReaderMode
    @State private var showOverlay = true
    @State private var currentPage = 0
    @State private var sessionStart: Date = Date()
    @State private var discussURL: URL? = nil
    @State private var showDiscussSheet = false
    @State private var sourceURL: URL? = nil
    @State private var showSourceSheet = false
    @State private var showFinishedBanner = false
    @State private var didMarkCurrentChapterRead = false
    @State private var toastMessage: String? = nil
    /// Non-error banner (page menu: "Saved to Photos", "Page copied").
    @State private var infoMessage: String? = nil
    @State private var nextPreload: (chapter: Chapter, pages: [String], sources: [Int]?)? = nil {
        didSet { if let nextPreload { PageNames.name(nextPreload.pages, chapterId: nextPreload.chapter.id) } }
    }
    /// Source page of each entry in `pages` when a downloaded chapter has tall pages stored as parts (D12); nil = the
    /// same index. Saved progress (`lastPageRead`) is always in source pages.
    @State private var pageSources: [Int]? = nil
    /// Chapters whose shown page list came from `PageListCache` and hasn't been fetched again yet (D12b).
    @State private var cachedListPaths: Set<String> = []
    @State private var isPreloadingNextChapter = false
    @State private var didUpdateTrackerForCurrentChapter = false
    @State private var pagePrefetcher = ReaderPagePrefetcher()
    /// Toolbar quick actions (L3c) change chapters the reader was handed as a `let`: kept here so the bookmark button
    /// and the chapter list show them.
    @State private var bookmarkOverrides: [String: Bool] = [:]
    @State private var markedReadIds: Set<String> = []

    init(manga: Manga, bridge: JSBridge?, chapters: [Chapter], chapterIndex: Int) {
        self.manga = manga
        self.bridge = bridge
        self.chapters = chapters
        _currentChapterIndex = State(initialValue: chapterIndex)
        let modeString = AppSettings.shared.readerMode
        var initialMode = ReaderMode(rawValue: modeString) ?? .horizontalRTL
        if AppSettings.shared.autoWebtoonFromTags {
            let webtoonTags = ["webtoon", "long strip", "manhwa", "manhua"]
            let genres = manga.genres.map { $0.lowercased() }
            if webtoonTags.contains(where: { tag in genres.contains(where: { $0.contains(tag) }) }) {
                initialMode = .verticalScroll
            }
        }
        _readerMode = State(initialValue: initialMode)
    }

    // MARK: - Computed

    private var activeChapter: Chapter { chapters[currentChapterIndex] }
    private var hasPrevChapter: Bool { currentChapterIndex > 0 }
    private var hasNextChapter: Bool { currentChapterIndex < chapters.count - 1 }
    private var isActiveBookmarked: Bool { bookmarkOverrides[activeChapter.id] ?? activeChapter.isBookmarked }

    /// `chapters` with the toolbar's bookmark / mark-read changes, for the overlay's chapter list.
    private var shownChapters: [Chapter] {
        guard !bookmarkOverrides.isEmpty || !markedReadIds.isEmpty else { return chapters }
        return chapters.map { ch in
            var c = ch
            if let b = bookmarkOverrides[ch.id] { c.isBookmarked = b }
            if markedReadIds.contains(ch.id) { c.isRead = true }
            return c
        }
    }

    /// Only continuous-scroll modes get the seamless in-scroll chapter-boundary transition —
    /// paged modes keep the explicit tap-to-advance flow via the overlay's Next button.
    private var isContinuousReaderMode: Bool {
        switch readerMode {
        case .verticalScroll, .continuousRTL, .continuousLTR: return true
        default: return false
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ReaderBackdrop.base(settings.readerBackground).ignoresSafeArea()

            #if DEBUG
            // UI tests (perf gates, S179) read the page on screen here: "page/pages", "loading" until pages arrive.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("reader.mangaPage")
                .accessibilityValue(pages.isEmpty ? "loading" : "\(currentPage + 1)/\(pages.count)")
            #endif

            // Tap-to-hide chrome — sits behind all reader content so
            // scroll/pinch gestures on the reader views still take priority.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showOverlay.toggle() }

            if isLoading {
                ProgressView()
                    .tint(ReaderBackdrop.isLight(settings.readerBackground) ? .black : .white)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(ReaderBackdrop.isLight(settings.readerBackground) ? .black : .white)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if !pages.isEmpty {
                switch readerMode {
                case .horizontalRTL:
                    MangaReaderView(
                        pages: pages,
                        currentPage: $currentPage,
                        showOverlay: $showOverlay,
                        isRTL: true
                    )
                case .horizontalLTR:
                    MangaReaderView(
                        pages: pages,
                        currentPage: $currentPage,
                        showOverlay: $showOverlay,
                        isRTL: false
                    )
                case .verticalScroll:
                    WebtoonReaderView(
                        pages: pages,
                        currentPage: $currentPage,
                        showOverlay: $showOverlay,
                        nextChapter: nextPreload?.chapter,
                        nextPages: nextPreload?.pages ?? [],
                        boundaryTitles: nextPreload.map { (activeChapter.name, $0.chapter.name) },
                        onNeedsNextChapterPreload: preloadNextChapterIfNeeded,
                        onCrossedIntoNextChapter: { crossIntoPreloadedChapter(atLocalIndex: $0) }
                    )
                case .verticalPaged:
                    VerticalPagedReaderView(
                        pages: pages,
                        currentPage: $currentPage,
                        showOverlay: $showOverlay
                    )
                case .continuousRTL:
                    ContinuousHorizontalReaderView(
                        pages: pages,
                        currentPage: $currentPage,
                        showOverlay: $showOverlay,
                        isRTL: true,
                        nextChapter: nextPreload?.chapter,
                        nextPages: nextPreload?.pages ?? [],
                        boundaryTitles: nextPreload.map { (activeChapter.name, $0.chapter.name) },
                        onNeedsNextChapterPreload: preloadNextChapterIfNeeded,
                        onCrossedIntoNextChapter: { crossIntoPreloadedChapter(atLocalIndex: $0) }
                    )
                case .continuousLTR:
                    ContinuousHorizontalReaderView(
                        pages: pages,
                        currentPage: $currentPage,
                        showOverlay: $showOverlay,
                        isRTL: false,
                        nextChapter: nextPreload?.chapter,
                        nextPages: nextPreload?.pages ?? [],
                        boundaryTitles: nextPreload.map { (activeChapter.name, $0.chapter.name) },
                        onNeedsNextChapterPreload: preloadNextChapterIfNeeded,
                        onCrossedIntoNextChapter: { crossIntoPreloadedChapter(atLocalIndex: $0) }
                    )
                }
            }

            if showFinishedBanner {
                chapterFinishedBanner
            }

            ReaderOverlayView(
                manga: manga,
                chapter: activeChapter,
                currentChapterIndex: currentChapterIndex,
                chapters: shownChapters,
                currentPage: $currentPage,
                totalPages: pages.count,
                readerMode: $readerMode,
                showOverlay: $showOverlay,
                showPageNumber: true,
                discussURL: discussURL,
                sourceURL: sourceURL,
                hasPrevChapter: hasPrevChapter,
                hasNextChapter: hasNextChapter,
                onDismiss: { dismiss() },
                onDiscuss: { showDiscussSheet = true },
                onViewSource: { showSourceSheet = true },
                onPrevChapter: { navigateToChapter(currentChapterIndex - 1) },
                onNextChapter: { navigateToChapter(currentChapterIndex + 1) },
                onJumpToChapter: { navigateToChapter($0) },
                isBookmarked: isActiveBookmarked,
                onToggleBookmark: toggleBookmark,
                onMarkPreviousRead: markPreviousRead,
                currentPageURL: pages.indices.contains(currentPage) ? pages[currentPage] : nil
            )
        }
        .navigationBarHidden(true)
        .swipeBackEnabled()
        .navigationBarStaysHidden(true)   // #206: opened while a search was active
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .tabBar)
        .yomiToast($toastMessage)
        .yomiToast($infoMessage, isError: false)
        .onReceive(NotificationCenter.default.publisher(for: ReaderPageActions.toast)) { infoMessage = $0.object as? String }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            sessionStart = Date()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            pagePrefetcher.stop()
            PageShapes.save()
            PageLooks.save()

            let incognito = AppSettings.shared.isIncognito

            // Mark as read if reached last page, or read ≥80% of a multi-page chapter
            let readProgress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
            if !incognito && !pages.isEmpty && (currentPage == pages.count - 1 || (pages.count > 1 && readProgress >= 0.8)) {
                markChapterRead()
            }

            // No pages = the chapter never loaded (offline, Cloudflare, source error): saving would overwrite the
            // real position with page 0 — S141 lost "Chapter 1 · 55%, page 21" this way.
            guard !incognito, !pages.isEmpty else { return }

            let elapsed = Int(Date().timeIntervalSince(sessionStart))
            let progress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
            let cid = activeChapter.id
            let page = sourcePage(currentPage)
            Task.detached {
                try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed, lastPageRead: page)
            }

            guard !pages.isEmpty, elapsed > 3 else { return }
            let mangaId = manga.id
            Task.detached(priority: .background) {
                try? MangaQueries.addReadingSeconds(mangaId: mangaId, seconds: elapsed)
            }
        }
        // S182 (Martin's phone): the exit save above never runs when Yomi is closed from the app switcher or by iOS while
        // a chapter is open, so reopening it started at page 1. Save the position each time Yomi goes to the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { PageShapes.save(); PageLooks.save() }   // S182: a kill skips onDisappear
            guard phase == .background, !AppSettings.shared.isIncognito, !pages.isEmpty else { return }
            let elapsed = Int(Date().timeIntervalSince(sessionStart))
            let progress = Double(currentPage + 1) / Double(pages.count)
            let cid = activeChapter.id
            let page = sourcePage(currentPage)
            Task.detached {
                try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed, lastPageRead: page)
            }
        }
        // Pages ahead load before they're reached (S161): on every page change, a new page list, the next chapter's list.
        .onChange(of: pages) { prefetchAhead() }
        .onReceive(NotificationCenter.default.publisher(for: PageRetry.pageFailed)) { note in
            if let url = note.object as? String { refreshCachedList(afterFailing: url) }
        }
        .onChange(of: nextPreload?.pages ?? []) { prefetchAhead() }
        .onChange(of: currentPage) { _, newPage in
            prefetchAhead()
            if pages.count > 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            if pages.count > 0 && newPage >= pages.count - 2 {
                withMotion(.spring(duration: 0.4)) { showFinishedBanner = true }
            }
            if !AppSettings.shared.isIncognito && pages.count > 0 && newPage >= pages.count - 2 {
                markChapterRead()
                if AppSettings.shared.trackerAutoUpdate && !didUpdateTrackerForCurrentChapter {
                    didUpdateTrackerForCurrentChapter = true
                    let mangaTitle = manga.trackingTitle ?? manga.title
                    let chapNum = Int(activeChapter.chapterNumber ?? 0)
                    Task {
                        for tracker in TrackerManager.loggedInTrackers {
                            if let trackerId = await tracker.searchManga(title: mangaTitle) {
                                await tracker.updateMangaProgress(trackerId: trackerId, chaptersRead: chapNum)
                            }
                        }
                    }
                }
            }
        }
        .task { await loadPages() }
        .task(id: activeChapter.id) {
            let path = activeChapter.path
            // No bridge means a Suwayomi-sourced chapter: neither a discussion URL nor a plugin
            // BASE_URL exists to resolve, so both icons stay hidden.
            guard let b = bridge else {
                discussURL = nil
                sourceURL = nil
                return
            }
            discussURL = await Task.detached(priority: .background) {
                b.getDiscussionURL(chapterPath: path)
            }.value
            sourceURL = await Task.detached(priority: .background) {
                b.resolveSourceURL(path: path)
            }.value
        }
        .sheet(isPresented: $showDiscussSheet) {
            if let url = discussURL {
                DiscussWebSheet(url: url)
            }
        }
        .sheet(isPresented: $showSourceSheet) {
            if let url = sourceURL {
                DiscussWebSheet(url: url, title: String(localized: "Source"))
            }
        }
        .onChange(of: shouldRequestReview) { _, should in
            if should { requestReview(); shouldRequestReview = false }
        }
    }

    // MARK: - Toolbar quick actions (L3c)

    private func toggleBookmark() {
        let id = activeChapter.id, mangaId = manga.id, bookmarked = !isActiveBookmarked
        bookmarkOverrides[id] = bookmarked
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        infoMessage = bookmarked ? String(localized: "Chapter bookmarked") : String(localized: "Bookmark removed")
        Task.detached { try? ChapterQueries.setBookmarked(chapterIds: [id], mangaId: mangaId, bookmarked: bookmarked) }
    }

    /// Every chapter before this one (reading order), like the detail screen's "Mark previous". Only unread ones are
    /// written: `setReadBatch` stamps `readAt`, and chapters already read keep their real read date.
    private func markPreviousRead() {
        let ids = shownChapters[..<currentChapterIndex].filter { !$0.isRead }.map(\.id), mangaId = manga.id
        guard !ids.isEmpty else { infoMessage = String(localized: "Earlier chapters are already read"); return }
        markedReadIds.formUnion(ids)
        infoMessage = ids.count == 1 ? "1 chapter marked as read" : "\(ids.count) chapters marked as read"
        Task.detached { try? ChapterQueries.setReadBatch(chapterIds: ids, mangaId: mangaId, isRead: true) }
    }

    // MARK: - Chapter Finished Banner

    @ViewBuilder private var chapterFinishedBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text(hasNextChapter ? "Chapter finished" : "All caught up!")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if hasNextChapter {
                    Button {
                        navigateToChapter(currentChapterIndex + 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .transition(Motion.slide(.bottom))
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(5))
                withMotion(.easeOut(duration: 0.25)) { showFinishedBanner = false }
            }
        }
    }

    // MARK: - Mark as Read

    private func markChapterRead() {
        guard !didMarkCurrentChapterRead else { return }
        didMarkCurrentChapterRead = true
        let cid = activeChapter.id
        let mid = activeChapter.mangaId
        let wasDownloaded = activeChapter.isDownloaded
        let deleteAfterReading = AppSettings.shared.deleteDownloadAfterReading
        Task.detached {
            do {
                try ChapterQueries.markRead(id: cid, mangaId: mid)
            } catch {
                print("markChapterRead error: \(error)")
                await MainActor.run {
                    toastMessage = String(localized: "Couldn't save read status")
                    YomiHaptics.error()
                }
            }
            // Auto-delete download after finishing a downloaded chapter
            if wasDownloaded && deleteAfterReading {
                let dir = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Downloads/\(mid)/\(cid)")
                try? FileManager.default.removeItem(at: dir)
                try? DownloadQueries.markNotDownloaded(chapterId: cid)
            }
            await MainActor.run {
                if AppSettings.shared.recordChapterRead() {
                    self.shouldRequestReview = true
                }
            }
        }
    }

    // MARK: - Chapter boundary preload (continuous/webtoon modes only)
    //
    // Tachimanga-style seamless transition: as the user nears the end of a chapter, fetch the
    // next chapter's pages in the background and hand them to the reader view, which appends a
    // boundary card + those pages directly into the same scroll content. When the user scrolls
    // past the boundary, `crossIntoPreloadedChapter` swaps ChapterReaderView's state (chapter
    // index, active `pages`, progress bookkeeping) without touching the scroll view at all — the
    // content the user is already looking at doesn't move, only its meaning changes.

    private func prefetchAhead() {
        pagePrefetcher.update(pages: pages, current: currentPage, nextChapterPages: nextPreload?.pages ?? [])
    }

    private func preloadNextChapterIfNeeded() {
        guard isContinuousReaderMode, hasNextChapter, nextPreload == nil, !isPreloadingNextChapter else { return }
        let next = chapters[currentChapterIndex + 1]

        // Prefer local files first, exactly like loadPages() does — otherwise every
        // chapter-boundary preload for a downloaded (offline-read) chapter burns the full
        // network timeout below trying and failing to reach the network, silently degrading
        // the seamless-crossing feature for the offline case it matters most in. See #90.
        if next.isDownloaded, let local = DownloadManager.shared.localPages(for: next) {
            nextPreload = (next, local.urls.map(\.absoluteString), local.sourcePages)
            return
        }

        isPreloadingNextChapter = true
        let path = next.path
        let b = bridge

        // SOURCE._fetchSync (JSBridge.swift) blocks synchronously on a DispatchSemaphore with no
        // timeout — fine for a foreground chapter load the user is already waiting on, but this
        // preload is opportunistic and silent. A slow/rate-limited/Cloudflare-challenged source
        // must not be allowed to tie things up indefinitely just because the user kept scrolling.
        // The race below only bounds how long we WAIT for a result — cancelAll() can't preempt the
        // underlying blocking call itself, so a truly stuck fetch still burns one background thread
        // until it eventually resolves; it just no longer holds up the preload state machine.
        Task {
            let result: (pages: [String], fromCache: Bool)? = await withTaskGroup(of: (pages: [String], fromCache: Bool)?.self) { group in
                group.addTask { await Self.readerPages(bridge: b, path: path) }
                group.addTask {
                    try? await Task.sleep(for: .seconds(12))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            guard isPreloadingNextChapter, nextPreload == nil,
                  hasNextChapter, chapters[currentChapterIndex + 1].id == next.id else { return }
            if let result, !result.pages.isEmpty {
                nextPreload = (next, result.pages, nil)
                if result.fromCache { cachedListPaths.insert(path) }
            }
            isPreloadingNextChapter = false
        }
    }

    private func crossIntoPreloadedChapter(atLocalIndex idx: Int) {
        guard let preload = nextPreload,
              hasNextChapter, preload.chapter.id == chapters[currentChapterIndex + 1].id else { return }

        // Close out the chapter being left, same bookkeeping navigateToChapter does explicitly.
        let leavingElapsed = Int(Date().timeIntervalSince(sessionStart))
        let leavingProgress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
        let leavingId = activeChapter.id
        let leavingPage = sourcePage(currentPage)
        if !AppSettings.shared.isIncognito {
            Task.detached {
                try? ChapterQueries.updateProgress(id: leavingId, progress: leavingProgress, readingSeconds: leavingElapsed, lastPageRead: leavingPage)
            }
        }
        markChapterRead()

        currentChapterIndex += 1
        pages = preload.pages
        pageSources = preload.sources
        currentPage = min(idx, max(pages.count - 1, 0))
        nextPreload = nil
        didMarkCurrentChapterRead = false
        didUpdateTrackerForCurrentChapter = false
        sessionStart = Date()
    }

    // MARK: - Navigation

    private func navigateToChapter(_ index: Int) {
        showFinishedBanner = false
        didMarkCurrentChapterRead = false
        didUpdateTrackerForCurrentChapter = false
        nextPreload = nil
        isPreloadingNextChapter = false

        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        let progress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
        let cid = activeChapter.id
        let page = sourcePage(currentPage)
        if !AppSettings.shared.isIncognito, !pages.isEmpty {   // see the exit save: empty = never loaded
            Task.detached {
                try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed, lastPageRead: page)
            }
        }

        currentChapterIndex = index
        pages = []
        pageSources = nil
        isLoading = true
        errorMessage = nil
        currentPage = 0
        sessionStart = Date()

        // A downloaded chapter opens from its files, offline too (it went to the network before D12).
        if chapters[index].isDownloaded, let local = DownloadManager.shared.localPages(for: chapters[index]) {
            pages = local.urls.map(\.absoluteString)
            pageSources = local.sourcePages
            isLoading = false
            return
        }

        let path = chapters[index].path
        let b = bridge
        Task {
            let result = await Self.readerPages(bridge: b, path: path)
            // A second, faster navigateToChapter() call (rapid double-tap, or two picks from
            // the Chapters sheet in quick succession) may have already moved past `index` by
            // the time this resolves — applying it now would overwrite the newer chapter's
            // pages with a stale result. See finding #88.
            guard currentChapterIndex == index else { return }
            pages = result.pages
            if result.fromCache { cachedListPaths.insert(path) }
            isLoading = false
            if result.pages.isEmpty {
                errorMessage = await Self.localArchiveError(path: path) ?? String(localized: "No pages found.")
            }
        }
    }

    /// Why a local chapter has no pages ("password-protected", "a 7z method Yomi doesn't read"…) — `fetchPages` only
    /// returns pages, so on failure ask once more for the error (S175; before, every case said "No pages found").
    private static func localArchiveError(path: String) async -> String? {
        guard path.hasPrefix(LocalLibrary.mangaScheme) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            do { _ = try LocalLibrary.pageURLs(chapterPath: path); return nil }
            catch { return error.localizedDescription }
        }.value
    }

    /// A page of a cached list failed to load (D12b): its URLs may have gone stale. Fetch the list again — once per
    /// chapter — keep it, and swap it in if it changed. Same index = same source page, so progress means the same.
    private func refreshCachedList(afterFailing url: String) {
        let path: String
        if cachedListPaths.contains(activeChapter.path), pageSources == nil, pages.contains(url) {
            path = activeChapter.path
        } else if let preload = nextPreload, cachedListPaths.contains(preload.chapter.path), preload.pages.contains(url) {
            path = preload.chapter.path
        } else { return }
        cachedListPaths.remove(path)
        let b = bridge
        Task {
            let fresh = await Self.fetchPages(bridge: b, path: path)
            #if DEBUG
            print("[PageListCache] page failed, list fetched again for \(path): \(fresh.count) pages")
            #endif
            guard !fresh.isEmpty else { return }   // offline: keep what we have, its pages may still be in Kingfisher
            Task.detached(priority: .utility) { PageListCache.store(fresh, for: path) }
            if activeChapter.path == path, pageSources == nil {
                guard fresh != pages else { return }
                pages = fresh
                currentPage = min(currentPage, fresh.count - 1)
            } else if let preload = nextPreload, preload.chapter.path == path, fresh != preload.pages {
                nextPreload = (preload.chapter, fresh, nil)
            }
        }
    }

    // MARK: - Page Source

    /// Resolves a chapter's page URLs from whichever backend the manga came from.
    ///
    /// The JS-plugin path stays on a detached task — `SOURCE._fetchSync` blocks its thread on a
    /// `DispatchSemaphore` and must never run on MainActor. The Suwayomi path is ordinary async
    /// `URLSession` work and needs no hop. So is the Keiyoushi path: the extension runs in the embedded JVM
    /// and pages come back as `http://127.0.0.1:<port>/image/<id>` URLs served by the on-device bridge.
    static func fetchPages(bridge: JSBridge?, path: String) async -> [String] {
        if path.hasPrefix(LocalLibrary.mangaScheme) {
            // A CBZ is unpacked into Caches on first open — off the main actor (S148).
            return await Task.detached(priority: .userInitiated) {
                ((try? LocalLibrary.pageURLs(chapterPath: path)) ?? []).map(\.absoluteString)
            }.value
        }
        if SuwayomiService.chapterRef(from: path) != nil {
            return (try? await SuwayomiService.shared.fetchPageURLs(chapterPath: path)) ?? []
        }
        if let ref = KeiyoushiMapping.chapterRef(from: path) {
            // Twice: the first call after a launch once lost its reply on device ("Socket closed", S144).
            var pages: [KeiyoushiPage] = []
            for _ in 0..<2 where pages.isEmpty {
                pages = (try? await KeiyoushiBridge.shared.pages(sourceId: ref.sourceId, chapterURL: ref.url,
                                                                 chapterName: ref.name)) ?? []
            }
            return pages.sorted { $0.index < $1.index }.compactMap { page in
                if let image = page.imageUrl, !image.isEmpty { return image }
                return page.url
            }
        }
        guard let bridge else { return [] }
        return await Task.detached(priority: .userInitiated) {
            bridge.getPageList(chapterPath: path)
        }.value
    }

    /// The reader's page list: the one kept in `PageListCache` while it is fresh (D12b — no plugin or JVM call), else
    /// `fetchPages`, kept for the next time. Downloads keep calling `fetchPages` directly.
    static func readerPages(bridge: JSBridge?, path: String) async -> (pages: [String], fromCache: Bool) {
        if let kept = await Task.detached(priority: .userInitiated, operation: { PageListCache.pages(for: path) }).value {
            #if DEBUG
            print("[PageListCache] hit \(path): \(kept.count) pages, no plugin call")
            #endif
            return (kept, true)
        }
        let start = Date()
        let fetched = await fetchPages(bridge: bridge, path: path)
        #if DEBUG
        print("[PageListCache] miss \(path): fetched \(fetched.count) pages in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        #endif
        Task.detached(priority: .utility) { PageListCache.store(fetched, for: path) }
        return (fetched, false)
    }

    // MARK: - Page numbers

    /// The source page of local page `index` — what progress is saved as.
    private func sourcePage(_ index: Int) -> Int {
        guard let pageSources, pageSources.indices.contains(index) else { return index }
        return pageSources[index]
    }

    /// The first local page of source page `page` (its top part when split).
    nonisolated static func localPage(forSource page: Int, in sources: [Int]?) -> Int {
        guard let sources else { return page }
        return sources.firstIndex { $0 >= page } ?? max(sources.count - 1, 0)
    }

    // MARK: - Load Pages

    private func loadPages() async {
        sessionStart = Date()

        let result: [String]
        if activeChapter.isDownloaded, let local = DownloadManager.shared.localPages(for: activeChapter) {
            result = local.urls.map(\.absoluteString)
            pageSources = local.sourcePages
        } else {
            let path = activeChapter.path
            let loaded = await Self.readerPages(bridge: bridge, path: path)
            result = loaded.pages
            pageSources = nil
            if loaded.fromCache { cachedListPaths.insert(path) }
        }
        pages = result
        isLoading = false
        if result.isEmpty {
            errorMessage = String(localized: "No pages found for this chapter.")
        } else {
            // Restore reading progress (prefer stored page number)
            // Downloaded chapters resume too (they always opened at page 1 before D12).
            let chapterId = activeChapter.id
            let pageCount = result.count
            let sources = pageSources
            Task.detached {
                if let saved = try? ChapterQueries.fetchOne(id: chapterId),
                   !saved.isRead, pageCount > 1 {
                    let resumePage: Int
                    if saved.lastPageRead > 0 {
                        resumePage = min(Self.localPage(forSource: saved.lastPageRead, in: sources), pageCount - 1)
                    } else if saved.progress > 0 {
                        resumePage = min(Int(saved.progress * Double(pageCount - 1)), pageCount - 1)
                    } else {
                        resumePage = 0
                    }
                    if resumePage > 0 {
                        await MainActor.run { currentPage = resumePage }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChapterReaderView(
        manga: Manga(
            id: "1", path: "/manga/berserk", sourceId: "com.yomi.test",
            title: "Berserk", coverURL: nil, summary: nil,
            author: "Kentaro Miura", artist: "Kentaro Miura",
            status: .hiatus, genres: [], inLibrary: true, isLocal: false,
            lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0
        ),
        bridge: {
            guard let url = Bundle.main.url(forResource: "test-source", withExtension: "js"),
                  let b = JSBridge(scriptURL: url) else {
                fatalError("test-source.js must be in the Debug target for Simulator previews")
            }
            return b
        }(),
        chapters: [],
        chapterIndex: 0
    )
}
