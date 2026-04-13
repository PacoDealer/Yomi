import SwiftUI

// MARK: - BrowseView

struct BrowseView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var catalogService   = PluginCatalogService.shared
    @State private var settings         = AppSettings.shared
    @State private var selectedTab: BrowseTab = .sources
    @State private var installingID: String? = nil

    enum BrowseTab: String, CaseIterable {
        case sources    = "Sources"
        case extensions = "Extensions"
        case search     = "Search"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(BrowseTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch selectedTab {
                case .sources:    sourcesTab
                case .extensions: extensionsTab
                case .search:     SearchView()
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: appRouter.openBrowseExtensions) { _, open in
                if open {
                    selectedTab = .extensions
                    appRouter.openBrowseExtensions = false
                }
            }
        }
    }

    // MARK: Sources tab

    @ViewBuilder
    private var sourcesTab: some View {
        if extensionManager.installed.isEmpty {
            ContentUnavailableView(
                "No sources installed",
                systemImage: "puzzlepiece.extension",
                description: Text("Browse Extensions to discover and install reading sources.")
            )
        } else {
            List(extensionManager.installed) { ext in
                NavigationLink {
                    SourceBrowseView(ext: ext)
                } label: {
                    ExtensionRow(ext: ext)
                }
            }
        }
    }

    // MARK: Extensions tab

    @ViewBuilder
    private var extensionsTab: some View {
        Group {
            if catalogService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = catalogService.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Failed to load: \(error)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await catalogService.fetchCatalog() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCatalog.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        Text("No extensions available")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Install a reading source to get started.\nYou can also add one manually via More → Plugins.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Link(destination: URL(string: "https://github.com/PacoDealer/Yomi/blob/main/EXTENSIONS.md")!) {
                        Label("View extension guide", systemImage: "arrow.up.right.square")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredCatalog) { entry in
                    YomiCatalogEntryRow(
                        entry:        entry,
                        isInstalled:  catalogService.isInstalled(entry),
                        isInstalling: installingID == entry.id
                    ) {
                        Task { await installEntry(entry) }
                    }
                }
                .refreshable { await catalogService.fetchCatalog() }
            }
        }
        .task { await catalogService.fetchCatalog() }
    }

    private var filteredCatalog: [PluginCatalogEntry] {
        settings.showNSFW
            ? catalogService.entries
            : catalogService.entries.filter { !$0.isNSFW }
    }

    private func installEntry(_ entry: PluginCatalogEntry) async {
        guard let fileURL = URL(string: entry.fileURL) else { return }
        installingID = entry.id
        let ext = Extension(
            id:            entry.id,
            name:          entry.name,
            version:       entry.version,
            language:      entry.language,
            iconURL:       entry.iconURL.flatMap { URL(string: $0) },
            sourceListURL: fileURL,
            isInstalled:   true,
            isNSFW:        entry.isNSFW,
            sourceIds:     []
        )
        await extensionManager.install(ext)
        installingID = nil
    }
}

// MARK: - SearchView

