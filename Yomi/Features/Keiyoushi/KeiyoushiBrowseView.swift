import SwiftUI

// MARK: - KeiyoushiBrowseView

/// Browse one installed Keiyoushi (Mihon) source: Popular / Latest / search, run on-device by the embedded JVM.
/// Mirrors `SuwayomiBrowseView` (including its stale-result generation guard, finding #84), styled with canvas
/// tokens from the start (the #115/#116 lesson).
struct KeiyoushiBrowseView: View {
    let source: KeiyoushiSource

    enum FeedTab: String, CaseIterable {
        case popular = "Popular"
        case latest  = "Latest"
    }

    @Environment(\.yomiCanvas) private var canvas
    @State private var mangas: [Manga] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var cloudflareURL: String? = nil
    @State private var showCFBypass = false
    @State private var currentPage = 1
    @State private var hasNextPage = true
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var selectedManga: Manga? = nil
    @State private var showMangaDetail = false
    @State private var selectedFeed: FeedTab = .popular
    @State private var supportsLatest = false
    @State private var loadGeneration = 0

    private let bridge = KeiyoushiBridge.shared
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)]

    var body: some View {
        Group {
            if isLoading && mangas.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Starting the extension…")
                        .font(YomiTokens.Font.mono(11))
                        .foregroundStyle(canvas.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, mangas.isEmpty {
                if cloudflareURL != nil {
                    YomiEmptyState(systemImage: "shield.slash", title: "Cloudflare blocked this source",
                                   message: "Solve the check once in the browser, then Yomi retries.",
                                   actionLabel: "Bypass Cloudflare", actionIcon: "shield.slash") {
                        showCFBypass = true
                    }
                } else {
                    YomiEmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't load \(source.name)",
                                   message: error, actionLabel: "Try again", actionIcon: "arrow.clockwise") {
                        Task { await reset(keepQuery: isSearching); await loadMore() }
                    }
                }
            } else if mangas.isEmpty && !hasNextPage {
                YomiEmptyState(systemImage: "magnifyingglass", title: "Nothing found",
                               message: isSearching ? "No results for \u{201C}\(searchQuery)\u{201D}." : "This feed is empty.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(mangas) { manga in
                            Button {
                                selectedManga = manga
                                showMangaDetail = true
                            } label: {
                                MangaCoverCell(manga: manga)
                            }
                            .buttonStyle(.plain)
                        }
                        if hasNextPage {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .onAppear { Task { await loadMore() } }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(canvas.bg.ignoresSafeArea())
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if supportsLatest && !isSearching {
                Picker("Feed", selection: $selectedFeed) {
                    ForEach(FeedTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(canvas.bg)
            }
        }
        .onChange(of: selectedFeed) { _, _ in
            Task { await reset(); await loadMore() }
        }
        .searchable(text: $searchQuery, prompt: "Search \(source.name)")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: searchQuery) { _, new in
            if new.isEmpty && isSearching { Task { await reset(); await loadMore() } }
        }
        .navigationDestination(isPresented: $showMangaDetail) {
            if let manga = selectedManga {
                MangaDetailView(manga: manga)
            }
        }
        .sheet(isPresented: $showCFBypass) {
            CFBypassView(initialURL: cloudflareURL ?? source.homeURL) {
                Task { await reset(keepQuery: isSearching); await loadMore() }
            }
        }
        .onAppear { AppSettings.shared.noteSourceOpened(BrowseSourceKey.keiyoushi(source.id)) }
        .task {
            await loadMore()
            supportsLatest = await bridge.supportsLatest(sourceId: source.id)
        }
    }

    // MARK: - Load

    private func loadMore() async {
        guard !isLoading, hasNextPage else { return }
        let perf = Perf.begin("KeiyoushiPage")
        defer { perf.end() }
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        cloudflareURL = nil
        do {
            let page: KeiyoushiMangaPage
            if isSearching {
                page = try await bridge.search(sourceId: source.id, query: searchQuery, page: currentPage)
            } else if supportsLatest && selectedFeed == .latest {
                page = try await bridge.latest(sourceId: source.id, page: currentPage)
            } else {
                page = try await bridge.popular(sourceId: source.id, page: currentPage)
            }
            // A reset() while this request was in flight bumped the generation — drop the stale page (#84).
            guard generation == loadGeneration else { return }
            let known = Set(mangas.map(\.id))
            let newMangas = (page.mangas ?? [])
                .map { KeiyoushiMapping.manga(from: $0, sourceId: source.id) }
                .filter { !known.contains($0.id) }
            mangas.append(contentsOf: newMangas)
            // A source that repeats its last page forever would paginate endlessly (#9b) — stop on no-new-items.
            hasNextPage = (page.hasNextPage ?? false) && !newMangas.isEmpty
            currentPage += 1
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            let message = error.localizedDescription
            if message.hasPrefix("CLOUDFLARE:") {
                cloudflareURL = String(message.dropFirst("CLOUDFLARE:".count))
                errorMessage = "Cloudflare"
            } else {
                errorMessage = message
            }
            hasNextPage = false
            isLoading = false
        }
    }

    private func runSearch() async {
        guard !searchQuery.isEmpty else { return }
        await reset(keepQuery: true)
        await loadMore()
    }

    private func reset(keepQuery: Bool = false) async {
        loadGeneration += 1
        mangas = []
        currentPage = 1
        hasNextPage = true
        isSearching = keepQuery
        errorMessage = nil
        cloudflareURL = nil
        isLoading = false
    }
}
