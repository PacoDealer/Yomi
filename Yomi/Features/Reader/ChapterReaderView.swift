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

// MARK: - MangaReaderView

struct MangaReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    var isRTL: Bool = true

    @State private var settings = AppSettings.shared
    @State private var viewportIsLandscape = false
    @State private var isZoomed = false
    @State private var viewSize: CGSize = .zero

    // MARK: - Double-page spreads
    //
    // "double"/"automatic" group pages into spreads (`PageSpreads`, F17: cover alone, wide pages alone, shapes must
    // match). currentPage keeps its normal meaning everywhere else (progress, resume, scrubber) — it's just an index
    // into `pages`. TabView only ever selects/produces spread-start indices via `spreadSelection`, a proxy binding
    // that snaps any raw page index down to the start of its enclosing spread. Groups change as page shapes are
    // learned; the page on screen stays on screen.

    private var isDoubleActive: Bool {
        switch settings.pageLayout {
        case "double":    return true
        case "automatic": return viewportIsLandscape
        default:          return false
        }
    }

    private var spreadGroups: [[Int]] {
        guard isDoubleActive, pages.count > 1 else { return pages.indices.map { [$0] } }
        _ = PageShapes.changes.count   // re-pair when a shape is learned
        return PageSpreads.groups(count: pages.count, aspect: { PageShapes.aspect(pages[$0]).map(Double.init) },
                                  coverAlone: settings.doublePageCoverAlone)
    }

    private func spreadStart(for page: Int) -> Int {
        spreadGroups.first(where: { $0.contains(page) })?.first ?? page
    }

    private var spreadSelection: Binding<Int> {
        Binding(
            get: { spreadStart(for: currentPage) },
            set: { currentPage = $0 }
        )
    }

    var body: some View {
        ZStack {
            TabView(selection: spreadSelection) {
                ForEach(spreadGroups, id: \.self) { group in
                    spreadContent(group)
                        .tag(group.first!)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(isZoomed)   // zoomed in: one finger pans the page instead of turning it
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .ignoresSafeArea()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportIsLandscape = geo.size.width > geo.size.height }
                        .onChange(of: geo.size) { _, newSize in
                            viewportIsLandscape = newSize.width > newSize.height
                        }
                }
            }

        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onTapGesture(coordinateSpace: .local) { handleTap(at: $0, in: viewSize) }
        .onChange(of: currentPage) { _, _ in isZoomed = false }
        // Shapes of downloaded pages (and web pages already cached) before they're reached, so spreads pair right.
        .task(id: isDoubleActive ? pages : []) { if isDoubleActive { await PageShapes.learn(pages) } }
    }

    @ViewBuilder
    private func spreadContent(_ group: [Int]) -> some View {
        if group.count == 2 {
            // "Invert double pages" (L3c): the pair swaps sides; reading order (and `currentPage`) stays the same.
            let (first, second) = settings.doublePageInvert ? (group[1], group[0]) : (group[0], group[1])
            HStack(spacing: 0) {
                MangaPageView(url: pages[first], isZoomed: $isZoomed).readerPageMenu(url: pages[first])
                MangaPageView(url: pages[second], isZoomed: $isZoomed).readerPageMenu(url: pages[second])
            }
        } else {
            MangaPageView(url: pages[group[0]], isZoomed: $isZoomed).readerPageMenu(url: pages[group[0]])
        }
    }

    // MARK: - Tap zone actions
    //
    // Moves by a whole spread (1 or 2 pages) so it always lands on a valid TabView tag.

    private func moveSpread(forward: Bool) {
        let groups = spreadGroups
        guard let idx = groups.firstIndex(where: { $0.first == spreadStart(for: currentPage) }) else { return }
        let targetIdx = forward ? min(idx + 1, groups.count - 1) : max(idx - 1, 0)
        let next = groups[targetIdx].first!
        if next != currentPage {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withMotion(.easeInOut(duration: 0.3)) { currentPage = next }   // slide, like novel Pages mode
        }
    }

    private func tapMenu() {
        withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
    }

    // MARK: - Tap zones
    //
    // Resolved from the tap location instead of an overlay of tap views: an overlay sits on top of
    // the pages and swallows pinch + swipe (#200 — pinch never worked on device). Geometry: `ReaderTapZones.paged`.

    private func handleTap(at p: CGPoint, in size: CGSize) {
        // Zoomed in: a tap zooms back out rather than turning the page under your finger.
        if isZoomed { withMotion(.spring(duration: 0.3)) { isZoomed = false }; return }
        switch ReaderTapZones.paged(settings.tapZoneLayout, at: p, in: size, isRTL: isRTL) {
        case .back:    moveSpread(forward: false)
        case .forward: moveSpread(forward: true)
        case .menu:    tapMenu()
        }
    }
}

// MARK: - MangaPageView (single page with pinch-to-zoom; tap zooms back out)

