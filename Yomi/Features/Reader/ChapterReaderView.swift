import SwiftUI

// MARK: - ReaderMode

enum ReaderMode: String, CaseIterable {
    case horizontalRTL  = "Manga (RTL)"
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

    init(manga: Manga, bridge: JSBridge, chapters: [Chapter], chapterIndex: Int) {
        self.manga = manga
        self.bridge = bridge
        self.chapters = chapters
        _currentChapterIndex = State(initialValue: chapterIndex)
        let modeString = AppSettings.shared.readerMode
        _readerMode = State(initialValue: ReaderMode(rawValue: modeString) ?? .horizontalRTL)
    }

    // MARK: - Computed

    private var activeChapter: Chapter { chapters[currentChapterIndex] }
    private var hasPrevChapter: Bool { currentChapterIndex > 0 }
    private var hasNextChapter: Bool { currentChapterIndex < chapters.count - 1 }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                        showOverlay: $showOverlay
                    )
                case .verticalScroll:
                    WebtoonReaderView(pages: pages, showOverlay: $showOverlay)
                        .onAppear {
                            markChapterRead()
                        }
                }
            }

            ReaderOverlayView(
                manga: manga,
                chapter: activeChapter,
                currentPage: currentPage,
                totalPages: pages.count,
                readerMode: $readerMode,
                showOverlay: $showOverlay,
                showPageNumber: true,
                hasPrevChapter: hasPrevChapter,
                hasNextChapter: hasNextChapter,
                onDismiss: { dismiss() },
                onPrevChapter: { navigateToChapter(currentChapterIndex - 1) },
                onNextChapter: { navigateToChapter(currentChapterIndex + 1) }
            )
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            sessionStart = Date()
            readingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                sessionSeconds += 1
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            readingTimer?.invalidate()
            readingTimer = nil

            if currentPage > 0 {
                markChapterRead()
            }

            let elapsed = Int(Date().timeIntervalSince(sessionStart))
            let progress = pages.isEmpty ? 0.0 : Double(currentPage + 1) / Double(pages.count)
            let cid = activeChapter.id
            Task.detached {
                try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed)
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
            if pages.count > 0 && newPage == pages.count - 1 {
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
    }

    // MARK: - Mark as Read

    private func markChapterRead() {
        let cid = activeChapter.id
        let mid = activeChapter.mangaId
        Task.detached {
            do {
                try ChapterQueries.markRead(id: cid, mangaId: mid)
            } catch {
                print("markChapterRead error: \(error)")
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
        Task.detached {
            try? ChapterQueries.updateProgress(id: cid, progress: progress, readingSeconds: elapsed)
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
        }
    }
}

// MARK: - MangaReaderView

struct MangaReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                MangaPageView(url: url, showOverlay: $showOverlay)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, .rightToLeft)
        .ignoresSafeArea()
    }
}

// MARK: - MangaPageView (single page with pinch-to-zoom + double-tap reset)

private struct MangaPageView: View {
    let url: String
    @Binding var showOverlay: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
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
                }
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showOverlay.toggle()
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.spring()) {
                        scale = 1.0
                        lastScale = 1.0
                    }
                }
        )
    }
}

// MARK: - WebtoonReaderView

struct WebtoonReaderView: View {
    let pages: [String]
    @Binding var showOverlay: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, url in
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
                }
            }
        }
        .ignoresSafeArea()
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
    let currentPage: Int
    let totalPages: Int
    @Binding var readerMode: ReaderMode
    @Binding var showOverlay: Bool
    let showPageNumber: Bool
    let hasPrevChapter: Bool
    let hasNextChapter: Bool
    let onDismiss: () -> Void
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

                    Picker("Mode", selection: $readerMode) {
                        ForEach(ReaderMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
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

                HStack(spacing: 0) {
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

                    Spacer()

                    if showPageNumber && totalPages > 0 {
                        Text("Page \(currentPage + 1) / \(totalPages)")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }

                    Spacer()

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
