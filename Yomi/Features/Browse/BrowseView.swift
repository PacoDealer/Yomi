import SwiftUI

// MARK: - BrowseView

struct BrowseView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var catalogService   = PluginCatalogService.shared
    @State private var settings         = AppSettings.shared
    @State private var selectedTab: BrowseTab = .sources
    @State private var installingID: String? = nil
    @State private var suwayomiSources: [SuwayomiSource] = []
    @State private var suwayomiLoading  = false
    @State private var extensionsSearch = ""
    @State private var langPickerGroup: PluginCatalogGroup? = nil
    @State private var selectedRepos: Set<String> = []

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
            .searchable(
                text: $extensionsSearch,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search extensions"
            )
            .onChange(of: appRouter.openBrowseExtensions) { _, open in
                if open {
                    selectedTab = .extensions
                    appRouter.openBrowseExtensions = false
                }
            }
        }
        // Language picker for multi-lang sources
        .confirmationDialog(
            langPickerGroup.map { "Install \($0.name)" } ?? "",
            isPresented: Binding(get: { langPickerGroup != nil }, set: { if !$0 { langPickerGroup = nil } }),
            titleVisibility: .visible
        ) {
            if let group = langPickerGroup {
                ForEach(group.entries) { entry in
                    let installed = catalogService.isInstalled(entry)
                    Button(installed ? "\(entry.language.uppercased()) — Installed" : entry.language.uppercased()) {
                        if !installed { Task { await installEntry(entry) } }
                    }
                    .disabled(installed)
                }
                Button("Cancel", role: .cancel) {}
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
                description: Text("Go to the Extensions tab to discover and install sources.")
            )
            .onTapGesture { selectedTab = .extensions }
        } else {
            List {
                if !extensionManager.installed.isEmpty {
                    Section {
                        ForEach(extensionManager.installed) { ext in
                            NavigationLink {
                                SourceBrowseView(ext: ext)
                            } label: {
                                ExtensionRow(ext: ext)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    extensionManager.remove(ext)
                                } label: {
                                    Label("Uninstall", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Installed (\(extensionManager.installed.count))")
                            Spacer()
                            Button("Get more") { selectedTab = .extensions }
                                .font(.caption)
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
            } else if filteredGroups.isEmpty && !catalogService.entries.isEmpty {
                ContentUnavailableView.search(text: extensionsSearch)
            } else if filteredGroups.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        Text("No extensions available")
                            .font(.title3).fontWeight(.semibold)
                        Text("Add a repository in More → Plugins to discover sources.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if availableRepos.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                RepoFilterChip(label: "All", isSelected: selectedRepos.isEmpty) {
                                    selectedRepos = []
                                }
                                ForEach(availableRepos, id: \.self) { repo in
                                    RepoFilterChip(label: repo, isSelected: selectedRepos.contains(repo)) {
                                        if selectedRepos.contains(repo) {
                                            selectedRepos.remove(repo)
                                        } else {
                                            selectedRepos.insert(repo)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        Divider()
                    }
                    List(filteredGroups) { group in
                        CatalogGroupRow(
                            group:        group,
                            isInstalled:  catalogService.isGroupInstalled(group),
                            installingID: installingID
                        ) {
                            if group.isMultiLang {
                                langPickerGroup = group
                            } else {
                                Task { await installEntry(group.primaryEntry) }
                            }
                        }
                    }
                    .refreshable { await catalogService.fetchCatalog(force: true) }
                }
            }
        }
        .task { await catalogService.fetchCatalog() }
    }

    private var availableRepos: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in catalogService.entries {
            let label = PluginCatalogService.repoLabel(from: entry.repoURL)
            guard !label.isEmpty, seen.insert(label).inserted else { continue }
            result.append(label)
        }
        return result.sorted()
    }

    private var filteredGroups: [PluginCatalogGroup] {
        var groups = settings.showNSFW
            ? catalogService.groupedEntries
            : catalogService.groupedEntries.filter { !$0.primaryEntry.isNSFW }
        if !selectedRepos.isEmpty {
            groups = groups.filter { selectedRepos.contains(PluginCatalogService.repoLabel(from: $0.primaryEntry.repoURL)) }
        }
        if !extensionsSearch.isEmpty {
            groups = groups.filter { $0.name.localizedStandardContains(extensionsSearch) }
        }
        return groups
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

// MARK: - RepoFilterChip

struct RepoFilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline).fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CatalogGroupRow

struct CatalogGroupRow: View {
    let group:        PluginCatalogGroup
    let isInstalled:  Bool
    let installingID: String?
    let onInstall:    () -> Void

    private var isInstalling: Bool {
        group.entries.contains { $0.id == installingID }
    }
    private var repoLabel: String {
        PluginCatalogService.repoLabel(from: group.primaryEntry.repoURL)
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: group.primaryEntry.iconURL.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(1, contentMode: .fit)
            } placeholder: {
                Image(systemName: "puzzlepiece.extension")
                    .resizable().aspectRatio(1, contentMode: .fit)
                    .padding(8)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.12))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.headline)
                HStack(spacing: 5) {
                    if group.isMultiLang {
                        Text("\(group.entries.count) langs")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    } else {
                        LanguageBadge(language: group.primaryEntry.language)
                    }
                    if group.primaryEntry.isNSFW { NSFWBadge() }
                    if !repoLabel.isEmpty {
                        Text(repoLabel)
                            .font(.caption2).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                    Text("v\(group.primaryEntry.version)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isInstalled {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if isInstalling {
                ProgressView().scaleEffect(0.8)
            } else {
                Button(group.isMultiLang ? "Get" : "Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
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
    @State private var showCFBypass = false
    @State private var bypassAttempted = false
    @State private var isBypassing = false

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
        .task { await loadWithBypass() }
        .overlay {
            if isBypassing {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Bypassing Cloudflare…")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCFBypass = true
                } label: {
                    Image(systemName: "shield.slash")
                }
                .help("Bypass Cloudflare")
            }
        }
        .sheet(isPresented: $showCFBypass) {
            CFBypassView(initialURL: bridge?.cfBlockedURL ?? "https://") {
                Task { await loadContent() }
            }
        }
    }

    // MARK: Load With Auto-Bypass

    private func loadWithBypass() async {
        bypassAttempted = false
        await loadContent()
        guard isContentEmpty, !bypassAttempted,
              let cfURL = bridge?.cfBlockedURL,
              let url = URL(string: cfURL) else { return }
        bypassAttempted = true
        isBypassing = true
        let success = await CFBypassManager.autoBypass(url: url)
        bridge?.clearCFBlock()
        isBypassing = false
        if success { await loadContent() }
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