private struct MangaPageView: View {
    let url: String
    /// Shared with the reader: true while this page is pinched in (TabView paging is off); the reader sets it
    /// back to false on a tap or a page change, which zooms the page out.
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadFailed = false
    @State private var attempt = 0
    @State private var settings = AppSettings.shared
    /// Margins + background colour (F17), from `PageLooks`; nil until the page has been measured.
    @State private var look: PageLook?
    /// Loaded and being measured: hidden for that moment when cropping, so the margins don't flash before the crop.
    @State private var measuring = false
    /// Shows the page again (from cache) so a setting turned on mid-chapter measures the page on screen.
    @State private var reload = 0

    var body: some View {
        GeometryReader { geo in
            // KFImage, not AsyncImage: page hosts behind Cloudflare (e.g. AquaManga) need the same
            // UA-matching requestModifier YomiApp.swift registers globally on KingfisherManager —
            // AsyncImage uses a bare URLSession with no way to attach that, so it 403s silently.
            Group {
                if loadFailed {
                    PageRetryButton { attempt = 0; loadFailed = false }
                } else {
                    KFImage(source: PageNames.source(url))
                        .readerPage()
                        .placeholder {
                            ProgressView()
                                .tint(ReaderBackdrop.isLight(settings.readerBackground) ? .black : .white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .onSuccess { result in
                            let size = result.image.size
                            if size.height > 0 { PageShapes.remember(url, size.width / size.height) }
                            guard look == nil, settings.cropBorders || settings.readerBackground == "automatic" else { return }
                            let page = url
                            measuring = true
                            Task {
                                let measured = await PageLooks.look(for: page, image: result.image)
                                if page == url { look = measured }
                                measuring = false
                            }
                        }
                        .onFailure { _ in
                            Task {
                                if await PageRetry.shouldRetry(url, attempt: attempt) { attempt += 1 } else { loadFailed = true }
                            }
                        }
                        .resizable()
                        .modifier(PageCrop(crop: settings.cropBorders ? look?.crop : nil, aspect: PageShapes.aspect(url)))
                        .opacity(settings.cropBorders && measuring ? 0 : 1)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id("\(attempt)-\(reload)")
            .onChange(of: url) { _, new in loadFailed = false; attempt = 0; look = PageLooks.cached(new) }
            .onChange(of: settings.cropBorders) { if look == nil { reload += 1 } }
            .onChange(of: settings.readerBackground) { if look == nil { reload += 1 } }
            .onAppear { if look == nil { look = PageLooks.cached(url) } }
            .background { pageBackground(landscape: geo.size.width > geo.size.height) }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 1.0), 4.0)
                        // Zoom around the fingers, not the page centre: keep the content point that was under the
                        // pinch's start location under it. Position on screen = centre + point * scale + offset.
                        let f = CGPoint(x: value.startLocation.x - geo.size.width / 2,
                                        y: value.startLocation.y - geo.size.height / 2)
                        let px = (f.x - lastOffset.width) / lastScale, py = (f.y - lastOffset.height) / lastScale
                        offset = clamped(CGSize(width: f.x - px * scale, height: f.y - py * scale), in: geo.size)
                        if scale > 1.0, !isZoomed { isZoomed = true }
                    }
                    .onEnded { _ in
                        lastScale = scale
                        lastOffset = offset
                        if scale <= 1.0 { resetZoom() }
                    },
                including: settings.readerPinchZoom ? .all : .subviews
            )
            // Pan only while zoomed: a drag gesture on the page at 1x steals the page swipe from the TabView.
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = clamped(CGSize(width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height), in: geo.size)
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    },
                including: isZoomed ? .all : .subviews
            )
            .onChange(of: isZoomed) { _, zoomed in
                if !zoomed { withMotion(.spring(duration: 0.3)) { resetZoom() } }
            }
        }
    }

    /// The reader's background colour; "Automatic" uses the page's own margins once it has been measured (F17).
    @ViewBuilder private func pageBackground(landscape: Bool) -> some View {
        if settings.readerBackground == "automatic", let look {
            ReaderBackdrop.view(landscape ? look.landscape : look.portrait)
        } else {
            ReaderBackdrop.base(settings.readerBackground)
        }
    }

    /// Keeps the zoomed page covering the screen: no panning past its edges.
    private func clamped(_ o: CGSize, in size: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2, maxY = (scale - 1) * size.height / 2
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    private func resetZoom() {
        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
        isZoomed = false
    }
}

// MARK: - WebtoonReaderView

