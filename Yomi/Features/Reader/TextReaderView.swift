import SwiftUI
import StoreKit
import WebKit

// MARK: - NovelTheme

enum NovelTheme: String, CaseIterable {
    case light  = "Light"
    case sepia  = "Sepia"
    case warm   = "Warm"
    case dark   = "Dark"
    case amoled = "AMOLED"

    private var token: YomiTokens.ReaderTheme { YomiTokens.Reader.theme(named: rawValue) }

    var bg:        String { token.bg }
    var fg:        String { token.fg }
    var linkColor: String { token.link }
    var isDark:    Bool   { token.isDark }

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    /// Color for the theme swatch circle in the overlay
    var swatchColor: Color { token.bgColor }

    var uiColor: UIColor { UIColor(hex: bg) ?? .systemBackground }
}

// MARK: - TextReaderView

struct TextReaderView: View {
    let novel: Novel
    let bridge: JSBridge
    let chapters: [NovelChapter]
    private let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var shouldRequestReview = false

    /// The chapter being read — with infinite scroll, the one under the reading line.
    @State private var currentChapterIndex: Int
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var didStart = false
    /// False until the first chapter opens, so that open doesn't flush a session that never started.
    @State private var didStartReading = false

    // One web view for the reader's lifetime; chapters are sections inside it (NovelReaderWeb.swift).
    @State private var controller = NovelReaderController()
    /// HTML of the chapters currently in the document, by chapter id (TTS reads from here).
    @State private var loadedContent: [String: String] = [:]
    /// Bumped on every whole-document load, so a slow fetch for a chapter the user already left is dropped.
    @State private var loadGeneration = 0
    @State private var isAppending = false

    // Background preload of the next chapter for Next/swipe when infinite scroll is off.
    @State private var chapterContentCache: [String: String] = [:]
    @State private var preloadingChapterIds: Set<String> = []

    // Reader settings — initialized from persisted AppSettings
    @State private var fontSize: Double        = AppSettings.shared.fontSize
    @State private var lineSpacing: Double     = AppSettings.shared.lineSpacing
    @State private var novelTheme: NovelTheme  = NovelTheme(rawValue: AppSettings.shared.novelTheme) ?? .light
    @State private var fontFamily: String      = AppSettings.shared.novelFontFamily
    @State private var justifyText: Bool       = AppSettings.shared.novelJustifyText
    @State private var hPadding: Int           = AppSettings.shared.novelHorizontalPadding
    @State private var paragraphSpacing: Double = AppSettings.shared.novelParagraphSpacing
    @State private var letterSpacing: Int      = AppSettings.shared.novelLetterSpacing

    @State private var showOverlay = true
    /// Pages mode: chapter name + "page / pages" drawn above and below the text (S136).
    @State private var pageInfo: PageInfo? = nil
    struct PageInfo: Equatable { var chapterName: String; var page: Int; var pages: Int }
    @State private var showFinishedBanner = false
    @State private var sessionStart: Date = Date()
    @State private var lastKnownScrollPercent: Double? = nil
    /// Last value actually written to the DB per chapter — the autosave skips ticks that haven't moved a
    /// meaningful distance from it (Known Issue #142).
    @State private var lastPersistedScrollPercent: [String: Double] = [:]
    @State private var sourceURL: URL? = nil
    @State private var showSourceSheet = false

    // Listening (S143): the app-wide player; the reader mirrors it (highlight, follow, mini-player).
    @State private var player = ListenPlayer.shared
    @State private var showPlayerSheet = false

    init(novel: Novel, bridge: JSBridge, chapters: [NovelChapter], startIndex: Int = 0) {
        self.novel   = novel
        self.bridge  = bridge
        self.chapters = chapters
        self.startIndex = min(max(startIndex, 0), max(chapters.count - 1, 0))
        _currentChapterIndex = State(initialValue: self.startIndex)
    }

    // MARK: - Computed

    private var activeChapter: NovelChapter { chapters[currentChapterIndex] }
    /// The player is reading this novel (maybe another chapter of it).
    private var listeningHere: Bool { player.novel?.id == novel.id }
    private var hasPrevChapter: Bool { currentChapterIndex > 0 }
    private var hasNextChapter: Bool { currentChapterIndex < chapters.count - 1 }
    private var nextChapterForPreload: NovelChapter? { hasNextChapter ? chapters[currentChapterIndex + 1] : nil }

    /// The source's language as a base code, for hyphenation (`<html lang>`). LNReader catalogs store
    /// native names ("English"), Yomi's own plugins codes ("en"); a multi-language source gives none.
    private var sourceLanguage: String? {
        guard let raw = ExtensionManager.shared.installed.first(where: { $0.id == novel.sourceId })?.language
        else { return nil }
        let code = SourceLanguage.baseCode(for: raw)
        return code == "all" ? nil : code
    }

