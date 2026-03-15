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
            Group {
                switch selectedTab {
                case .sources: sourcesTab
                case .search:  searchTab
                }
            }
            .navigationTitle("Browse")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(BrowseTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
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

    // MARK: Search tab

    private var searchTab: some View {
        ContentUnavailableView(
            "Global search coming soon",
            systemImage: "magnifyingglass",
            description: Text("Search across all installed sources will be available in a future update.")
        )
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

    @State private var mangas: [Manga] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)
    ]

    private var filteredMangas: [Manga] {
        guard !searchText.isEmpty else { return mangas }
        return mangas.filter { $0.title.localizedStandardContains(searchText) }
    }

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
            } else if filteredMangas.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "No titles found",
                    systemImage: "books.vertical",
                    description: Text("This source returned no results.")
                )
            } else if filteredMangas.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredMangas) { manga in
                            MangaCoverCell(manga: manga)
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
        .task { await loadMangas() }
    }

    private func loadMangas() async {
        isLoading = true
        errorMessage = nil
        let sourceId = ext.id
        let scriptURL = ext.sourceListURL
        let results = await Task.detached(priority: .userInitiated) {
            JSBridge(scriptURL: scriptURL)?.getMangaList(page: 1, sourceId: sourceId) ?? []
        }.value
        mangas = results
        isLoading = false
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
