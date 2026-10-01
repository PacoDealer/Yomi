import SwiftUI
import StoreKit
import WebKit
import AVFoundation

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

    @State private var showOverlay = true
    @State private var showFinishedBanner = false
    @State private var sessionStart: Date = Date()
    @State private var lastKnownScrollPercent: Double? = nil
    /// Last value actually written to the DB per chapter — the autosave skips ticks that haven't moved a
    /// meaningful distance from it (Known Issue #142).
    @State private var lastPersistedScrollPercent: [String: Double] = [:]
    @State private var sourceURL: URL? = nil
    @State private var showSourceSheet = false

    // TTS
    @State private var isSpeaking = false
    @State private var ttsDelegate: TTSDelegate? = nil

    init(novel: Novel, bridge: JSBridge, chapters: [NovelChapter], startIndex: Int = 0) {
        self.novel   = novel
        self.bridge  = bridge
        self.chapters = chapters
        self.startIndex = min(max(startIndex, 0), max(chapters.count - 1, 0))
        _currentChapterIndex = State(initialValue: self.startIndex)
    }

    // MARK: - Computed

    private var activeChapter: NovelChapter { chapters[currentChapterIndex] }
    private var hasPrevChapter: Bool { currentChapterIndex > 0 }
    private var hasNextChapter: Bool { currentChapterIndex < chapters.count - 1 }
    private var nextChapterForPreload: NovelChapter? { hasNextChapter ? chapters[currentChapterIndex + 1] : nil }

    private var fontFamilyCSS: String {
        fontFamily == "Serif"
            ? "Georgia, \"Times New Roman\", serif"
            : "-apple-system, \"Helvetica Neue\", sans-serif"
    }

    /// Reader-settings stylesheet. Applied once at load and again only when a setting changes.
    private var readerCSS: String {
        let fs  = Int(fontSize)
        let ls  = String(format: "%.2f", lineSpacing)
        let lnk = AppSettings.shared.accentColor
        return """
            html, body { background: \(novelTheme.bg); }
            body {
                font-family: \(fontFamilyCSS);
                font-size: \(fs)px;
                line-height: \(ls);
                text-align: \(justifyText ? "justify" : "start");
                color: \(novelTheme.fg);
                -webkit-text-size-adjust: 100%;
                word-break: break-word;
                overflow-wrap: break-word;
            }
            #yomi-chapters { padding: 24px \(hPadding)px 200px \(hPadding)px; }
            p { margin: 0 0 0.75em 0; }
            a { color: \(lnk); text-decoration: none; }
            a svg, a svg path, a svg polygon, a svg rect { fill: \(lnk); stroke: \(lnk); }
            svg { fill: currentColor; }
            h1, h2, h3 { margin: 0.5em 0 0.4em 0; line-height: 1.3; }
            """
    }

    private var readerOptions: NovelReaderController.Options {
        .init(infinite: AppSettings.shared.novelInfiniteScroll,
              swipe: AppSettings.shared.novelSwipeChapters,
              taps: AppSettings.shared.novelMenuTaps == 2 ? 2 : 1)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(novelTheme.uiColor)
                .ignoresSafeArea()

            // Always mounted: changing chapter never depends on SwiftUI rebuilding the web view (bug #1).
            ReaderWebView(controller: controller, css: readerCSS, options: readerOptions)
                .ignoresSafeArea()

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

            #if DEBUG
            // UI tests read the menu state here.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("reader.menuState")
                .accessibilityValue(showOverlay ? "open" : "closed")
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
                    showOverlay:          $showOverlay,
                    isSpeaking:           $isSpeaking,
                    hasPrevChapter:       hasPrevChapter,
                    hasNextChapter:       hasNextChapter,
                    sourceURL:            sourceURL,
                    onDismiss:            { dismiss() },
                    onPrevChapter:        { navigateToChapter(currentChapterIndex - 1) },
                    onNextChapter:        { navigateToChapter(currentChapterIndex + 1) },
                    onJumpToChapter:      { navigateToChapter($0) },
                    onToggleTTS:          { toggleTTS() },
                    onViewSource:         { showSourceSheet = true }
                )
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
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
        .onChange(of: shouldRequestReview) { _, should in
            if should { requestReview(); shouldRequestReview = false }
        }
        .onAppear { sessionStart = Date() }
        .onDisappear {
            stopTTS()
            flushScrollPercent()
            flushReadingTime()
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
                if pct >= 0.7 && !AppSettings.shared.novelInfiniteScroll { preloadNextChapterIfNeeded() }
            }
            persistScrollPercent(pct, chapterId: id)
        case .complete(let id):
            chapterCompleted(id)
        case .needNext(let afterId):
            appendChapter(after: afterId)
        case .dropped(let id):
            loadedContent.removeValue(forKey: id)
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
        // With infinite scroll the next chapter is already coming up below; only say so at the very end.
        let isLast = chapter.id == chapters.last?.id
        if id == activeChapter.id && (!AppSettings.shared.novelInfiniteScroll || isLast) {
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
        openChapter(index, restorePercent: 0)
    }

    /// Replaces the document with one chapter. The web view stays; only its content changes.
    private func openChapter(_ index: Int, restorePercent: Double) {
        guard index >= 0, index < chapters.count else { return }
        stopTTS()
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

    // MARK: - TTS

    private func toggleTTS() {
        if isSpeaking {
            stopTTS()
        } else {
            startTTS()
        }
    }

    private func startTTS() {
        guard let html = loadedContent[activeChapter.id], !html.isEmpty else { return }
        let plain = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: plain)
        utterance.rate = AppSettings.shared.ttsSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        let delegate = TTSDelegate { self.isSpeaking = false }
        ttsDelegate = delegate
        let synth = AVSpeechSynthesizer()
        synth.delegate = delegate
        delegate.synthesizer = synth
        isSpeaking = true
        synth.speak(utterance)
    }

    private func stopTTS() {
        ttsDelegate?.synthesizer?.stopSpeaking(at: .immediate)
        ttsDelegate = nil
        isSpeaking = false
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
    @Binding var showOverlay: Bool
    @Binding var isSpeaking:  Bool
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

    private let paddingOptions: [(label: String, value: Int)] = [
        ("Narrow", 8), ("Normal", 16), ("Wide", 28)
    ]
    private let lineSpacingOptions: [(label: String, value: Double)] = [
        ("Tight", 1.3), ("Normal", 1.6), ("Airy", 2.0)
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

            // ── Bottom bar — Liquid Glass ─────────────────────────────────
            VStack(spacing: 14) {

                // Row 1: Font size slider
                HStack(spacing: 10) {
                    Text("A").font(.caption).foregroundStyle(.secondary)
                    YomiScrubber(
                        value: $fontSize,
                        range: 14...28,
                        accessibilityLabelText: "Font size",
                        accessibilityValueText: { "\(Int($0.rounded())) points" }
                    )
                    Text("A").font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                // Row 2: Font family + justify + horizontal margin
                HStack(spacing: 12) {
                    Button {
                        fontFamily = (fontFamily == "Serif") ? "System" : "Serif"
                    } label: {
                        Text("Aa")
                            .font(fontFamily == "Serif"
                                  ? .system(.subheadline, design: .serif).bold()
                                  : .subheadline.bold())
                            .foregroundStyle(fontFamily == "Serif" ? Color.primary : Color.primary.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(fontFamily == "Serif" ? 0.18 : 0.06))
                            .clipShape(Capsule())
                    }
                    // "Aa" reads as nothing useful to VoiceOver, and neither state is announced
                    // without an explicit trait (Known Issue #121).
                    .accessibilityLabel("Serif font")
                    .accessibilityValue(fontFamily == "Serif" ? "On" : "Off")
                    .accessibilityAddTraits(fontFamily == "Serif" ? .isSelected : [])

                    Button { justifyText.toggle() } label: {
                        Image(systemName: "text.justify")
                            .font(.subheadline)
                            .foregroundStyle(justifyText ? Color.primary : Color.primary.opacity(0.45))
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(justifyText ? 0.18 : 0.06))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Justify text")
                    .accessibilityValue(justifyText ? "On" : "Off")
                    .accessibilityAddTraits(justifyText ? .isSelected : [])

                    Spacer()

                    // Margin control: Narrow / Normal / Wide
                    HStack(spacing: 0) {
                        ForEach(paddingOptions, id: \.value) { opt in
                            Button {
                                hPadding = opt.value
                            } label: {
                                Text(opt.label)
                                    .font(.caption2).fontWeight(.medium)
                                    .foregroundStyle(hPadding == opt.value ? Color.black : Color.primary.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(hPadding == opt.value ? Color.white : Color.clear)
                            }
                            // "Narrow" alone doesn't say narrow *what* (Known Issue #121).
                            .accessibilityLabel("Margins: \(opt.label)")
                            .accessibilityAddTraits(hPadding == opt.value ? .isSelected : [])
                        }
                    }
                    .background(Color.primary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)

                // Row 2b: Line spacing
                HStack(spacing: 16) {
                    Image(systemName: "text.alignleft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Spacing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(lineSpacingOptions, id: \.label) { opt in
                            Button {
                                lineSpacing = opt.value
                            } label: {
                                Text(opt.label)
                                    .font(.caption2).fontWeight(.medium)
                                    .foregroundStyle(abs(lineSpacing - opt.value) < 0.05 ? Color.black : Color.primary.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(abs(lineSpacing - opt.value) < 0.05 ? Color.white : Color.clear)
                            }
                            .accessibilityLabel("Line spacing: \(opt.label)")
                            .accessibilityAddTraits(abs(lineSpacing - opt.value) < 0.05 ? .isSelected : [])
                        }
                    }
                    .background(Color.primary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)

                // Row 3: Theme swatches
                HStack(spacing: 12) {
                    Spacer()
                    ForEach(NovelTheme.allCases, id: \.rawValue) { theme in
                        Button {
                            novelTheme = theme
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.swatchColor)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                                    )
                                if novelTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(theme.isDark ? Color.white : Color.black)
                                }
                            }
                        }
                        // Selection here is conveyed by colour + a checkmark glyph only — neither
                        // reaches VoiceOver without this (Known Issue #121).
                        .accessibilityLabel("\(theme.rawValue) reading theme")
                        .accessibilityAddTraits(novelTheme == theme ? .isSelected : [])
                    }
                    Spacer()
                }

                // Row 4: Prev / TTS / Next chapter
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
                        Image(systemName: isSpeaking ? "stop.circle.fill" : "play.circle")
                            .font(.title2)
                            .foregroundStyle(isSpeaking ? Color.accentColor : .secondary)
                    }
                    // The glyph is the only indication of speaking state (Known Issue #121).
                    .accessibilityLabel(isSpeaking ? "Stop reading aloud" : "Read aloud")

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

                // Row 5: Chapter progress footer
                if let num = chapter.chapterNumber {
                    VStack(alignment: .leading, spacing: 7) {
                        let pctText = Text(Notation.progress(progress)).foregroundStyle(Color.accentColor)
                        Text("\(Notation.chapter(num)) · \(pctText)")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(.secondary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(Color.accentColor)
                                    .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                            }
                        }
                        .frame(height: 3)
                    }
                    .padding(.top, 11)
                    .padding(.horizontal, 20)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }
}

// MARK: - TTSDelegate

private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: () -> Void
    var synthesizer: AVSpeechSynthesizer?

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
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
