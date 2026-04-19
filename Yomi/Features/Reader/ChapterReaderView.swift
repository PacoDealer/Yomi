import SwiftUI

// MARK: - ReaderMode

enum ReaderMode: String, CaseIterable {
    case horizontalRTL  = "Manga (RTL)"
    case horizontalLTR  = "Manhwa (LTR)"
    case verticalScroll = "Webtoon"
}

// MARK: - ChapterReaderView

struct ChapterReaderView: View {
    let manga: Manga
    let bridge: JSBridge
    let chapters: [Chapter]

    @Environment(\.dismiss) private var dismiss

    @State private var settings = AppSettings.shared
    @State private var currentChapterIndex: Int
    @State private var pages: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var readerMode: ReaderMode
    @State private var showOverlay = true
    @State private var currentPage = 0
    @State private var sessionStart: Date = Date()
    @State private var readingTimer: Timer? = nil
    @State private var sessionSeconds: Int = 0
    @State private var discussURL: URL? = nil
    @State private var showDiscussSheet = false

    init(manga: Manga, bridge: JSBridge, chapters: [Chapter], chapterIndex: Int) {
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
                        showOverlay: $showOverlay
                    )
                }
            }

            ReaderOverlayView(
                manga: manga,
                chapter: activeChapter,
                currentPage: $currentPage,
                totalPages: pages.count,
                readerMode: $readerMode,
                showOverlay: $showOverlay,
                showPageNumber: true,
                discussURL: discussURL,
                hasPrevChapter: hasPrevChapter,
                hasNextChapter: hasNextChapter,
                onDismiss: { dismiss() },
                onDiscuss: { showDiscussSheet = true },
                onPrevChapter: { navigateToChapter(currentChapterIndex - 1) },
                onNextChapter: { navigateToChapter(currentChapterIndex + 1) }
            )
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            sessionStart = Date()
            readingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                sessionSeconds += 1
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            readingTimer?.invalidate()
            readingTimer = nil

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
            if !AppSettings.shared.isIncognito && pages.count > 0 && newPage == pages.count - 1 {
                markChapterRead()
                if MALService.shared.isLoggedIn {
                    Task {
                        let mangaTitle = manga.title
                        let chapNum = Int(activeChapter.chapterNumber ?? 0)
                        if let malId = await MALService.shared.searchManga(title: mangaTitle) {
                            await MALService.shared.updateMangaProgress(malId: malId, chaptersRead: chapNum)
                        }
                    }
                }
            }
        }
        .task { await loadPages() }
        .task(id: activeChapter.id) {
            let path = activeChapter.path
            let b = bridge
            discussURL = await Task.detached(priority: .background) {
                b.getDiscussionURL(chapterPath: path)
            }.value
        }
        .sheet(isPresented: $showDiscussSheet) {
            if let url = discussURL {
                DiscussWebSheet(url: url)
            }
        }
    }

    // MARK: - Mark as Read

    private func markChapterRead() {
        let cid = activeChapter.id
        let mid = activeChapter.mangaId
        let wasDownloaded = activeChapter.isDownloaded
        let deleteAfterReading = AppSettings.shared.deleteDownloadAfterReading
        Task.detached {
            do {
                try ChapterQueries.markRead(id: cid, mangaId: mid)
            } catch {
                print("markChapterRead error: \(error)")
            }
            // Auto-delete download after finishing a downloaded chapter
            if wasDownloaded && deleteAfterReading {
                let dir = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Downloads/\(mid)/\(cid)")
                try? FileManager.default.removeItem(at: dir)
                try? DownloadQueries.markNotDownloaded(chapterId: cid)
            }
        }
    }

    // MARK: - Navigation

    private func navigateToChapter(_ index: Int) {
        readingTimer?.invalidate()
        readingTimer = nil

        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        let progress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
        let cid = activeChapter.id
        let page = currentPage
        Task.detached {
            try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed, lastPageRead: page)
        }

        currentChapterIndex = index
        pages = []
        isLoading = true
        errorMessage = nil
        currentPage = 0
        sessionSeconds = 0
        sessionStart = Date()
        readingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            sessionSeconds += 1
        }

        let path = chapters[index].path
        let b = bridge
        Task.detached(priority: .userInitiated) {
            let result = b.getPageList(chapterPath: path)
            await MainActor.run {
                pages = result
                isLoading = false
                if result.isEmpty { errorMessage = "No pages found." }
            }
        }
    }

    // MARK: - Load Pages

    private func loadPages() async {
        sessionStart = Date()

        // Si el capítulo está descargado, usar archivos locales
        if activeChapter.isDownloaded,
           let localURLs = DownloadManager.shared.localURLs(for: activeChapter) {
            pages = localURLs.map { $0.absoluteString }
            isLoading = false
            return
        }

        let path = activeChapter.path
        let result = await Task.detached(priority: .userInitiated) {
            bridge.getPageList(chapterPath: path)
        }.value
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

    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                    MangaPageView(url: url)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .ignoresSafeArea()

            tapZoneOverlay
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var tapZoneOverlay: some View {
        let layout = settings.tapZoneLayout

        if layout == "disabled" {
            Color.clear.contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
                }
        } else {
            GeometryReader { geo in
                let w = geo.size.width
                let leftFraction: CGFloat = layout == "sides" ? 0.2 : 1.0 / 3.0
                let rightFraction: CGFloat = layout == "sides" ? 0.2 : 1.0 / 3.0
                let centerFraction = 1.0 - leftFraction - rightFraction

                HStack(spacing: 0) {
                    // Left zone
                    Color.clear.contentShape(Rectangle())
                        .frame(width: w * leftFraction)
                        .onTapGesture {
                            let next = isRTL
                                ? min(currentPage + 1, pages.count - 1)
                                : max(currentPage - 1, 0)
                            if next != currentPage {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                currentPage = next
                            }
                        }
                    // Center zone — toggles overlay
                    Color.clear.contentShape(Rectangle())
                        .frame(width: w * centerFraction)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
                        }
                    // Right zone
                    Color.clear.contentShape(Rectangle())
                        .frame(width: w * rightFraction)
                        .onTapGesture {
                            let next = isRTL
                                ? max(currentPage - 1, 0)
                                : min(currentPage + 1, pages.count - 1)
                            if next != currentPage {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                currentPage = next
                            }
                        }
                }
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

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
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

    @State private var visibleId: Int? = nil
    @State private var isAutoScrolling = false
    @State private var settings = AppSettings.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                            default:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .aspectRatio(2 / 3, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, CGFloat(settings.webtoonHorizontalPadding))
            }
            .scrollPosition(id: $visibleId, anchor: .top)
            .onAppear {
                if currentPage > 0 {
                    proxy.scrollTo(currentPage, anchor: .top)
                }
            }
            .onChange(of: visibleId) { _, id in
                if let id { currentPage = id }
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
                let next = (visibleId ?? 0) + 1
                guard next < pages.count else { isAutoScrolling = false; break }
                visibleId = next
            }
        }
        .onDisappear { isAutoScrolling = false }
    }
}