struct WebtoonReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    var nextChapter: Chapter? = nil
    var nextPages: [String] = []
    var boundaryTitles: (finished: String, next: String)? = nil
    var onNeedsNextChapterPreload: (() -> Void)? = nil
    var onCrossedIntoNextChapter: ((Int) -> Void)? = nil

    @State private var visibleId: String? = nil
    @State private var isAutoScrolling = false
    @State private var settings = AppSettings.shared
    @State private var scroller = StripScroller()
    /// Last page the strip reported, from either source (`scrollPosition` or visibility) — reported once.
    @State private var observedId: String? = nil
    @State private var viewSize: CGSize = .zero
    @GestureState private var isHolding = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: settings.readerScrollIndicator) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                        pageImage(url)
                            .id("cur:\(index)")
                    }
                    if let boundaryTitles {
                        ChapterBoundaryCard(finishedTitle: boundaryTitles.finished, nextTitle: boundaryTitles.next, axis: .vertical)
                            .id("boundary")
                        ForEach(Array(nextPages.enumerated()), id: \.offset) { index, url in
                            pageImage(url)
                                .id("next:\(index)")
                        }
                    }
                }
                .padding(.horizontal, CGFloat(settings.webtoonHorizontalPadding))
                .scrollTargetLayout()
                .background(EnclosingScrollViewFinder { scroller.scrollView = $0 })
            }
            .scrollPosition(id: $visibleId, anchor: .top)
            // `scrollPosition(id:)` only follows the reader's own finger; tap zones and scroll-while-held move the
            // scroll view in code and it never updates (F16, sim). Visibility does — used only then: at rest a sliver
            // of the previous page under the status bar counts as visible, one page before the `.top` anchor's.
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { ids in
                guard scroller.isDriving else { return }
                func top(_ prefix: String) -> Int? {
                    ids.compactMap { $0.hasPrefix(prefix) ? Int($0.dropFirst(prefix.count)) : nil }.min()
                }
                if let page = top("cur:") { observe("cur:\(page)") } else if let page = top("next:") { observe("next:\(page)") }
            }
            .onAppear {
                if currentPage > 0 {
                    proxy.scrollTo("cur:\(currentPage)", anchor: .top)
                }
            }
            .onChange(of: visibleId) { _, id in
                if let id { observe(id) }
            }
            .onChange(of: pages) { observedId = nil }   // a new chapter's "cur:N" is a different page
            .onChange(of: currentPage) { _, new in
                // Two-way sync with the overlay's progress slider — scrolling
                // updates currentPage above, this reflects slider drags back
                // into the scroll position. Guarded so it's a no-op when the
                // change originated from the scroll itself.
                let newId = "cur:\(new)"
                guard newId != visibleId, newId != observedId else { return }
                withMotion { proxy.scrollTo(newId, anchor: .top) }
            }
        }
        .modifier(ReaderZoom(scrollAxis: .vertical, pinchEnabled: settings.readerPinchZoom && !isHolding))
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onTapGesture(coordinateSpace: .local) { p in
            switch ReaderTapZones.strip(settings.stripTapZoneLayout, at: p, in: viewSize) {
            case .back:    scroller.page(by: -0.75)
            case .forward: scroller.page(by: 0.75)
            case .menu:    withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            }
        }
        // Long press (F16): auto-scroll on/off (the pre-F16 behaviour, default) · scroll while held · page menu
        // (on each page, see `pageImage`). Only the chosen gesture is live.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in
                    withMotion(.easeInOut(duration: 0.2)) { isAutoScrolling.toggle() }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                },
            including: settings.stripLongPress == "autoScroll" ? .all : .subviews
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($isHolding) { value, state, _ in
                    if case .second(true, _) = value { state = true }
                },
            including: settings.stripLongPress == "hold" ? .all : .subviews
        )
        .onChange(of: isHolding) { _, holding in
            if holding { scroller.startHold() } else { scroller.stopHold() }
        }
        .overlay(alignment: .bottom) {
            if isAutoScrolling {
                Label("Auto-scroll", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 60)
                    .transition(Motion.pop)
            }
        }
        .motion(.easeInOut(duration: 0.2), value: isAutoScrolling)
        .task(id: isAutoScrolling) {
            guard isAutoScrolling else { return }
            while !Task.isCancelled && isAutoScrolling {
                try? await Task.sleep(for: .milliseconds(Int(settings.autoScrollSpeed * 1000)))
                guard !Task.isCancelled && isAutoScrolling else { break }
                guard let cur = visibleId, cur.hasPrefix("cur:"), let idx = Int(cur.dropFirst(4)) else { break }
                let nextIdx = idx + 1
                guard nextIdx < pages.count else { isAutoScrolling = false; break }
                visibleId = "cur:\(nextIdx)"
            }
        }
        .onDisappear { isAutoScrolling = false; scroller.stopHold() }
    }

    private func observe(_ id: String) {
        guard id != observedId else { return }
        observedId = id
        if id.hasPrefix("cur:"), let idx = Int(id.dropFirst(4)) {
            currentPage = idx
            if nextChapter == nil, pages.count > 0, idx >= pages.count - 3 {
                onNeedsNextChapterPreload?()
            }
        } else if id.hasPrefix("next:"), let idx = Int(id.dropFirst(5)) {
            onCrossedIntoNextChapter?(idx)
        }
    }

    private func pageImage(_ url: String) -> some View {
        StripPageImage(url: url, axis: .vertical)
            .readerPageMenu(url: url, enabled: settings.stripLongPress == "pageMenu")
    }
}

// MARK: - ChapterBoundaryCard
//
// The Tachimanga-style mid-scroll transition marker: rendered directly inside the reader's
// scroll content (not a floating overlay) so continuous/webtoon reading flows straight from one
// chapter into the next with no tap.

struct ChapterBoundaryCard: View {
    let finishedTitle: String
    let nextTitle: String
    enum Axis { case vertical, horizontal }
    var axis: Axis = .vertical