    /// Reader-settings stylesheet. Applied once at load and again only when a setting changes.
    private var readerCSS: String {
        let font = ReaderFont.resolve(fontFamily)
        let fs  = Int(fontSize)
        let ls  = String(format: "%.2f", lineSpacing)
        let ps  = String(format: "%.2f", paragraphSpacing)
        let lnk = AppSettings.shared.accentColor
        let spacing: String = switch letterSpacing {
        case ..<0: "letter-spacing: -0.01em;"
        case 1...: "letter-spacing: 0.04em; word-spacing: 0.1em;"
        default:   "letter-spacing: normal;"
        }
        // Justified ~40-character phone lines need hyphenation or they open wide word gaps (RESEARCH §25.3).
        let align = justifyText
            ? "text-align: justify; -webkit-hyphens: auto; hyphens: auto;"
            : "text-align: start;"
        return """
            \(font.fontFaceCSS)
            :root { --m: \(hPadding)px; }
            html, body { background: \(novelTheme.bg); }
            body {
                font-family: \(font.css);
                font-size: \(fs)px;
                line-height: \(ls);
                \(align)
                \(spacing)
                color: \(novelTheme.fg);
                -webkit-text-size-adjust: 100%;
                word-break: break-word;
                overflow-wrap: break-word;
            }
            /* The column is capped near 36em (~75 characters) so iPad and landscape lines stay readable. */
            #yomi-chapters { padding: 24px \(hPadding)px 200px \(hPadding)px;
                             max-width: calc(36em + \(2 * hPadding)px); margin: 0 auto; }
            p { margin: 0 0 \(ps)em 0; }
            a { color: \(lnk); text-decoration: none; }
            a svg, a svg path, a svg polygon, a svg rect { fill: \(lnk); stroke: \(lnk); }
            svg { fill: currentColor; }
            h1, h2, h3 { margin: 0.5em 0 0.4em 0; line-height: 1.3; }
            ::highlight(yomi-tts) { background-color: color-mix(in srgb, \(lnk) 30%, transparent); }
            """
    }

    private var pagesMode: Bool { AppSettings.shared.novelReadingMode == "pages" }

    /// Whether reaching a chapter's end flows into the next one: infinite scroll in scroll mode, "Continue into
    /// next chapter" in pages mode (separate settings, Martin's call).
    private var continuesIntoNext: Bool {
        pagesMode ? AppSettings.shared.novelPagesContinue : AppSettings.shared.novelInfiniteScroll
    }

