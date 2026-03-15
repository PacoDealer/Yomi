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

    @State private var displayedChapter: Chapter
    @State private var displayedIndex: Int
    @State private var pages: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var readerMode: ReaderMode = .horizontalRTL
    @State private var showOverlay = true
    @State private var currentPage = 0

    init(chapter: Chapter, manga: Manga, bridge: JSBridge, chapters: [Chapter], currentIndex: Int) {
        self.manga = manga
        self.bridge = bridge
        self.chapters = chapters
        _displayedChapter = State(initialValue: chapter)
        _displayedIndex = State(initialValue: currentIndex)
    }

    // MARK: - Computed

    private var prevChapter: Chapter? {
        displayedIndex > 0 ? chapters[displayedIndex - 1] : nil
    }

    private var nextChapter: Chapter? {
        displayedIndex < chapters.count - 1 ? chapters[displayedIndex + 1] : nil
    }

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
                            Task {
                                try? ChapterQueries.markRead(
                                    id: displayedChapter.id,
                                    mangaId: displayedChapter.mangaId
                                )
                            }
                        }
                }
            }

            ReaderOverlayView(
                manga: manga,
                chapter: displayedChapter,
                currentPage: currentPage,
                totalPages: pages.count,
                readerMode: $readerMode,
                showOverlay: $showOverlay,
                onDismiss: { dismiss() },
                onPrevChapter: prevChapter.map { ch in
                    { navigateTo(chapter: ch, index: displayedIndex - 1) }
                },
                onNextChapter: nextChapter.map { ch in
                    { navigateTo(chapter: ch, index: displayedIndex + 1) }
                }
            )
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(.dark)
        .onChange(of: currentPage) { _, newPage in
            if !pages.isEmpty && newPage == pages.count - 1 {
                Task {
                    try? ChapterQueries.markRead(
                        id: displayedChapter.id,
                        mangaId: displayedChapter.mangaId
                    )
                }
            }
        }
        .task { await loadPages() }
    }

    // MARK: - Navigation

    private func navigateTo(chapter: Chapter, index: Int) {
        displayedChapter = chapter
        displayedIndex = index
        pages = []
        isLoading = true
        currentPage = 0
        errorMessage = nil
        Task { await loadPages() }
    }

    // MARK: - Load Pages

    private func loadPages() async {
        let path = displayedChapter.path
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

// MARK: - MangaPageView (single page with pinch-to-zoom)

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
    let onDismiss: () -> Void
    let onPrevChapter: (() -> Void)?
    let onNextChapter: (() -> Void)?

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
                        onPrevChapter?()
                    } label: {
                        Image(systemName: "chevron.left.2")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(onPrevChapter != nil ? .white : .white.opacity(0.25))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(onPrevChapter == nil)

                    Spacer()

                    if totalPages > 0 {
                        Text("Page \(currentPage + 1) / \(totalPages)")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button {
                        onNextChapter?()
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(onNextChapter != nil ? .white : .white.opacity(0.25))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(onNextChapter == nil)
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
        chapter: Chapter(
            id: "ch-1", mangaId: "1", path: "/chapter/ch-1",
            name: "Chapter 1", chapterNumber: 1.0,
            isRead: false, isDownloaded: false, readAt: nil, progress: 0.0
        ),
        manga: Manga(
            id: "1", path: "/manga/berserk", sourceId: "com.yomi.test",
            title: "Berserk", coverURL: nil, summary: nil,
            author: "Kentaro Miura", artist: "Kentaro Miura",
            status: .hiatus, genres: [], inLibrary: true, isLocal: false,
            lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0
        ),
        bridge: JSBridge(scriptURL: Bundle.main.url(forResource: "test-source", withExtension: "js")!)!,
        chapters: [],
        currentIndex: 0
    )
}