    var body: some View {
        Group {
            switch axis {
            case .vertical:
                content.frame(maxWidth: .infinity).padding(.vertical, 40)
            case .horizontal:
                content.frame(width: 220).frame(maxHeight: .infinity)
            }
        }
        .background(Color.black)
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Finished: \(finishedTitle)")
                    .font(YomiTokens.Font.mono(12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 1)

            Text("Current: \(nextTitle)")
                .font(YomiTokens.Font.grotesk(17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - ReaderZoom
//
// Pinch-zoom for the scrolling modes (webtoon, continuous; #200). The whole scroll view is scaled, so scrolling keeps
// working while zoomed; the pinch anchors at the fingers (Martin S149: zoom wherever you want), one finger pans across
// the scroll direction, a tap zooms back out.

struct ReaderZoom: ViewModifier {
    let scrollAxis: Axis
    /// Off: no pinch (Settings → Pinch to zoom, or long strip while a finger holds it scrolling — L3c).
    var pinchEnabled = true

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var size: CGSize = .zero

    private var isZoomed: Bool { scale > 1.01 }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 1), 4)
                        // Keep the point that was under the fingers under them: screen = centre + point * scale + offset.
                        let fx = value.startLocation.x - size.width / 2, fy = value.startLocation.y - size.height / 2
                        let px = (fx - lastOffset.width) / lastScale, py = (fy - lastOffset.height) / lastScale
                        offset = clamped(CGSize(width: fx - px * scale, height: fy - py * scale))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        lastOffset = offset
                        if !isZoomed { reset() }
                    },
                including: pinchEnabled ? .all : .subviews
            )
            // Across the scroll direction only; along it, the scroll view itself moves.
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        var o = lastOffset
                        if scrollAxis == .vertical { o.width += value.translation.width } else { o.height += value.translation.height }
                        offset = clamped(o)
                    }
                    .onEnded { _ in lastOffset = offset },
                including: isZoomed ? .all : .subviews
            )
            .gesture(TapGesture().onEnded { withMotion(.spring(duration: 0.3)) { reset() } },
                     including: isZoomed ? .all : .subviews)
    }

    private func clamped(_ o: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2, maxY = (scale - 1) * size.height / 2
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

// MARK: - ContinuousHorizontalReaderView

struct ContinuousHorizontalReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    var isRTL: Bool = false
    var nextChapter: Chapter? = nil
    var nextPages: [String] = []
    var boundaryTitles: (finished: String, next: String)? = nil
    var onNeedsNextChapterPreload: (() -> Void)? = nil
    var onCrossedIntoNextChapter: ((Int) -> Void)? = nil

    @State private var visibleId: String? = nil
    @State private var settings = AppSettings.shared
    @State private var viewSize: CGSize = .zero

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: settings.readerScrollIndicator) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                        pageImage(url)
                            .id("cur:\(index)")
                    }
                    if let boundaryTitles {
                        ChapterBoundaryCard(finishedTitle: boundaryTitles.finished, nextTitle: boundaryTitles.next, axis: .horizontal)
                            .id("boundary")
                        ForEach(Array(nextPages.enumerated()), id: \.offset) { index, url in
                            pageImage(url)
                                .id("next:\(index)")
                        }
                    }
                }
                .scrollTargetLayout()
            }
            // RTL on the ScrollView itself, not just its stack: with only the stack flipped the scroll view
            // still starts at its left edge = the LAST page (#198).
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .scrollPosition(id: $visibleId, anchor: .center)
            .onAppear {
                if currentPage > 0 {
                    visibleId = "cur:\(currentPage)"
                }
            }
            .onChange(of: visibleId) { _, id in
                guard let id else { return }
                if id.hasPrefix("cur:"), let idx = Int(id.dropFirst(4)) {
                    currentPage = idx
                    if nextChapter == nil, pages.count > 0, idx >= pages.count - 3 {
                        onNeedsNextChapterPreload?()
                    }
                } else if id.hasPrefix("next:"), let idx = Int(id.dropFirst(5)) {
                    onCrossedIntoNextChapter?(idx)
                }
            }
            .onChange(of: currentPage) { _, new in
                let newId = "cur:\(new)"
                guard newId != visibleId else { return }
                withMotion { proxy.scrollTo(newId, anchor: .center) }
            }
        }
        .modifier(ReaderZoom(scrollAxis: .horizontal, pinchEnabled: settings.readerPinchZoom))
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        // One page per screen, so tap zones step a page (strip zones, F16); the scroll follows `currentPage`.
        .onTapGesture(coordinateSpace: .local) { p in
            switch ReaderTapZones.strip(settings.stripTapZoneLayout, at: p, in: viewSize, isRTL: isRTL) {
            case .back:    step(-1)
            case .forward: step(1)
            case .menu:    withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            }
        }
    }

    private func step(_ delta: Int) {
        let target = min(max(currentPage + delta, 0), pages.count - 1)
        guard target != currentPage else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        currentPage = target
    }

    private func pageImage(_ url: String) -> some View {
        // Fit each page inside the screen. Height-only fit made a portrait page ~1.5x wider than a phone, so
        // the sides were cut off (#199).
        StripPageImage(url: url, axis: .horizontal)
            .readerPageMenu(url: url)
            .containerRelativeFrame([.horizontal, .vertical])
    }
}