// MARK: - ReaderOverlayView

struct ReaderOverlayView: View {
    let manga: Manga
    let chapter: Chapter
    @Binding var currentPage: Int
    let totalPages: Int
    @Binding var readerMode: ReaderMode
    @Binding var showOverlay: Bool
    let showPageNumber: Bool
    let discussURL: URL?
    let hasPrevChapter: Bool
    let hasNextChapter: Bool
    let onDismiss: () -> Void
    let onDiscuss: () -> Void
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 88)
                .ignoresSafeArea(edges: .top)

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.trailing, 4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(manga.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(chapter.name)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if discussURL != nil {
                        Button(action: onDiscuss) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                    }

                    Picker("Mode", selection: $readerMode) {
                        Image(systemName: "book.pages").tag(ReaderMode.horizontalRTL)
                        Image(systemName: "book.pages.fill").tag(ReaderMode.horizontalLTR)
                        Image(systemName: "scroll").tag(ReaderMode.verticalScroll)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 108)
                    .colorScheme(.dark)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            Spacer()

            // Bottom bar
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 88)
                .ignoresSafeArea(edges: .bottom)

                HStack(spacing: 8) {
                    Button {
                        onPrevChapter()
                    } label: {
                        Image(systemName: "chevron.left.2")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(hasPrevChapter ? .white : .white.opacity(0.25))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!hasPrevChapter)

                    if showPageNumber && totalPages > 1 {
                        VStack(spacing: 4) {
                            Text("\(currentPage + 1) / \(totalPages)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .monospacedDigit()

                            if readerMode != .verticalScroll {
                                Slider(
                                    value: Binding(
                                        get: { Double(currentPage) },
                                        set: { currentPage = Int($0.rounded()) }
                                    ),
                                    in: 0...Double(totalPages - 1),
                                    step: 1
                                )
                                .tint(.white)
                                .environment(\.colorScheme, .dark)
                            }
                        }
                    } else {
                        Spacer()
                    }

                    Button {
                        onNextChapter()
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(hasNextChapter ? .white : .white.opacity(0.25))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!hasNextChapter)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .opacity(showOverlay ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
    }
}

// MARK: - DiscussWebSheet

import WebKit

struct DiscussWebSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Discussion")
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
        bridge: JSBridge(scriptURL: Bundle.main.url(forResource: "test-source", withExtension: "js")!)!,
        chapters: [],
        chapterIndex: 0
    )
}
