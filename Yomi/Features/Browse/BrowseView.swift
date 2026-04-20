import SwiftUI

// MARK: - BrowseView

struct BrowseView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var catalogService   = PluginCatalogService.shared
    @State private var settings         = AppSettings.shared
    @State private var selectedTab: BrowseTab = .sources
    @State private var installingID: String? = nil
    @State private var suwayomiSources: [SuwayomiSource] = []
    @State private var suwayomiLoading = false

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
                case .search:     GlobalSearchView()
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
        let hasSuwayomi = SuwayomiService.shared.isEnabled
        if extensionManager.installed.isEmpty && !hasSuwayomi {
            ContentUnavailableView(
                "No sources installed",
                systemImage: "puzzlepiece.extension",
                description: Text("Browse Extensions to discover and install reading sources.")
            )
        } else {
            List {
                if !extensionManager.installed.isEmpty {
                    Section("Installed Plugins") {
                        ForEach(extensionManager.installed) { ext in
                            NavigationLink {
                                SourceBrowseView(ext: ext)
                            } label: {
                                ExtensionRow(ext: ext)
                            }
                        }
                    }
                }
                if hasSuwayomi {
                    Section {
                        if suwayomiLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if suwayomiSources.isEmpty {
                            Button("Load sources") {
                                Task { await loadSuwayomiSources() }
                            }
                        } else {
                            ForEach(suwayomiSources) { src in
                                NavigationLink {
                                    SuwayomiBrowseView(source: src)
                                } label: {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: "\(SuwayomiService.shared.baseURL)\(src.iconUrl)")) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Image(systemName: "network").foregroundStyle(.secondary)
                                        }
                                        .frame(width: 32, height: 32)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(src.name).font(.body)
                                            Text(src.lang.uppercased())
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Suwayomi Server")
                    } footer: {
                        Text(SuwayomiService.shared.baseURL)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .task {
                if hasSuwayomi && suwayomiSources.isEmpty {
                    await loadSuwayomiSources()
                }
            }
        }
    }

    private func loadSuwayomiSources() async {
        suwayomiLoading = true
        do {
            let sources = try await SuwayomiService.shared.fetchSources()
            await MainActor.run {
                suwayomiSources = sources.filter { !$0.isNsfw || settings.showNSFW }
                suwayomiLoading = false
            }
        } catch {
            await MainActor.run { suwayomiLoading = false }
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
                .refreshable { await catalogService.fetchCatalog(force: true) }
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

// MARK: - GlobalSearchView

private struct GlobalSearchView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var searchQuery = ""
    @State private var sections: [SearchSection] = []
    @State private var pendingCount = 0
    @State private var debounceTask: Task<Void, Never>? = nil

    struct SearchSection: Identifiable {
        let id: String
        let sourceName: String
        let isNovel: Bool
        let mangas: [Manga]
        let novels: [NovelItem]
        let bridge: JSBridge
    }

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)]

    var body: some View {
        Group {
            if extensionManager.installed.isEmpty {
                ContentUnavailableView(
                    "No sources installed",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Install a source from More → Plugins before searching.")
                )
            } else if pendingCount > 0 && sections.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !sections.isEmpty {
                resultsList
            } else if searchQuery.count >= 2 {
                ContentUnavailableView.search(text: searchQuery)
            } else if searchQuery.isEmpty {
                ContentUnavailableView(
                    "Search all sources",
                    systemImage: "magnifyingglass",
                    description: Text("Results stream in from all your installed sources.")
                )
            } else {
                ContentUnavailableView(
                    "Keep typing",
                    systemImage: "magnifyingglass",
                    description: Text("Type at least 2 characters to search.")
                )
            }
        }
        .searchable(text: $searchQuery, prompt: "Search titles")
        .onChange(of: searchQuery) { _, newValue in
            scheduleSearch(query: newValue)
        }
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    sectionView(section)
                }
                if pendingCount > 0 {
                    HStack {
                        ProgressView()
                        Text("Searching \(pendingCount) more…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: SearchSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.sourceName)
                .font(.headline)
                .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 12) {
                if section.isNovel {
                    ForEach(section.novels, id: \.path) { item in
                        let novel = Novel(
                            id: "\(section.id)_\(item.path)",
                            path: item.path,
                            sourceId: section.id,
                            title: item.name,
                            coverURL: URL(string: item.cover ?? ""),
                            summary: nil, author: nil,
                            status: "unknown", genres: [],
                            inLibrary: false, lastReadAt: nil,
                            lastUpdatedAt: nil, readingSeconds: 0,
                            readingStatus: .none
                        )
                        NovelCoverCell(novel: novel, bridge: section.bridge)
                    }
                } else {
                    ForEach(section.mangas) { manga in
                        MangaCoverCell(manga: manga)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: Search logic

    private func scheduleSearch(query: String) {
        debounceTask?.cancel()
        guard query.count >= 2 else {
            sections = []
            pendingCount = 0
            return
        }
        sections = []
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await runParallelSearch(query: query)
        }
    }

    private func runParallelSearch(query: String) async {
        let sources = extensionManager.installed
        await MainActor.run { pendingCount = sources.count }

        await withTaskGroup(of: SearchSection?.self) { group in
            for ext in sources {
                group.addTask {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let url = docs
                        .appendingPathComponent("Extensions", isDirectory: true)
                        .appendingPathComponent("\(ext.id).js")
                    guard let bridge = JSBridge(scriptURL: url) else { return nil }
                    if bridge.isLNReaderPlugin {
                        let items = bridge.searchNovels(query: query, page: 1)
                        guard !items.isEmpty else { return nil }
                        return SearchSection(id: ext.id, sourceName: ext.name, isNovel: true,
                                            mangas: [], novels: items, bridge: bridge)
                    } else {
                        let items = bridge.searchManga(query: query, page: 1, sourceId: ext.id)
                        guard !items.isEmpty else { return nil }
                        return SearchSection(id: ext.id, sourceName: ext.name, isNovel: false,
                                            mangas: items, novels: [], bridge: bridge)
                    }
                }
            }
            for await result in group {
                await MainActor.run {
                    pendingCount = max(0, pendingCount - 1)
                    if let section = result {
                        sections.append(section)
                    }
                }
            }
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
                    .padding(.bottom, 8)

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
                Novel(id: "\(sourceId)_\(item.path)", path: item.path, sourceId: sourceId,
                      title: item.name, coverURL: URL(string: item.cover ?? ""),
                      summary: nil, author: nil, status: "unknown", genres: [],
                      inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
                      readingSeconds: 0, readingStatus: .none)
            }
        } else {
            isNovelSource = false
            let currentFeed = selectedFeed
            let (results, hasLatest) = await Task.detached(priority: .userInitiated) {
                let hasLatest = b.supportsLatest
                let list: [Manga]
                if hasLatest && currentFeed == .latest {
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
                    Novel(id: "\(sourceId)_\(item.path)", path: item.path, sourceId: sourceId,
                          title: item.name, coverURL: URL(string: item.cover ?? ""),
                          summary: nil, author: nil, status: "unknown", genres: [],
                          inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
                          readingSeconds: 0, readingStatus: .none)
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
                AsyncImage(url: novel.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    default:
                        Color.secondary.opacity(0.3)
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
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