// MARK: - VerticalPagedReaderView

struct VerticalPagedReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    @State private var isZoomed = false
    @State private var settings = AppSettings.shared
    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                    MangaPageView(url: url, isZoomed: $isZoomed)
                        .readerPageMenu(url: url)
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(-90))
                        .tag(index)
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90))
            .frame(width: geo.size.width, height: geo.size.height)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(isZoomed)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        // Paged tap zones here too (F16; before, every tap only showed the menu). Left side = previous page.
        .onTapGesture(coordinateSpace: .local) { p in
            if isZoomed { isZoomed = false; return }
            switch ReaderTapZones.paged(settings.tapZoneLayout, at: p, in: viewSize, isRTL: false) {
            case .back:    step(-1)
            case .forward: step(1)
            case .menu:    withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            }
        }
        .onChange(of: currentPage) { _, _ in isZoomed = false }
    }

    private func step(_ delta: Int) {
        let target = min(max(currentPage + delta, 0), pages.count - 1)
        guard target != currentPage else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withMotion(.easeInOut(duration: 0.3)) { currentPage = target }
    }
}

// MARK: - ReaderOverlayView

struct ReaderOverlayView: View {
    let manga: Manga
    let chapter: Chapter
    let currentChapterIndex: Int
    let chapters: [Chapter]
    @Binding var currentPage: Int
    let totalPages: Int
    @Binding var readerMode: ReaderMode
    @Binding var showOverlay: Bool
    let showPageNumber: Bool
    let discussURL: URL?
    let sourceURL: URL?
    let hasPrevChapter: Bool
    let hasNextChapter: Bool
    let onDismiss: () -> Void
    let onDiscuss: () -> Void
    let onViewSource: () -> Void
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    var onJumpToChapter: ((Int) -> Void)? = nil
    /// Custom toolbar (L3c): bookmark + mark-previous quick actions, and the page on screen for Share page.
    var isBookmarked = false
    var onToggleBookmark: (() -> Void)? = nil
    var onMarkPreviousRead: (() -> Void)? = nil
    var currentPageURL: String? = nil

    @State private var showChapterSheet = false
    @State private var showSettingsSheet = false
    @State private var showMarkPreviousConfirm = false
    @State private var shareImage: UIImage? = nil
    @State private var pageTextImage: UIImage? = nil
    @State private var settings = AppSettings.shared

    private var isStripMode: Bool {
        switch readerMode {
        case .verticalScroll, .continuousRTL, .continuousLTR: true
        default: false
        }
    }

    @ViewBuilder private var readingModeOptions: some View {
        Label("Right to left", systemImage: "book.pages").tag(ReaderMode.horizontalRTL)
        Label("Left to right", systemImage: "book.pages.fill").tag(ReaderMode.horizontalLTR)
        Label("Paged (vertical)", systemImage: "square.stack").tag(ReaderMode.verticalPaged)
        Label("Continuous (right to left)", systemImage: "arrow.left").tag(ReaderMode.continuousRTL)
        Label("Continuous (left to right)", systemImage: "arrow.right").tag(ReaderMode.continuousLTR)
        Label("Webtoon", systemImage: "scroll").tag(ReaderMode.verticalScroll)
    }

    @ViewBuilder private var spreadOptions: some View {
        Text("Off").tag("single")
        Text("Always").tag("double")
        Text("In landscape").tag("automatic")
    }

    /// Crop borders is two settings (paged / strip, F17) — the button flips the one for the mode being read.
    private var cropBinding: Binding<Bool> {
        isStripMode ? $settings.cropBordersStrip : $settings.cropBorders
    }

    // MARK: - Custom toolbar (L3c)

    /// The saved buttons minus those that don't apply right now (spreads outside the paged modes, comments the source
    /// doesn't have, Share before a page has loaded).
    private var toolbarItems: [ReaderToolbarItem] {
        ReaderToolbarItem.current(settings).filter { item in
            switch item {
            case .spreads:   readerMode == .horizontalRTL || readerMode == .horizontalLTR
            case .comments:  discussURL != nil
            case .sharePage, .pageText: currentPageURL != nil
            default:         true
            }
        }
    }

