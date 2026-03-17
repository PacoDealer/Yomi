import SwiftUI

// MARK: - BrowseView

struct BrowseView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var selectedTab: BrowseTab = .sources

    enum BrowseTab: String, CaseIterable {
        case sources = "Sources"
        case search  = "Search"
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
                case .sources: sourcesTab
                case .search:  SearchView()
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Sources tab

    @ViewBuilder
    private var sourcesTab: some View {
        if extensionManager.installed.isEmpty {
            ContentUnavailableView(
                "No sources installed",
                systemImage: "puzzlepiece.extension",
                description: Text("Go to More → Plugins to install sources.")
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
}

// MARK: - SearchView

private struct SearchView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var globalSearch = ""
    @State private var searchResults: [Manga] = []
    @State private var isSearching = false
    @State private var selectedSource: Extension? = nil
    @State private var hasSearched = false

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)
    ]

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
            } else if hasSearched && searchResults.isEmpty {
                ContentUnavailableView.search(text: globalSearch)
            } else if searchResults.isEmpty {
                ContentUnavailableView(
                    "Search titles",
                    systemImage: "magnifyingglass",
                    description: Text("Results from your installed sources will appear here.")
                )
            } else {
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
        .searchable(text: $globalSearch, prompt: "Search titles")
        .onSubmit(of: .search) { Task { await performSearch() } }
    }

    // MARK: Perform Search

    private func performSearch() async {
        guard !globalSearch.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            hasSearched = false
            return
        }
        isSearching = true
        hasSearched = true
        let query = globalSearch
        let sources = selectedSource.map { [$0] } ?? extensionManager.installed
        let results = await Task.detached {
            sources.flatMap { ext in
                JSBridge(scriptURL: ext.sourceListURL)?
                    .getMangaList(page: 1, sourceId: ext.id)
                    .filter { $0.title.localizedStandardContains(query) }
                ?? []
            }
        }.value
        searchResults = results
        isSearching = false
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

    // MARK: State

    @State private var mangas: [Manga] = []
    @State private var novels: [Novel] = []
    @State private var bridge: JSBridge? = nil
    @State private var isNovelSource = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""

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
                }
            }
        }
        .navigationTitle(ext.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search \(ext.name)")
        .task { await loadContent() }
    }

    // MARK: Load Content

    private func loadContent() async {
        isLoading = true
        errorMessage = nil
        let sourceId  = ext.id
        let scriptURL = ext.sourceListURL

        let loadedBridge = await Task.detached(priority: .userInitiated) {
            JSBridge(scriptURL: scriptURL)
        }.value

        guard let b = loadedBridge else {
            errorMessage = "Failed to load source plugin."
            isLoading = false
            return
        }

        bridge = b

        if b.isLNReaderPlugin {
            isNovelSource = true
            let items = await Task.detached(priority: .userInitiated) {
                b.popularNovels(page: 1)
            }.value
            novels = items.map { item in
                Novel(
                    id:            UUID().uuidString,
                    path:          item.path,
                    sourceId:      sourceId,
                    title:         item.name,
                    coverURL:      URL(string: item.cover ?? ""),
                    summary:       nil,
                    author:        nil,
                    status:        "unknown",
                    genres:        [],
                    inLibrary:      false,
                    lastReadAt:     nil,
                    lastUpdatedAt:  nil,
                    readingSeconds: 0
                )
            }
        } else {
            isNovelSource = false
            let results = await Task.detached(priority: .userInitiated) {
                b.getMangaList(page: 1, sourceId: sourceId)
            }.value
            mangas = results
        }

        isLoading = false
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