    private var readerOptions: NovelReaderController.Options {
        .init(infinite: continuesIntoNext,
              swipe: AppSettings.shared.novelSwipeChapters,
              taps: AppSettings.shared.novelMenuTaps == 2 ? 2 : 1,
              pages: pagesMode)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(novelTheme.uiColor)
                .ignoresSafeArea()

            // Always mounted: changing chapter never depends on SwiftUI rebuilding the web view (bug #1).
            ReaderWebView(controller: controller, css: readerCSS, options: readerOptions, lang: sourceLanguage)
                .ignoresSafeArea()

            if pagesMode, let info = pageInfo, !isLoading, errorMessage == nil {
                pageIndicator(info)
            }

            if isLoading || errorMessage != nil {
                ZStack {
                    Color(novelTheme.uiColor).ignoresSafeArea()
                    if let error = errorMessage {
                        VStack(spacing: 14) {
                            Text(error)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try again") { openChapter(currentChapterIndex, restorePercent: 0) }
                                .buttonStyle(.bordered)
                        }
                        .padding()
                    } else {
                        ProgressView()
                            .tint(novelTheme.isDark ? .white : .gray)
                    }
                }
                // Tapping the placeholder still toggles the menu, so Back is always reachable.
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() } }
            }

            if showFinishedBanner {
                chapterFinishedBanner
            }

            // Docked under the text while listening; the menu panel takes its place when open.
            if listeningHere && !showOverlay {
                VStack {
                    Spacer()
                    ListenMiniPlayer(onOpen: { showPlayerSheet = true })
                        .environment(\.colorScheme, novelTheme.colorScheme)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            #if DEBUG
            // UI tests read the menu state here.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("reader.menuState")
                .accessibilityValue(showOverlay ? "open" : "closed")
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("reader.fontFamily")
                .accessibilityValue(ReaderFont.resolve(fontFamily).id)
            #endif

            // Not rendered at all while hidden: a faded-out glass overlay stayed in the accessibility tree,
            // so VoiceOver could reach invisible controls (S129).
            if showOverlay {
                TextReaderOverlayView(
                    novel:                novel,
                    chapter:              activeChapter,
                    currentChapterIndex:  currentChapterIndex,
                    chapters:             chapters,
                    progress:             lastKnownScrollPercent ?? activeChapter.lastScrollPercent ?? 0,
                    fontSize:             $fontSize,
                    lineSpacing:          $lineSpacing,
                    novelTheme:           $novelTheme,
                    fontFamily:           $fontFamily,
                    justifyText:          $justifyText,
                    hPadding:             $hPadding,
                    paragraphSpacing:     $paragraphSpacing,
                    letterSpacing:        $letterSpacing,
                    showOverlay:          $showOverlay,
                    isListening:          listeningHere,
                    hasPrevChapter:       hasPrevChapter,
                    hasNextChapter:       hasNextChapter,
                    sourceURL:            sourceURL,
                    onDismiss:            { dismiss() },
                    onPrevChapter:        { navigateToChapter(currentChapterIndex - 1) },
                    onNextChapter:        { navigateToChapter(currentChapterIndex + 1) },
                    onJumpToChapter:      { navigateToChapter($0) },
                    onToggleTTS:          { toggleListening() },
                    onViewSource:         { showSourceSheet = true }
                )
                // The app root's .preferredColorScheme (app theme) wins over this view's, so the glass menu
                // followed the app theme, not the reader theme the user picked under Look (Martin, S136).
                .environment(\.colorScheme, novelTheme.colorScheme)
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .swipeBackEnabled()
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(novelTheme.colorScheme)
        .task {
            guard !didStart, !chapters.isEmpty else { return }
            didStart = true
            controller.onEvent = { handle($0) }
            openChapter(startIndex, restorePercent: chapters[startIndex].lastScrollPercent ?? 0)
        }
        .task(id: activeChapter.id) {
            let path = activeChapter.path
            let b = bridge
            sourceURL = await Task.detached(priority: .background) {
                b.resolveSourceURL(path: path)
            }.value
        }
        .sheet(isPresented: $showPlayerSheet) {
            ListenPlayerView()
        }
        .onChange(of: player.chapterToken) { _, _ in syncListeningChapter() }
        .onChange(of: player.sentenceIndex) { _, _ in markListeningSentence() }
        .onChange(of: listeningHere) { _, on in
            controller.setListening(on)
            if !on { controller.ttsClear() }
        }
        .sheet(isPresented: $showSourceSheet) {
            if let url = sourceURL {
                DiscussWebSheet(url: url, title: "Source")
            }
        }
        .onChange(of: fontSize)   { _, v in AppSettings.shared.fontSize = v }
        .onChange(of: novelTheme) { _, v in
            AppSettings.shared.novelTheme  = v.rawValue
        }
        .onChange(of: lineSpacing) { _, v in AppSettings.shared.lineSpacing = v }
        .onChange(of: fontFamily)    { _, v in AppSettings.shared.novelFontFamily = v }
        .onChange(of: justifyText)  { _, v in AppSettings.shared.novelJustifyText = v }
        .onChange(of: hPadding)     { _, v in AppSettings.shared.novelHorizontalPadding = v }
        .onChange(of: paragraphSpacing) { _, v in AppSettings.shared.novelParagraphSpacing = v }
        .onChange(of: letterSpacing) { _, v in AppSettings.shared.novelLetterSpacing = v }
        .onChange(of: shouldRequestReview) { _, should in
            if should { requestReview(); shouldRequestReview = false }
        }
        .onAppear {
            player.readersOpen += 1
            controller.setListening(listeningHere)
            sessionStart = Date()
            // "Keep screen on" used to apply to the manga reader only (S142 settings audit).
            UIApplication.shared.isIdleTimerDisabled = AppSettings.shared.keepScreenOn
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            player.readersOpen = max(0, player.readersOpen - 1)
            // Listening carries on after the reader closes (Martin S143); the mini-player moves to the tab bar.
            flushScrollPercent()
            flushReadingTime()
        }
    }

    // MARK: - Pages mode indicator

    /// Chapter name at the top, "12 / 30" at the bottom — in the space the pages-mode CSS leaves free
    /// (34 px + safe area each side), so it never covers text.
    private func pageIndicator(_ info: PageInfo) -> some View {
        VStack {
            Text(info.chapterName)
                .lineLimit(1)
                .padding(.top, 6)
            Spacer()
            Text("\(info.page) / \(info.pages)")
                .monospacedDigit()
                // Above the docked mini-player while listening (the pages CSS leaves room for both).
                .padding(.bottom, listeningHere && !showOverlay ? 72 : 6)
        }
        .font(YomiTokens.Font.mono(11))
        .foregroundStyle(Color(hex: novelTheme.fg).opacity(0.5))
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(info.page) of \(info.pages), \(info.chapterName)")
        #if DEBUG
        .accessibilityIdentifier("reader.page")
        .accessibilityValue("\(info.page)/\(info.pages)")
        #endif
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
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
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

    // MARK: - Reader events

    private func handle(_ event: NovelReaderController.Event) {
        switch event {
        case .tap:
            withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
        case .swipe(let next):
            navigateToChapter(currentChapterIndex + (next ? 1 : -1))
        case .current(let id):
            guard let idx = chapters.firstIndex(where: { $0.id == id }), idx != currentChapterIndex else { return }
            // Infinite scroll crossed into another chapter: close out the old one, no reload.
            flushReadingTime()
            showFinishedBanner = false
            currentChapterIndex = idx
            lastKnownScrollPercent = nil
            enterChapter()
        case .progress(let id, let pct):
            if id == activeChapter.id {
                lastKnownScrollPercent = pct
                if pct >= 0.7 && !continuesIntoNext { preloadNextChapterIfNeeded() }
            }
            persistScrollPercent(pct, chapterId: id)
        case .complete(let id):
            chapterCompleted(id)
        case .needNext(let afterId):
            appendChapter(after: afterId)
        case .dropped(let id):
            loadedContent.removeValue(forKey: id)
        case .page(let id, let page, let pages):
            pageInfo = PageInfo(chapterName: chapters.first { $0.id == id }?.name ?? "", page: page, pages: pages)
        case .listenFromHere:
            Task { await listenFromSelection() }
        }
    }

    private func chapterCompleted(_ id: String) {
        guard let chapter = chapters.first(where: { $0.id == id }) else { return }
        if !AppSettings.shared.isIncognito {
            let novelId = novel.id
            Task {
                try? NovelQueries.markRead(chapterId: id, novelId: novelId)
                await MainActor.run {
                    if AppSettings.shared.recordChapterRead() {
                        shouldRequestReview = true
                    }
                }
            }
            if AppSettings.shared.trackerAutoUpdate {
                let novelTitle = novel.title
                let chapNum = Int(chapter.chapterNumber ?? 0)
                Task {
                    for tracker in TrackerManager.loggedInTrackers {
                        if let trackerId = await tracker.searchManga(title: novelTitle) {
                            await tracker.updateMangaProgress(trackerId: trackerId, chaptersRead: chapNum)
                        }
                    }
                }
            }
        }
        // With infinite scroll the next chapter is already coming up below; only say so at the very end. Pages mode
        // without "continue" ends on its own Next chapter page, so the banner would just cover it.
        let isLast = chapter.id == chapters.last?.id
        if id == activeChapter.id && (isLast || (!continuesIntoNext && !pagesMode)) {
            withAnimation(.spring(duration: 0.4)) { showFinishedBanner = true }
        }
    }

    // MARK: - Scroll Position

    private func persistScrollPercent(_ pct: Double, chapterId: String) {
        guard !AppSettings.shared.isIncognito else { return }
        // Only write when the position actually moved ≥1% (Known Issue #142); `.onDisappear` and chapter
        // changes always write the final value.
        guard abs(pct - (lastPersistedScrollPercent[chapterId] ?? -1)) >= 0.01 else { return }
        lastPersistedScrollPercent[chapterId] = pct
        Task.detached(priority: .background) {
            try? NovelQueries.updateScrollPercent(chapterId: chapterId, percent: pct)
        }
    }

    private func flushScrollPercent() {
        guard !AppSettings.shared.isIncognito, let pct = lastKnownScrollPercent else { return }
        let cid = activeChapter.id
        lastPersistedScrollPercent[cid] = pct
        Task.detached(priority: .background) {
            try? NovelQueries.updateScrollPercent(chapterId: cid, percent: pct)
        }
    }

    // MARK: - Reading Time

    private func flushReadingTime() {
        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        sessionStart = Date()
        guard !AppSettings.shared.isIncognito, elapsed > 3 else { return }
        let cid = activeChapter.id
        let nid = novel.id
        Task.detached(priority: .background) {
            try? NovelQueries.addReadingTime(chapterId: cid, novelId: nid, seconds: elapsed)
        }
    }

    // MARK: - Navigate

    /// Next / Previous / swipe / the Chapters sheet.
    private func navigateToChapter(_ index: Int) {
        // Re-selecting the open chapter is a no-op (finding #92) — unless its load failed.
        guard index >= 0, index < chapters.count, index != currentChapterIndex || errorMessage != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showFinishedBanner = false
        // Already in the document below (infinite scroll)? Scroll to it; the `current` event does the rest.
        let target = chapters[index]
        if errorMessage == nil, !isLoading, index > currentChapterIndex, loadedContent[target.id] != nil {
            controller.scrollToChapter(id: target.id)
            if listeningHere, let html = loadedContent[target.id] { listen(chapterIndex: index, html: html, from: 0) }
            return
        }
        // Credit the chapter being left as read if the user was effectively done with it (matches the
        // 90% `complete` threshold), not unconditionally (finding #91).
        let wasNearComplete = (lastKnownScrollPercent ?? activeChapter.lastScrollPercent ?? 0) >= 0.9
        if wasNearComplete && !AppSettings.shared.isIncognito {
            let chapterId = activeChapter.id
            let novelId = novel.id
            Task.detached(priority: .background) { try? NovelQueries.markRead(chapterId: chapterId, novelId: novelId) }
        }
        // Changing chapter by hand while listening moves the listening there too.
        openChapter(index, restorePercent: 0, listen: listeningHere)
    }

    /// Replaces the document with one chapter. The web view stays; only its content changes.
    private func openChapter(_ index: Int, restorePercent: Double, listen: Bool = false) {
        guard index >= 0, index < chapters.count else { return }
        if didStartReading { flushScrollPercent(); flushReadingTime() }
        didStartReading = true
        loadGeneration += 1
        let generation = loadGeneration
        let chapter = chapters[index]
        currentChapterIndex = index
        lastKnownScrollPercent = nil
        isLoading = true
        errorMessage = nil
        isAppending = false
        // Evict preloaded content we're not about to use — a jump can strand the old "next" (#94).
        chapterContentCache = chapterContentCache.filter { $0.key == chapter.id }
        enterChapter()
        Task {
            let perf = Perf.begin("NovelChapter")
            let html = await content(for: chapter)
            perf.end()
            guard generation == loadGeneration else { return }
            if html.isEmpty {
                errorMessage = "Unable to load chapter content. The source may be temporarily unavailable."
                isLoading = false
                return
            }
            loadedContent = [chapter.id: html]
            controller.show(id: chapter.id, title: chapter.name, html: html, restorePercent: restorePercent)
            isLoading = false
            if listen {
                self.listen(chapterIndex: index, html: html, from: 0)
            } else {
                resendListeningSentences(for: chapter.id)
            }
        }
    }

    /// Infinite scroll asked for the chapter after `afterId`.
    private func appendChapter(after afterId: String) {
        guard let idx = chapters.firstIndex(where: { $0.id == afterId }) else { return }
        guard idx + 1 < chapters.count else {
            controller.appendUnavailable(retry: false)
            return
        }
        guard !isAppending else { return }
        isAppending = true
        let generation = loadGeneration
        let next = chapters[idx + 1]
        Task {
            let html = await content(for: next)
            guard generation == loadGeneration else { return }
            isAppending = false
            if html.isEmpty {
                controller.appendUnavailable(retry: true)
                return
            }
            loadedContent[next.id] = html
            controller.append(id: next.id, title: next.name, html: html)
            resendListeningSentences(for: next.id)
        }
    }

    /// Bookkeeping when a chapter becomes the one being read.
    private func enterChapter() {
        sessionStart = Date()
        // Download-ahead first, so the next chapters are fetching while this one is read.
        NovelDownloadManager.shared.downloadAhead(novel: novel, chapters: chapters,
                                                  after: currentChapterIndex,
                                                  count: AppSettings.shared.novelDownloadAhead)
    }

    /// Preloaded → downloaded → source.
    private func content(for chapter: NovelChapter) async -> String {
        if let cached = chapterContentCache.removeValue(forKey: chapter.id) { return cached }
        let path = chapter.path
        let novelId = novel.id
        let b = bridge
        return await Task.detached(priority: .userInitiated) {
            NovelDownloadStore.content(novelId: novelId, chapterPath: path)
                ?? b.parseChapter(path: path)
        }.value
    }

    // MARK: - Preload

    private func preloadNextChapterIfNeeded() {
        // Low Data Mode asks apps not to prefetch; the next chapter still loads when it's opened.
        guard let next = nextChapterForPreload,
              !NetworkMonitor.shared.isConstrained
                || FileManager.default.fileExists(atPath: NovelDownloadStore.fileURL(novelId: novel.id, chapterPath: next.path).path),
              chapterContentCache[next.id] == nil,
              !preloadingChapterIds.contains(next.id) else { return }
        preloadingChapterIds.insert(next.id)
        let path = next.path
        let nextId = next.id
        let novelId = novel.id
        let b = bridge
        Task.detached(priority: .background) {
            let html = NovelDownloadStore.content(novelId: novelId, chapterPath: path)
                ?? b.parseChapter(path: path)
            await MainActor.run {
                preloadingChapterIds.remove(nextId)
                // Only cache if this chapter is still "next" — a jump may have evicted it meanwhile (#94).
                guard !html.isEmpty, nextChapterForPreload?.id == nextId else { return }
                chapterContentCache[nextId] = html
            }
        }
    }

    // MARK: - Listening

    private func toggleListening() {
        if listeningHere {
            player.stop()
            return
        }
        guard let html = loadedContent[activeChapter.id] else { return }
        let id = activeChapter.id
        let index = currentChapterIndex
        let sentences = ListenText.sentences(fromHTML: html)
        controller.ttsSet(id: id, sentences: sentences)
        Task {
            // Start where the reader is looking, not at the top of the chapter.
            let first = await controller.ttsFirstVisible(id: id)
            startPlayer(chapterIndex: index, sentences: sentences, from: first)
            withAnimation(.easeInOut(duration: 0.2)) { showOverlay = false }
        }
    }

    /// "Listen from Here" in the selection menu.
    private func listenFromSelection() async {
        guard let id = await controller.selectionChapterId(),
              let index = chapters.firstIndex(where: { $0.id == id }),
              let html = loadedContent[id] else { return }
        let sentences = ListenText.sentences(fromHTML: html)
        controller.ttsSet(id: id, sentences: sentences)
        let from = await controller.ttsSelectionIndex(id: id)
        startPlayer(chapterIndex: index, sentences: sentences, from: from)
    }

    private func listen(chapterIndex index: Int, html: String, from sentence: Int) {
        let sentences = ListenText.sentences(fromHTML: html)
        controller.ttsSet(id: chapters[index].id, sentences: sentences)
        startPlayer(chapterIndex: index, sentences: sentences, from: sentence)
    }

    private func startPlayer(chapterIndex index: Int, sentences: [String], from sentence: Int) {
        player.start(novel: novel, bridge: bridge, chapters: chapters, index: index,
                     sentences: sentences, from: sentence, language: sourceLanguage)
        markListeningSentence()
    }

    /// The player moved to another chapter (auto-advance, lock screen, its own buttons): bring the reader along.
    private func syncListeningChapter() {
        guard listeningHere, let chapter = player.chapter else { return }
        if loadedContent[chapter.id] != nil {
            controller.ttsSet(id: chapter.id, sentences: player.sentences)
            if chapter.id != activeChapter.id { controller.scrollToChapter(id: chapter.id) }
            markListeningSentence()
        } else if let index = chapters.firstIndex(where: { $0.id == chapter.id }), index != currentChapterIndex {
            openChapter(index, restorePercent: 0)
        }
    }

    /// A chapter (re)entered the page: if it's the one being read aloud, the page needs its sentences again.
    private func resendListeningSentences(for id: String) {
        guard listeningHere, player.chapter?.id == id, !player.sentences.isEmpty else { return }
        controller.ttsSet(id: id, sentences: player.sentences)
        markListeningSentence()
    }

    private func markListeningSentence() {
        guard listeningHere, let id = player.chapter?.id, loadedContent[id] != nil else { return }
        controller.ttsMark(id: id, index: player.sentenceIndex, show: AppSettings.shared.ttsHighlight)
    }
}

// MARK: - TextReaderOverlayView

struct TextReaderOverlayView: View {
    let novel:                Novel
    let chapter:              NovelChapter
    let currentChapterIndex:  Int
    let chapters:             [NovelChapter]
    let progress:             Double
    @Binding var fontSize:    Double
    @Binding var lineSpacing: Double
    @Binding var novelTheme:  NovelTheme
    @Binding var fontFamily:   String
    @Binding var justifyText:  Bool
    @Binding var hPadding:     Int
    @Binding var paragraphSpacing: Double
    @Binding var letterSpacing: Int
    @Binding var showOverlay: Bool
    var isListening:          Bool
    var hasPrevChapter:       Bool = false
    var hasNextChapter:       Bool = false
    var sourceURL:            URL? = nil
    let onDismiss:            () -> Void
    var onPrevChapter:        (() -> Void)? = nil
    var onNextChapter:        (() -> Void)? = nil
    var onJumpToChapter:      ((Int) -> Void)? = nil
    var onToggleTTS:          (() -> Void)? = nil
    var onViewSource:         (() -> Void)? = nil

    @State private var showChapterSheet = false
    @State private var settings = AppSettings.shared
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("novelPanelTab") private var panelTabRaw = ReaderPanelTab.text.rawValue

    private var panelTab: ReaderPanelTab { ReaderPanelTab(rawValue: panelTabRaw) ?? .text }

    private let paddingOptions: [(label: String, value: Int)] = [
        ("Narrow", 8), ("Normal", 16), ("Wide", 28)
    ]
    private let lineSpacingOptions: [(label: String, value: Double)] = [
        ("Tight", 1.3), ("Normal", 1.6), ("Airy", 2.0)
    ]
    private let paragraphOptions: [(label: String, value: Double)] = [
        ("Small", 0.5), ("Medium", 1.0), ("Large", 1.5)
    ]
    private let letterOptions: [(label: String, value: Int)] = [
        ("Tight", -1), ("Normal", 0), ("Loose", 1)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar — individual floating Liquid Glass chips ───────────
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("Close reader")

                VStack(alignment: .leading, spacing: 2) {
                    Text(novel.title)
                        .font(YomiTokens.Font.grotesk(15, weight: .medium))
                        .lineLimit(1)
                    Text(chapter.name)
                        .font(YomiTokens.Font.mono(11))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !chapters.isEmpty {
                    Button {
                        showChapterSheet = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 17))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .glassEffect(.regular, in: Circle())
                    .accessibilityLabel("Chapters")
                }

                if sourceURL != nil {
                    Button {
                        onViewSource?()
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 17))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .glassEffect(.regular, in: Circle())
                    .accessibilityLabel("Open on source website")
                }
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
                                        } else if let pct = ch.lastScrollPercent, pct > 0.01 {
                                            Text("\(Int(pct * 100))%")
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

            Spacer()

            // ── Bottom panel — Liquid Glass (S136 redesign) ────────────────
            // Chapter nav + progress always on top; every reader setting one tab away below it, so nothing
            // hides in a sheet or in the app's Settings screen.
            VStack(spacing: 10) {
                navigationRow
                progressFooter
                tabStrip
                switch panelTab {
                case .text:    textTab
                case .look:    lookTab
                case .reading: readingTab
                }
            }
            .padding(.vertical, 14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }
}

// MARK: - Reader panel pieces (S136)

/// Selected controls are a solid inverted pill — black on light glass, white on dark — now that the panel follows
/// the reader theme (S136: a fixed white pill vanished on Light). Fixed colours on purpose: semantic ones
/// (`.primary`, systemBackground) get glass vibrancy and wash out to grey.
enum ReaderPanelStyle {
    static func selectedFill(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : .black }
    static func selectedText(_ scheme: ColorScheme) -> Color { scheme == .dark ? .black : .white }
}

enum ReaderPanelTab: String, CaseIterable {
    case text = "Text", look = "Look", reading = "Reading"
}

extension TextReaderOverlayView {
    var navigationRow: some View {
        HStack(spacing: 0) {
            Button { onPrevChapter?() } label: {
                Image(systemName: "chevron.left.2")
                    .font(.title3).fontWeight(.semibold)
                    .foregroundStyle(hasPrevChapter ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 56, height: 40)
            }
            .disabled(!hasPrevChapter)
            .accessibilityLabel("Previous chapter")

            Spacer()

            Button { onToggleTTS?() } label: {
                Label(isListening ? "Stop" : "Listen",
                      systemImage: isListening ? "stop.circle.fill" : "headphones")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isListening ? Color.accentColor : .primary)
            }
            // The glyph is the only indication of speaking state (Known Issue #121).
            .accessibilityLabel(isListening ? "Stop reading aloud" : "Read aloud")

            Spacer()

            Button { onNextChapter?() } label: {
                Image(systemName: "chevron.right.2")
                    .font(.title3).fontWeight(.semibold)
                    .foregroundStyle(hasNextChapter ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 56, height: 40)
            }
            .disabled(!hasNextChapter)
            .accessibilityLabel("Next chapter")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder var progressFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            let pctText = Text(Notation.progress(progress)).foregroundStyle(Color.accentColor)
            if let num = chapter.chapterNumber {
                Text("\(Notation.chapter(num)) · \(pctText)")
                    .font(YomiTokens.Font.mono(12))
                    .foregroundStyle(.secondary)
            } else {
                pctText.font(YomiTokens.Font.mono(12))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 20)
    }

    var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(ReaderPanelTab.allCases, id: \.self) { tab in
                let selected = panelTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { panelTabRaw = tab.rawValue }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(selected ? 0.16 : 0), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.rawValue) settings")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: Text

    var textTab: some View {
        VStack(spacing: 8) {
            fontRow
            sizeRow
            ReaderSegmentedRow(title: "Line", options: lineSpacingOptions, selection: $lineSpacing,
                               matches: { abs($0 - $1) < 0.05 }, accessibilityName: "Line spacing")
            ReaderSegmentedRow(title: "Paragraph", options: paragraphOptions, selection: $paragraphSpacing,
                               matches: { abs($0 - $1) < 0.05 }, accessibilityName: "Paragraph spacing")
            ReaderSegmentedRow(title: "Letters", options: letterOptions, selection: $letterSpacing,
                               accessibilityName: "Letter spacing")
            // Margins + Justify share a row to keep the panel short (S136 screenshot: one row per setting
            // covered half the screen).
            HStack(spacing: 10) {
                ReaderSegmentedControl(options: paddingOptions, selection: $hPadding, accessibilityName: "Margins")
                Spacer()
                Button { justifyText.toggle() } label: {
                    Label("Justify", systemImage: "text.justify")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(justifyText ? ReaderPanelStyle.selectedText(colorScheme) : Color.primary.opacity(0.75))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(justifyText ? ReaderPanelStyle.selectedFill(colorScheme) : Color.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Justify text")
                .accessibilityValue(justifyText ? "On" : "Off")
                .accessibilityHint("Aligns both edges and hyphenates long words")
                .accessibilityAddTraits(justifyText ? .isSelected : [])
            }
            .padding(.horizontal, 20)
        }
    }

    private var fontRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReaderFont.available) { font in
                        let selected = ReaderFont.resolve(fontFamily).id == font.id
                        Button { fontFamily = font.id } label: {
                            Text(font.name)
                                .font(font.previewFont(size: 15))
                                .lineLimit(1)
                                .foregroundStyle(selected ? ReaderPanelStyle.selectedText(colorScheme) : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selected ? ReaderPanelStyle.selectedFill(colorScheme) : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(font.id)
                        .accessibilityLabel("Font: \(font.name)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear { proxy.scrollTo(ReaderFont.resolve(fontFamily).id, anchor: .center) }
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 12) {
            Text("Size").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button { fontSize = max(12, fontSize - 1) } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 40, height: 32)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .disabled(fontSize <= 12)
            .accessibilityLabel("Smaller text")
            Text("\(Int(fontSize))")
                .font(YomiTokens.Font.mono(15))
                .frame(minWidth: 28)
                .accessibilityLabel("Font size \(Int(fontSize)) points")
            Button { fontSize = min(40, fontSize + 1) } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 40, height: 32)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .disabled(fontSize >= 40)
            .accessibilityLabel("Larger text")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 20)
    }

    // MARK: Look

    var lookTab: some View {
        HStack(spacing: 14) {
            ForEach(NovelTheme.allCases, id: \.rawValue) { theme in
                Button { novelTheme = theme } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(theme.swatchColor)
                                .frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
                            if novelTheme == theme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(theme.isDark ? Color.white : Color.black)
                            }
                        }
                        Text(theme.rawValue)
                            .font(.caption2)
                            .foregroundStyle(novelTheme == theme ? Color.primary : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                // Selection is colour + a checkmark glyph only without this (Known Issue #121).
                .accessibilityLabel("\(theme.rawValue) reading theme")
                .accessibilityAddTraits(novelTheme == theme ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: Reading

    /// Same AppSettings values as Settings → Novels → Reading; the reader reads them live (`readerOptions`).
    var readingTab: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Layout").font(.subheadline)
                Spacer()
                ReaderSegmentedControl(options: [("Scroll", "scroll"), ("Pages", "pages")],
                                       selection: $settings.novelReadingMode,
                                       accessibilityName: "Layout")
            }
            if settings.novelReadingMode == "pages" {
                // In pages mode a sideways swipe turns the page, so "swipe to change chapter" doesn't apply.
                Toggle(isOn: $settings.novelPagesContinue) {
                    Text("Continue into next chapter").font(.subheadline)
                }
                .accessibilityHint("Off: each chapter ends on a page with a Next chapter button")
            } else {
                Toggle(isOn: $settings.novelInfiniteScroll) {
                    Text("Infinite scroll").font(.subheadline)
                }
                .accessibilityHint("Carries on into the next chapter at the end of this one")
                Toggle(isOn: $settings.novelSwipeChapters) {
                    Text("Swipe to change chapter").font(.subheadline)
                }
            }
            HStack {
                Text("Show menu with").font(.subheadline)
                Spacer()
                ReaderSegmentedControl(options: [("One tap", 1), ("Two taps", 2)],
                                       selection: $settings.novelMenuTaps,
                                       accessibilityName: "Show menu with")
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Title + segmented capsule — the reader panel's one control style for presets.
private struct ReaderSegmentedRow<Value: Equatable>: View {
    let title: String
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var matches: (Value, Value) -> Bool = { $0 == $1 }
    let accessibilityName: String

    var body: some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            ReaderSegmentedControl(options: options, selection: $selection, matches: matches,
                                   accessibilityName: accessibilityName)
        }
        .padding(.horizontal, 20)
    }
}

private struct ReaderSegmentedControl<Value: Equatable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var matches: (Value, Value) -> Bool = { $0 == $1 }
    let accessibilityName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                let selected = matches(selection, opt.value)
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(selected ? ReaderPanelStyle.selectedText(colorScheme) : Color.primary.opacity(0.75))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(selected ? ReaderPanelStyle.selectedFill(colorScheme) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                // A bare "Tight" doesn't say tight *what* (Known Issue #121).
                .accessibilityLabel("\(accessibilityName): \(opt.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(Color.primary.opacity(0.12), in: Capsule())
    }
}

// MARK: - UIColor hex init (needed for NovelTheme.uiColor)

private extension UIColor {
    convenience init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(red:   CGFloat((val >> 16) & 0xFF) / 255,
                  green: CGFloat((val >>  8) & 0xFF) / 255,
                  blue:  CGFloat( val        & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Preview

#Preview {
    let chapter = NovelChapter(
        id: "ch-1", novelId: "1", path: "/novel/re-zero/chapter/1",
        name: "Chapter 1 — The Beginning", chapterNumber: 1.0,
        isRead: false, readAt: nil, releaseTime: "2021-01-01", readingSeconds: 0
    )
    TextReaderView(
        novel: Novel(
            id: "1", path: "/novel/re-zero", sourceId: "en.royalroad",
            title: "Re:Zero − Starting Life in Another World",
            coverURL: nil, summary: nil, author: "Tappei Nagatsuki",
            status: "ongoing", genres: ["Fantasy", "Isekai"],
            inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
            readingSeconds: 0, readingStatus: .none, notes: nil
        ),
        bridge: {
            guard let url = Bundle.main.url(forResource: "test-source", withExtension: "js"),
                  let b = JSBridge(scriptURL: url) else {
                fatalError("test-source.js must be in the Debug target for Simulator previews")
            }
            return b
        }(),
        chapters: [chapter], startIndex: 0
    )
}