private struct SearchView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var searchQuery: String = ""
    @State private var searchResults: [Manga] = []
    @State private var isSearching: Bool = false
    @State private var selectedSource: Extension? = nil
    @State private var debounceTask: Task<Void, Never>? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)
    ]

    // MARK: Body

    var body: some View {
        Group {
            if extensionManager.installed.isEmpty {
                ContentUnavailableView(
                    "No sources installed",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Install a source from More → Plugins before searching.")
                )
            } else if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchResults.isEmpty {
                resultsGrid
            } else if searchQuery.count >= 2 {
                ContentUnavailableView.search(text: searchQuery)
            } else if searchQuery.isEmpty {
                ContentUnavailableView(
                    "Search titles",
                    systemImage: "magnifyingglass",
                    description: Text("Results from your installed sources will appear here.")
                )
            } else {
                // 1 character typed
                ContentUnavailableView(
                    "Keep typing",
                    systemImage: "magnifyingglass",
                    description: Text("Type at least 2 characters to search.")
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if extensionManager.installed.count > 1 {
                Picker("Source", selection: $selectedSource) {
                    Text("All").tag(Optional<Extension>.none)
                    ForEach(extensionManager.installed) { ext in
                        Text(ext.name).tag(Optional(ext))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .searchable(text: $searchQuery, prompt: "Search titles")
        .onChange(of: searchQuery) { _, newValue in
            runSearch(query: newValue, debounce: true)
        }
        .onChange(of: selectedSource) { _, _ in
            guard searchQuery.count >= 2 else { return }
            runSearch(query: searchQuery, debounce: false)
        }
    }

    private func runSearch(query: String, debounce: Bool) {
        debounceTask?.cancel()
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        let sources = selectedSource.map { [$0] } ?? extensionManager.installed
        let bridgeFn: (Extension) -> JSBridge? = { ext in
            let docs = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs
                .appendingPathComponent("Extensions", isDirectory: true)
                .appendingPathComponent("\(ext.id).js")
            return JSBridge(scriptURL: url)
        }
        debounceTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                sources.flatMap { ext in
                    bridgeFn(ext)?
                        .searchManga(query: query, page: 1, sourceId: ext.id)
                    ?? []
                }
            }.value
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    // MARK: Results Grid

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(searchResults) { manga in
                    MangaCoverCell(manga: manga)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

// MARK: - ExtensionRow

private struct ExtensionRow: View {
    let ext: Extension

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: ext.iconURL) { image in
                image
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } placeholder: {
                Image(systemName: "puzzlepiece.extension")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(8)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.15))
            }
            .frame(width: 44, height: 44)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(ext.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(ext.language.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(.tint)
                        .clipShape(Capsule())
                    if ext.isNSFW {
                        Text("18+")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                    Text("v\(ext.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SourceBrowseView

struct SourceBrowseView: View {
    let ext: Extension

    enum FeedTab: String, CaseIterable {
        case popular = "Popular"
        case latest  = "Latest"
    }

    // MARK: State

    @State private var mangas: [Manga] = []
    @State private var novels: [Novel] = []
    @State private var bridge: JSBridge? = nil
    @State private var isNovelSource = false
    @State private var supportsLatest = false
    @State private var selectedFeed: FeedTab = .popular
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMoreContent = true

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)
    ]

    // MARK: Filtered Content

    private var filteredMangas: [Manga] {
        guard !searchText.isEmpty else { return mangas }
        return mangas.filter { $0.title.localizedStandardContains(searchText) }
    }

    private var filteredNovels: [Novel] {
        guard !searchText.isEmpty else { return novels }
        return novels.filter { $0.title.localizedStandardContains(searchText) }
    }

    private var isContentEmpty: Bool {
        isNovelSource ? filteredNovels.isEmpty : filteredMangas.isEmpty
    }

    // MARK: Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if isContentEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "No titles found",
                    systemImage: "books.vertical",
                    description: Text("This source returned no results.")
                )
            } else if isContentEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        if isNovelSource {
                            if let b = bridge {
                                ForEach(filteredNovels) { novel in
                                    NovelCoverCell(novel: novel, bridge: b)
                                }
                            }
                        } else {
                            ForEach(filteredMangas) { manga in
                                MangaCoverCell(manga: manga)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    if hasMoreContent && searchText.isEmpty {
                        Group {
                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            } else {
                                Color.clear
                                    .frame(height: 40)
                                    .onAppear { Task { await loadMore() } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(ext.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search \(ext.name)")
        .safeAreaInset(edge: .top, spacing: 0) {
            // Only show Popular/Latest picker for manga sources that support latest
            if !isNovelSource && supportsLatest {
                Picker("Feed", selection: $selectedFeed) {
                    ForEach(FeedTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .onChange(of: selectedFeed) { _, _ in
            Task { await loadContent() }
        }
        .task { await loadContent() }
    }

    // MARK: Load Content

    private func loadContent() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        hasMoreContent = true
        isLoadingMore = false
        mangas = []
        novels = []
        let sourceId = ext.id

        // Reuse existing bridge when switching tabs; only build one on first load
        let b: JSBridge
        if let existing = bridge {
            b = existing
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs
                .appendingPathComponent("Extensions", isDirectory: true)
                .appendingPathComponent("\(ext.id).js")
            guard let newBridge = JSBridge(scriptURL: url) else {
                errorMessage = "Failed to load source plugin."
                isLoading = false
                return
            }
            bridge = newBridge
            b = newBridge
        }

        if b.isLNReaderPlugin {
            isNovelSource = true
            supportsLatest = false
            let items = await Task.detached(priority: .userInitiated) {
                b.popularNovels(page: 1)
            }.value
            novels = items.map { item in
                Novel(id: UUID().uuidString, path: item.path, sourceId: sourceId,
                      title: item.name, coverURL: URL(string: item.cover ?? ""),
                      summary: nil, author: nil, status: "unknown", genres: [],
                      inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0)
            }
        } else {
            isNovelSource = false
            let (results, hasLatest) = await Task.detached(priority: .userInitiated) {
                let hasLatest = b.supportsLatest
                let list: [Manga]
                if hasLatest && self.selectedFeed == .latest {
                    list = b.getLatestManga(page: 1, sourceId: sourceId)
                } else {
                    list = b.getMangaList(page: 1, sourceId: sourceId)
                }
                return (list, hasLatest)
            }.value
            supportsLatest = hasLatest
            mangas = results
        }

        isLoading = false
    }

    // MARK: Load More

    private func loadMore() async {
        guard !isLoadingMore, hasMoreContent, let b = bridge else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        let sourceId = ext.id
        let feed = selectedFeed

        if isNovelSource {
            let items = await Task.detached(priority: .userInitiated) {
                b.popularNovels(page: nextPage)
            }.value
            if items.isEmpty {
                hasMoreContent = false
            } else {
                let newNovels = items.map { item in
                    Novel(id: UUID().uuidString, path: item.path, sourceId: sourceId,
                          title: item.name, coverURL: URL(string: item.cover ?? ""),
                          summary: nil, author: nil, status: "unknown", genres: [],
                          inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0)
                }
                novels.append(contentsOf: newNovels)
                currentPage = nextPage
            }
        } else {
            let results = await Task.detached(priority: .userInitiated) {
                feed == .latest
                    ? b.getLatestManga(page: nextPage, sourceId: sourceId)
                    : b.getMangaList(page: nextPage, sourceId: sourceId)
            }.value
            if results.isEmpty {
                hasMoreContent = false
            } else {
                mangas.append(contentsOf: results)
                currentPage = nextPage
            }
        }
        isLoadingMore = false
    }
}

// MARK: - NovelCoverCell

private struct NovelCoverCell: View {
    let novel: Novel
    let bridge: JSBridge

    var body: some View {
        NavigationLink {
            NovelDetailView(novel: novel, bridge: bridge)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: novel.coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .aspectRatio(2 / 3, contentMode: .fit)
                }
                .cornerRadius(8)
                .clipped()

                Text(novel.title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Browse — empty") {
    BrowseView()
}

#Preview("SourceBrowse — loading") {
    NavigationStack {
        SourceBrowseView(ext: Extension(
            id: "com.yomi.test",
            name: "Test Source",
            version: "1.0.0",
            language: "en",
            iconURL: nil,
            sourceListURL: Bundle.main.url(forResource: "test-source", withExtension: "js")!,
            isInstalled: true,
            isNSFW: false,
            sourceIds: []
        ))
    }
}