    @ViewBuilder private func toolbarButton(_ item: ReaderToolbarItem) -> some View {
        switch item {
        case .previousChapter:
            Button(action: onPrevChapter) { toolbarIcon(item.systemImage, dimmed: !hasPrevChapter) }
                .disabled(!hasPrevChapter)
                .accessibilityLabel(item.title)
        case .nextChapter:
            Button(action: onNextChapter) { toolbarIcon(item.systemImage, dimmed: !hasNextChapter) }
                .disabled(!hasNextChapter)
                .accessibilityLabel(item.title)
        case .bookmark:
            Button { onToggleBookmark?() } label: {
                toolbarIcon(isBookmarked ? "bookmark.fill" : "bookmark", tinted: isBookmarked)
            }
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark chapter")
        case .markPreviousRead:
            Button {
                if unreadBefore == 0 { onMarkPreviousRead?() } else { showMarkPreviousConfirm = true }
            } label: {
                toolbarIcon(item.systemImage, dimmed: currentChapterIndex == 0)
            }
            .disabled(currentChapterIndex == 0)
            .accessibilityLabel(item.title)
        case .readingMode:
            Menu {
                Picker("Reading mode", selection: $readerMode) { readingModeOptions }
            } label: { toolbarIcon(item.systemImage) }
            .accessibilityLabel(item.title)
        case .spreads:
            Menu {
                Picker("Two-page spreads", selection: $settings.pageLayout) { spreadOptions }
            } label: { toolbarIcon(item.systemImage, tinted: settings.pageLayout != "single") }
            .accessibilityLabel(item.title)
        case .cropBorders:
            Button { cropBinding.wrappedValue.toggle() } label: {
                toolbarIcon(item.systemImage, tinted: cropBinding.wrappedValue)
            }
            .accessibilityLabel(item.title)
            .accessibilityValue(cropBinding.wrappedValue ? "On" : "Off")
        case .sharePage:
            Button {
                guard let url = currentPageURL else { return }
                Task {
                    if let image = await ReaderPageActions.image(for: url) { shareImage = image }
                    else { ReaderPageActions.say(String(localized: "The page isn't loaded yet")) }
                }
            } label: { toolbarIcon(item.systemImage) }
            .accessibilityLabel(item.title)
        case .pageText:
            Button {
                guard let url = currentPageURL else { return }
                Task {
                    if let image = await ReaderPageActions.image(for: url) { pageTextImage = image }
                    else { ReaderPageActions.say(String(localized: "The page isn't loaded yet")) }
                }
            } label: { toolbarIcon(item.systemImage) }
            .accessibilityLabel(item.title)
        case .comments:
            Button(action: onDiscuss) { toolbarIcon(item.systemImage) }
                .accessibilityLabel(item.title)
        }
    }

    /// Unread chapters before this one — what "Mark previous as read" would change.
    private var unreadBefore: Int {
        chapters.prefix(currentChapterIndex).filter { !$0.isRead }.count
    }

