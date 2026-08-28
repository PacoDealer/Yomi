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

    @State private var settings = AppSettings.shared
    @State private var shouldRequestReview = false
    @State private var currentChapterIndex: Int
    @State private var pages: [String] = []
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
    @State private var nextPreload: (chapter: Chapter, pages: [String])? = nil
    @State private var isPreloadingNextChapter = false
    @State private var didUpdateTrackerForCurrentChapter = false

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
            Color.black.ignoresSafeArea()

            // Tap-to-hide chrome — sits behind all reader content so
            // scroll/pinch gestures on the reader views still take priority.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showOverlay.toggle() }

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.white)
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
                chapters: chapters,
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
                onJumpToChapter: { navigateToChapter($0) }
            )
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .tabBar)
        .yomiToast($toastMessage)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            sessionStart = Date()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false

            let incognito = AppSettings.shared.isIncognito

            // Mark as read if reached last page, or read ≥80% of a multi-page chapter
            let readProgress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
            if !incognito && !pages.isEmpty && (currentPage == pages.count - 1 || (pages.count > 1 && readProgress >= 0.8)) {
                markChapterRead()
            }

            guard !incognito else { return }

            let elapsed = Int(Date().timeIntervalSince(sessionStart))
            let progress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
            let cid = activeChapter.id
            let page = currentPage
            Task.detached {
                try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed, lastPageRead: page)
            }

            guard !pages.isEmpty, elapsed > 3 else { return }
            let mangaId = manga.id
            Task.detached(priority: .background) {
                guard var m = try? MangaQueries.fetchOne(id: mangaId) else { return }
                m.readingSeconds += elapsed
                try? MangaQueries.update(m)
            }
        }
        .onChange(of: currentPage) { _, newPage in
            if pages.count > 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            if pages.count > 0 && newPage >= pages.count - 2 {
                withAnimation(.spring(duration: 0.4)) { showFinishedBanner = true }
            }
            if !AppSettings.shared.isIncognito && pages.count > 0 && newPage >= pages.count - 2 {
                markChapterRead()
                if AppSettings.shared.trackerAutoUpdate && !didUpdateTrackerForCurrentChapter {
                    didUpdateTrackerForCurrentChapter = true
                    let mangaTitle = manga.title
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
                DiscussWebSheet(url: url, title: "Source")
            }
        }
        .onChange(of: shouldRequestReview) { _, should in
            if should { requestReview(); shouldRequestReview = false }
        }
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.easeOut(duration: 0.25)) { showFinishedBanner = false }
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
                    toastMessage = "Couldn't save read status"
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

    private func preloadNextChapterIfNeeded() {
        guard isContinuousReaderMode, hasNextChapter, nextPreload == nil, !isPreloadingNextChapter else { return }
        let next = chapters[currentChapterIndex + 1]

        // Prefer local files first, exactly like loadPages() does — otherwise every
        // chapter-boundary preload for a downloaded (offline-read) chapter burns the full
        // network timeout below trying and failing to reach the network, silently degrading
        // the seamless-crossing feature for the offline case it matters most in. See #90.
        if next.isDownloaded, let localURLs = DownloadManager.shared.localURLs(for: next) {
            nextPreload = (next, localURLs.map { $0.absoluteString })
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
            let result: [String]? = await withTaskGroup(of: [String]?.self) { group in
                group.addTask { await Self.fetchPages(bridge: b, path: path) }
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
            if let result, !result.isEmpty {
                nextPreload = (next, result)
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
        let leavingPage = currentPage
        if !AppSettings.shared.isIncognito {
            Task.detached {
                try? ChapterQueries.updateProgress(id: leavingId, progress: leavingProgress, readingSeconds: leavingElapsed, lastPageRead: leavingPage)
            }
        }
        markChapterRead()

        currentChapterIndex += 1
        pages = preload.pages
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
        let page = currentPage
        if !AppSettings.shared.isIncognito {
            Task.detached {
                try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed, lastPageRead: page)
            }
        }

        currentChapterIndex = index
        pages = []
        isLoading = true
        errorMessage = nil
        currentPage = 0
        sessionStart = Date()

        let path = chapters[index].path
        let b = bridge
        Task {
            let result = await Self.fetchPages(bridge: b, path: path)
            // A second, faster navigateToChapter() call (rapid double-tap, or two picks from
            // the Chapters sheet in quick succession) may have already moved past `index` by
            // the time this resolves — applying it now would overwrite the newer chapter's
            // pages with a stale result. See finding #88.
            guard currentChapterIndex == index else { return }
            pages = result
            isLoading = false
            if result.isEmpty { errorMessage = "No pages found." }
        }
    }

    // MARK: - Page Source

    /// Resolves a chapter's page URLs from whichever backend the manga came from.
    ///
    /// The JS-plugin path stays on a detached task — `SOURCE._fetchSync` blocks its thread on a
    /// `DispatchSemaphore` and must never run on MainActor. The Suwayomi path is ordinary async
    /// `URLSession` work and needs no hop.
    private static func fetchPages(bridge: JSBridge?, path: String) async -> [String] {
        if SuwayomiService.chapterRef(from: path) != nil {
            return (try? await SuwayomiService.shared.fetchPageURLs(chapterPath: path)) ?? []
        }
        guard let bridge else { return [] }
        return await Task.detached(priority: .userInitiated) {
            bridge.getPageList(chapterPath: path)
        }.value
    }

    // MARK: - Load Pages

    private func loadPages() async {
        sessionStart = Date()

        if activeChapter.isDownloaded,
           let localURLs = DownloadManager.shared.localURLs(for: activeChapter) {
            pages = localURLs.map { $0.absoluteString }
            isLoading = false
            return
        }

        let path = activeChapter.path
        let result = await Self.fetchPages(bridge: bridge, path: path)
        pages = result
        isLoading = false
        if result.isEmpty {
            errorMessage = "No pages found for this chapter."
        } else {
            // Restore reading progress (prefer stored page number)
            let chapterId = activeChapter.id
            let pageCount = result.count
            Task.detached {
                if let saved = try? ChapterQueries.fetchOne(id: chapterId),
                   !saved.isRead, pageCount > 1 {
                    let resumePage: Int
                    if saved.lastPageRead > 0 {
                        resumePage = min(saved.lastPageRead, pageCount - 1)
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

    // MARK: - Double-page spreads
    //
    // "double"/"automatic" pair consecutive pages into spreads. currentPage keeps its normal
    // meaning everywhere else (progress, resume, scrubber) — it's just an index into `pages`.
    // TabView only ever selects/produces spread-start indices via `spreadSelection`, a proxy
    // binding that snaps any raw page index down to the start of its enclosing spread.

    private var isDoubleActive: Bool {
        switch settings.pageLayout {
        case "double":    return true
        case "automatic": return viewportIsLandscape
        default:          return false
        }
    }

    private var spreadGroups: [[Int]] {
        guard isDoubleActive, pages.count > 1 else { return pages.indices.map { [$0] } }
        var groups: [[Int]] = []
        var i = 0
        while i < pages.count {
            groups.append(i + 1 < pages.count ? [i, i + 1] : [i])
            i += 2
        }
        return groups
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

            tapZoneOverlay
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func spreadContent(_ group: [Int]) -> some View {
        if group.count == 2 {
            HStack(spacing: 0) {
                MangaPageView(url: pages[group[0]])
                MangaPageView(url: pages[group[1]])
            }
        } else {
            MangaPageView(url: pages[group[0]])
        }
    }

    // MARK: - Tap zone actions
    //
    // "Left"/"right" here means physical screen side, not reading direction — RTL flips which
    // physical side advances vs. goes back, matching the original thirds/sides behavior.
    // Both move by a whole spread (1 or 2 pages) so they always land on a valid TabView tag.

    private func tapLeft() {
        moveSpread(forward: isRTL)
    }

    private func tapRight() {
        moveSpread(forward: !isRTL)
    }

    private func moveSpread(forward: Bool) {
        let groups = spreadGroups
        guard let idx = groups.firstIndex(where: { $0.first == spreadStart(for: currentPage) }) else { return }
        let targetIdx = forward ? min(idx + 1, groups.count - 1) : max(idx - 1, 0)
        let next = groups[targetIdx].first!
        if next != currentPage {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            currentPage = next
        }
    }

    private func tapMenu() {
        withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
    }

    @ViewBuilder
    private var tapZoneOverlay: some View {
        let layout = settings.tapZoneLayout

        if layout == "disabled" {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(perform: tapMenu)
        } else {
            GeometryReader { geo in
                switch layout {
                case "lShaped":   lShapedZones(geo: geo)
                case "kindle":    kindleZones(geo: geo)
                case "rightLeft": rightLeftZones(geo: geo)
                case "sides":     thirdsOrEdgeZones(geo: geo, sides: true)
                default:          thirdsOrEdgeZones(geo: geo, sides: false)
                }
            }
        }
    }

    // MARK: - Tap zone layouts

    /// "default" (equal thirds) / "sides" a.k.a. Edge (20 · 60 · 20)
    @ViewBuilder
    private func thirdsOrEdgeZones(geo: GeometryProxy, sides: Bool) -> some View {
        let w = geo.size.width
        let leftFraction: CGFloat = sides ? 0.2 : 1.0 / 3.0
        let rightFraction: CGFloat = sides ? 0.2 : 1.0 / 3.0
        let centerFraction = 1.0 - leftFraction - rightFraction
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .frame(width: w * leftFraction)
                .onTapGesture(perform: tapLeft)
            Color.clear.contentShape(Rectangle())
                .frame(width: w * centerFraction)
                .onTapGesture(perform: tapMenu)
            Color.clear.contentShape(Rectangle())
                .frame(width: w * rightFraction)
                .onTapGesture(perform: tapRight)
        }
    }

    /// L-Shaped: left column + bottom band both go "left" (the L), a top menu strip, everything
    /// else goes "right" — approximates Tachimanga's L-Shaped tap zone preset.
    @ViewBuilder
    private func lShapedZones(geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        let menuHeight = h * 0.12
        let bottomBandHeight = h * 0.18
        let leftWidth = w * 0.28

        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .frame(width: leftWidth, height: h)
                    .onTapGesture(perform: tapLeft)
                Color.clear.contentShape(Rectangle())
                    .frame(width: w - leftWidth, height: h)
                    .onTapGesture(perform: tapRight)
            }

            VStack(spacing: 0) {
                Spacer()
                Color.clear.contentShape(Rectangle())
                    .frame(width: w, height: bottomBandHeight)
                    .onTapGesture(perform: tapLeft)
            }
            .frame(height: h)

            Color.clear.contentShape(Rectangle())
                .frame(width: w, height: menuHeight)
                .onTapGesture(perform: tapMenu)
        }
        .frame(width: w, height: h)
    }

    /// Kindle-ish: a thin left strip goes back, the rest of the screen advances — optimized for
    /// mostly-forward reading. Top strip reaches the menu.
    @ViewBuilder
    private func kindleZones(geo: GeometryProxy) -> some View {
        edgeWeightedZones(geo: geo, leftFraction: 0.2)
    }

    /// Right-and-Left: a plain 50/50 split, top strip reaches the menu.
    @ViewBuilder
    private func rightLeftZones(geo: GeometryProxy) -> some View {
        edgeWeightedZones(geo: geo, leftFraction: 0.5)
    }

    @ViewBuilder
    private func edgeWeightedZones(geo: GeometryProxy, leftFraction: CGFloat) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        let menuHeight = h * 0.12
        let leftWidth = w * leftFraction
        VStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .frame(width: w, height: menuHeight)
                .onTapGesture(perform: tapMenu)
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .frame(width: leftWidth, height: h - menuHeight)
                    .onTapGesture(perform: tapLeft)
                Color.clear.contentShape(Rectangle())
                    .frame(width: w - leftWidth, height: h - menuHeight)
                    .onTapGesture(perform: tapRight)
            }
        }
    }
}

// MARK: - MangaPageView (single page with pinch-to-zoom + double-tap reset)

private struct MangaPageView: View {
    let url: String

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadFailed = false

    var body: some View {
        GeometryReader { geo in
            // KFImage, not AsyncImage: page hosts behind Cloudflare (e.g. AquaManga) need the same
            // UA-matching requestModifier YomiApp.swift registers globally on KingfisherManager —
            // AsyncImage uses a bare URLSession with no way to attach that, so it 403s silently.
            Group {
                if loadFailed {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    KFImage(URL(string: url))
                        .placeholder {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .onFailure { _ in loadFailed = true }
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onChange(of: url) { _, _ in loadFailed = false }
            .background(Color.black)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 1.0), 4.0)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale == 1.0 {
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1.0 else { return }
                        let maxX = (scale - 1) * geo.size.width / 2
                        let maxY = (scale - 1) * geo.size.height / 2
                        offset = CGSize(
                            width:  min(max(lastOffset.width  + value.translation.width,  -maxX), maxX),
                            height: min(max(lastOffset.height + value.translation.height, -maxY), maxY)
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.0
                                lastScale = 2.0
                            }
                        }
                    }
            )
        }
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
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
            }
            .scrollPosition(id: $visibleId, anchor: .top)
            .onAppear {
                if currentPage > 0 {
                    proxy.scrollTo("cur:\(currentPage)", anchor: .top)
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
                // Two-way sync with the overlay's progress slider — scrolling
                // updates currentPage above, this reflects slider drags back
                // into the scroll position. Guarded so it's a no-op when the
                // change originated from the scroll itself.
                let newId = "cur:\(new)"
                guard newId != visibleId else { return }
                withAnimation { proxy.scrollTo(newId, anchor: .top) }
            }
        }
        .ignoresSafeArea()
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showOverlay.toggle()
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { isAutoScrolling.toggle() }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
        )
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
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAutoScrolling)
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
        .onDisappear { isAutoScrolling = false }
    }

    @ViewBuilder
    private func pageImage(_ url: String) -> some View {
        KFImage(URL(string: url))
            .placeholder {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
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
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $visibleId, anchor: .center)
            .onAppear {
                if currentPage > 0 {
                    proxy.scrollTo("cur:\(currentPage)", anchor: .center)
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
                withAnimation { proxy.scrollTo(newId, anchor: .center) }
            }
        }
        .ignoresSafeArea()
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showOverlay.toggle()
            }
        }
    }

    @ViewBuilder
    private func pageImage(_ url: String) -> some View {
        KFImage(URL(string: url))
            .placeholder {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxHeight: .infinity)
            }
            .resizable()
            .scaledToFit()
            .frame(maxHeight: .infinity)
    }
}

// MARK: - VerticalPagedReaderView

struct VerticalPagedReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                    MangaPageView(url: url)
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(-90))
                        .tag(index)
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90))
            .frame(width: geo.size.width, height: geo.size.height)
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showOverlay.toggle()
            }
        }
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

    @State private var showChapterSheet = false
    @State private var showSettingsSheet = false

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
                            Picker("Mode", selection: $readerMode) {
                                Label("Right to left", systemImage: "book.pages").tag(ReaderMode.horizontalRTL)
                                Label("Left to right", systemImage: "book.pages.fill").tag(ReaderMode.horizontalLTR)
                                Label("Paged (vertical)", systemImage: "square.stack").tag(ReaderMode.verticalPaged)
                                Label("Continuous (right to left)", systemImage: "arrow.left").tag(ReaderMode.continuousRTL)
                                Label("Continuous (left to right)", systemImage: "arrow.right").tag(ReaderMode.continuousLTR)
                                Label("Webtoon", systemImage: "scroll").tag(ReaderMode.verticalScroll)
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                    .navigationTitle("Reader Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettingsSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium])
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
                    HStack(spacing: 18) {
                        Button(action: onPrevChapter) {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(hasPrevChapter ? Color.primary : Color.primary.opacity(0.3))
                        }
                        .disabled(!hasPrevChapter)
                        .accessibilityLabel("Previous chapter")

                        Button(action: onNextChapter) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(hasNextChapter ? Color.primary : Color.primary.opacity(0.3))
                        }
                        .disabled(!hasNextChapter)
                        .accessibilityLabel("Next chapter")
                    }
                }
                .font(YomiTokens.Font.mono(12))
                .foregroundStyle(.secondary)

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
                            accessibilityValueText: { "Page \(Int($0.rounded()) + 1) of \(totalPages)" }
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
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
    }
}

// MARK: - DiscussWebSheet

import WebKit

struct DiscussWebSheet: View {
    let url: URL
    var title: String = "Discussion"
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