    private func toolbarIcon(_ name: String, dimmed: Bool = false, tinted: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 17))
            .foregroundStyle(tinted ? Color.accentColor : Color.primary.opacity(dimmed ? 0.3 : 1))
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
    }

    /// Same settings as More → Settings → Manga & Webtoon, for the mode being read (F16).
    @ViewBuilder private var gesturesSection: some View {
        switch readerMode {
        case .verticalScroll, .continuousRTL, .continuousLTR:
            Section("Gestures") {
                Picker("Tap zones", selection: $settings.stripTapZoneLayout) {
                    Text("Off").tag("disabled")
                    Text("L-shaped").tag("lShaped")
                    Text("Top and bottom").tag("topBottom")
                }
                if readerMode == .verticalScroll {
                    Picker("Long press", selection: $settings.stripLongPress) {
                        Text("Auto-scroll").tag("autoScroll")
                        Text("Scroll while held").tag("hold")
                        Text("Share or save").tag("pageMenu")
                    }
                }
            }
        default:
            Section {
                Picker("Tap zones", selection: $settings.tapZoneLayout) {
                    Text("Thirds").tag("default")
                    Text("Edges").tag("sides")
                    Text("L-shaped").tag("lShaped")
                    Text("Kindle").tag("kindle")
                    Text("Left and right halves").tag("rightLeft")
                    Text("Off").tag("disabled")
                }
            } header: { Text("Gestures") } footer: { Text("Hold a page to share or save it.") }
        }
    }

    /// F17: spreads, crop borders and background for the mode being read (same settings as Manga & Webtoon).
    @ViewBuilder private var pagesSection: some View {
        Section("Pages") {
            switch readerMode {
            case .verticalScroll, .continuousRTL, .continuousLTR:
                Toggle("Crop borders", isOn: $settings.cropBordersStrip)
                Toggle("Scroll bar", isOn: $settings.readerScrollIndicator)
            case .horizontalRTL, .horizontalLTR:
                Picker("Two-page spreads", selection: $settings.pageLayout) { spreadOptions }
                if settings.pageLayout != "single" {
                    Toggle("Cover on its own", isOn: $settings.doublePageCoverAlone)
                    Toggle("Swap the two pages", isOn: $settings.doublePageInvert)
                }
                Toggle("Crop borders", isOn: $settings.cropBorders)
            default:
                Toggle("Crop borders", isOn: $settings.cropBorders)
            }
            Toggle("Pinch to zoom", isOn: $settings.readerPinchZoom)
            ReaderBackgroundPicker(selection: $settings.readerBackground)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — individual floating Liquid Glass chips
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                }
                .glassChip()
                .accessibilityLabel("Close reader")

                VStack(alignment: .leading, spacing: 2) {
                    Text(manga.title)
                        .font(YomiTokens.Font.grotesk(15, weight: .medium))
                        .lineLimit(1)
                    Text(chapter.name)
                        .font(YomiTokens.Font.mono(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .shadow(color: .black.opacity(0.5), radius: 6)
                .frame(maxWidth: .infinity, alignment: .leading)

                if !chapters.isEmpty {
                    Button {
                        showChapterSheet = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 17))
                    }
                    .glassChip()
                    .accessibilityLabel("Chapters")
                }

                if sourceURL != nil {
                    Button(action: onViewSource) {
                        Image(systemName: "globe")
                            .font(.system(size: 17))
                    }
                    .glassChip()
                    .accessibilityLabel("Open on source website")
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17))
                }
                .glassChip()
                .accessibilityLabel("Reader settings")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .sheet(isPresented: $showChapterSheet) {
                let target = currentChapterIndex
                NavigationStack {
                    ScrollViewReader { proxy in
                        List(chapters.indices, id: \.self) { idx in
                            let ch = chapters[idx]
                            Button {
                                showChapterSheet = false
                                onJumpToChapter?(idx)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.name)
                                            .font(.subheadline)
                                            .foregroundStyle(idx == target ? Color.accentColor : .primary)
                                            .fontWeight(idx == target ? .semibold : .regular)
                                        if ch.isRead {
                                            Text("Read")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        } else if ch.lastPageRead > 0 {
                                            Text("Page \(ch.lastPageRead + 1)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if idx == target {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .id(idx)
                        }
                        .navigationTitle("Chapters")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showChapterSheet = false }
                            }
                        }
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(100))
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettingsSheet) {
                NavigationStack {
                    Form {
                        Section("Reading mode") {
                            Picker("Mode", selection: $readerMode) { readingModeOptions }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                        gesturesSection
                        pagesSection
                        Section {
                            NavigationLink("Toolbar") { ReaderToolbarEditor() }
                        } footer: { Text("Pick the buttons in the bar at the bottom of the reader.") }
                    }
                    .navigationTitle("Reader Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettingsSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }

            Spacer()

            // Bottom bar — floating Liquid Glass card
            VStack(spacing: 14) {
                HStack {
                    if let num = chapter.chapterNumber {
                        Text(Notation.pagePosition(chapter: num, page: currentPage + 1, total: totalPages))
                    } else {
                        Text("\(currentPage + 1)/\(totalPages)")
                    }
                    Spacer()
                    // Up to three buttons sit next to the page count (the pre-L3c bar = previous + next).
                    if toolbarItems.count <= 3 {
                        HStack(spacing: 18) {
                            ForEach(toolbarItems) { toolbarButton($0) }
                        }
                    }
                }
                .font(YomiTokens.Font.mono(12))
                .foregroundStyle(.secondary)

                // More than three get a row of their own, spread across the bar.
                if toolbarItems.count > 3 {
                    HStack(spacing: 0) {
                        ForEach(toolbarItems) { toolbarButton($0).frame(maxWidth: .infinity) }
                    }
                }

                if showPageNumber && totalPages > 1 {
                    HStack(spacing: 10) {
                        Text("\(currentPage + 1)")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(.secondary)

                        YomiScrubber(
                            value: Binding(
                                get: { Double(currentPage) },
                                set: { currentPage = Int($0.rounded()) }
                            ),
                            range: 0...Double(totalPages - 1),
                            accessibilityLabelText: "Page",
                            accessibilityValueText: { String(localized: "Page \(Int($0.rounded()) + 1) of \(totalPages)") }
                        )

                        Text("\(totalPages)")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .opacity(showOverlay ? 1 : 0)
        .motion(.easeInOut(duration: 0.2), value: showOverlay)
        .confirmationDialog("Mark previous as read", isPresented: $showMarkPreviousConfirm, titleVisibility: .hidden) {
            Button("Mark as Read") { onMarkPreviousRead?() }
        } message: {
            Text(unreadBefore == 1 ? "1 unread chapter before this one will be marked as read."
                                   : "\(unreadBefore) unread chapters before this one will be marked as read.")
        }
        .pageTextSheet($pageTextImage)
        .sheet(isPresented: Binding(get: { shareImage != nil }, set: { if !$0 { shareImage = nil } })) {
            if let shareImage {
                ActivityView(items: [shareImage])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - DiscussWebSheet

import WebKit

struct DiscussWebSheet: View {
    let url: URL
    var title: String = String(localized: "Discussion")
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {}
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

// MARK: - Page load retry (S144)

/// After a page fails to load: a Keiyoushi page waits until the bridge serves again (it stops while Yomi is in the
/// background and comes back on a new port — Martin: "the first page appeared and the rest did not load"), any
/// other page gets a short pause for a network blip. Then it's tried again, up to 3 times, before showing Retry.
enum PageRetry {
    /// Posted with the page URL on a page's first failure; the reader refetches the list if it came from the cache.
    static let pageFailed = Notification.Name("YomiReaderPageFailed")

    static func shouldRetry(_ url: String, attempt: Int) async -> Bool {
        guard attempt < 3 else { return false }
        if attempt == 0 { NotificationCenter.default.post(name: pageFailed, object: url) }
        // Not while Yomi is in the background: iOS suspends us there, and the attempts would be used up for nothing.
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(500))
        }
        if KeiyoushiBridge.isBridgeImage(URL(string: url)) {
            return (try? await KeiyoushiBridge.shared.servingPort()) != nil
        }
        try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        return true
    }
}

/// A page that gave up: tap to load it again.
private struct PageRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                Text("Page didn't load · Tap to retry")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


/// One page in the long strip / continuous horizontal readers. Used to stay a grey placeholder forever on failure.
/// Loads through KingfisherManager itself instead of KFImage (S145): a very tall page must never reach the screen
/// in one piece, and KFImage could show it without calling `onSuccess`, so the strips weren't always made.
private struct StripPageImage: View {
    let url: String
    let axis: Axis
    @State private var attempt = 0
    @State private var failed = false
    @State private var pieces: [UIImage]? = nil
    @State private var settings = AppSettings.shared

    var body: some View {
        page.onChange(of: url) { pieces = nil; failed = false; attempt = 0 }
            .onChange(of: settings.cropBordersStrip) { pieces = nil }   // load again, cut (or not)
    }

    /// The crop this page is drawn with (F17, long strip + continuous), when known.
    private var crop: CGRect? { settings.cropBordersStrip ? PageLooks.cached(url)?.crop : nil }

    @ViewBuilder private var page: some View {
        if failed {
            PageRetryButton { attempt = 0; failed = false }
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
        } else if let pieces {
            let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(pieces.indices, id: \.self) { i in
                    Image(uiImage: pieces[i])
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
            // A decoded 900x16000 Asura page is ~57 MB and the lazy stack kept every page it had built until the
            // reader closed (S160, sim: 20 pages took the app from 908 MB to 1,964 MB). Let go of it off screen; the
            // placeholder keeps the page's size and the page loads again from cache on the way back.
            .onDisappear { self.pieces = nil }
        } else {
            placeholder
                .task(id: LoadKey(url: url, attempt: attempt, crop: settings.cropBordersStrip)) { await load() }
        }
    }

    /// A refetched list (D12b) gives the same slot a new URL: start that page over. Done here and NOT with `.id(url)`
    /// on the page: a second id inside the strip's `cur:N` id hid it from `scrollPosition`, so the current page
    /// never changed while scrolling (found S168 — counter stuck, saved position too).
    private struct LoadKey: Equatable { let url: String; let attempt: Int; let crop: Bool }

    /// The lazy stack throws a page's state away once it is far off screen, so scrolling back meets a placeholder
    /// again. It must be exactly as big as the page was, or everything below it jumps (a long-strip page is ~10x
    /// taller than the old 2:3 box: pages seemed to skip, and scrolling up fought back — Martin, S151).
    @ViewBuilder private var placeholder: some View {
        let box = Rectangle().fill(Color.gray.opacity(0.2))
        if let aspect = PageShapes.aspect(url) {
            // The page as it will be drawn, cropped or not.
            box.aspectRatio(crop.map { aspect * $0.width / $0.height } ?? aspect, contentMode: .fit)
                .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
        } else if axis == .vertical {
            // Never seen: a full screen, so a flick can't pass several unloaded pages that then grow behind you.
            box.containerRelativeFrame(.vertical)
                .frame(maxWidth: .infinity)
                .overlay { ProgressView().tint(.white) }
        } else {
            box.aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxHeight: .infinity)
        }
    }

    private func load() async {
        guard let source = PageNames.source(url) else { failed = true; return }
        do {
            let result = try await KingfisherManager.shared.retrieveImage(with: source, options: KFImage.readerPageOptions)
            var image = result.image
            if image.size.height > 0 { PageShapes.remember(url, image.size.width / image.size.height) }
            if settings.cropBordersStrip, let rect = await PageLooks.look(for: url, image: image).crop, let cg = image.cgImage {
                let source = image
                image = await Task.detached(priority: .userInitiated) {
                    UIImage(cgImage: cg.cropped(to: rect), scale: source.scale, orientation: source.imageOrientation)
                }.value
            }
            let vertical = axis == .vertical
            let page = image
            let cut = await Task.detached(priority: .userInitiated) { vertical ? Self.strips(of: page) : nil }.value
            if Task.isCancelled { return }
            pieces = cut ?? [image]
        } catch {
            if Task.isCancelled { return }   // scrolled away; .task starts again when the page comes back
            if await PageRetry.shouldRetry(url, attempt: attempt) { attempt += 1 } else { failed = true }
        }
    }

    /// A very tall page drawn as one view is taller than the GPU can draw and shows up BLACK (S145: Keiyoushi's
    /// Asura extension stitches each chapter part into one 900x16000 image = 21,000+ px on screen). Cut it into
    /// strips. Each strip is drawn into its own bitmap: a plain `cropping` crop of an ImageIO-backed page made
    /// ImageIO decode every strip AGAIN into buffers of its own that outlived the views (S160: 20 pages = 1.3 GB
    /// of ImageIO memory). Copied strips are freed with the view; the source page is left to Kingfisher's cache.
    nonisolated static func strips(of image: UIImage) -> [UIImage]? {
        guard let cg = image.cgImage, cg.height > 4096 else { return nil }
        let step = 2048
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return stride(from: 0, to: cg.height, by: step).compactMap { y in
            let height = min(step, cg.height - y)
            guard let crop = cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: height)),
                  let context = CGContext(data: nil, width: cg.width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: cg.width, height: height))
            return context.makeImage().map { UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation) }
        }
    }
}
