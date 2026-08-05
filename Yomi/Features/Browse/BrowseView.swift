import SwiftUI
import Kingfisher

// MARK: - BrowseView
//
// Design spec: YOMI Screens.dc.html N.06 (Browse) + N.16 (Browse — search).
// Extension/repo management (install, add repo, update, delete) lives entirely in
// More → Plugins (PluginsView) — Browse only consumes already-installed sources.

struct BrowseView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var settings         = AppSettings.shared
    @Environment(\.yomiCanvas) private var canvas
    @State private var suwayomiSources: [SuwayomiSource] = []
    @State private var suwayomiLoading  = false
    @State private var opdsRootFeed: OPDSFeed? = nil
    @State private var opdsLoading = false
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            sourcesTab
                .navigationTitle("Browse")
                .navigationDestination(isPresented: $showSearch) { SearchScreen() }
        }
    }

    // MARK: Sources

    @ViewBuilder
    private var sourcesTab: some View {
        let hasSuwayomi = SuwayomiService.shared.isEnabled
        let hasOPDS     = OPDSService.shared.isEnabled
        if extensionManager.installed.isEmpty && !hasSuwayomi && !hasOPDS {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    searchPillAndSegmented
                    installedSection
                    if hasSuwayomi { suwayomiSection }
                    if hasOPDS { opdsSection }
                    if let firstExt = extensionManager.installed.first {
                        PopularSourceCarousel(ext: firstExt)
                    }
                    Color.clear.frame(height: 24)
                }
            }
            .task {
                if hasSuwayomi && suwayomiSources.isEmpty { await loadSuwayomiSources() }
                if hasOPDS && opdsRootFeed == nil { await loadOPDSRoot() }
            }
        }
    }

    private var emptyState: some View {
        YomiEmptyState(
            systemImage: "puzzlepiece.extension",
            title: "No sources installed",
            message: "Go to More → Plugins to discover and install sources.",
            actionLabel: "Open Plugins",
            actionIcon: "puzzlepiece.extension"
        ) {
            appRouter.openMorePlugins = true
            appRouter.selectedTab = AppRouter.tabMore
        }
    }

    // MARK: Search pill + segmented control (N.06)

    private var searchPillAndSegmented: some View {
        VStack(spacing: 14) {
            Button { showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                    Text("Search all sources")
                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.callout))
                    Spacer()
                }
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(canvas.surface2, in: Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                segmentButton(title: "Sources", isSelected: true) {}
                segmentButton(title: "Global search", isSelected: false) { showSearch = true }
            }
            .padding(3)
            .background(canvas.surface2, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func segmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.footnote, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : canvas.textSecondary)
                .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Installed section

    @ViewBuilder
    private var installedSection: some View {
        if !extensionManager.installed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("INSTALLED · \(extensionManager.installed.count)")
                    .font(YomiTokens.Font.mono(11))
                    .tracking(0.6)
                    .foregroundStyle(canvas.textSecondary)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(extensionManager.installed) { ext in
                        NavigationLink {
                            SourceBrowseView(ext: ext)
                        } label: {
                            SourceRow(ext: ext)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                extensionManager.remove(ext)
                            } label: {
                                Label("Uninstall", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 22)
        }
    }

    // MARK: Suwayomi section

    @ViewBuilder
    private var suwayomiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUWAYOMI SERVER")
                .font(YomiTokens.Font.mono(11))
                .tracking(0.6)
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 16)

            if suwayomiLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if suwayomiSources.isEmpty {
                Button("Load sources") { Task { await loadSuwayomiSources() } }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(suwayomiSources) { src in
                        NavigationLink {
                            SuwayomiBrowseView(source: src)
                        } label: {
                            HStack(spacing: 12) {
                                KFImage(URL(string: "\(SuwayomiService.shared.baseURL)\(src.iconUrl)"))
                                    .placeholder { Image(systemName: "network").foregroundStyle(canvas.textSecondary) }
                                    .fade(duration: 0.2)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(src.name)
                                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                                        .foregroundStyle(canvas.textPrimary)
                                    Text(src.lang.uppercased())
                                        .font(YomiTokens.Font.mono(11))
                                        .foregroundStyle(canvas.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(canvas.textSecondary.opacity(0.6))
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) { Rectangle().fill(canvas.hairline).frame(height: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 22)
    }

    // MARK: OPDS section

    @ViewBuilder
    private var opdsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OPDS LIBRARY")
                .font(YomiTokens.Font.mono(11))
                .tracking(0.6)
                .foregroundStyle(canvas.textSecondary)
                .padding(.horizontal, 16)

            if opdsLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if let feed = opdsRootFeed {
                VStack(spacing: 0) {
                    ForEach(feed.entries) { entry in
                        NavigationLink {
                            OPDSBrowseView(title: entry.title, feedHref: entry.navigationHref ?? OPDSService.shared.baseURL)
                        } label: {
                            opdsRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                Button("Load library") { Task { await loadOPDSRoot() } }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 22)
    }

    private func opdsRow(entry: OPDSEntry) -> some View {
        HStack(spacing: 12) {
            if let coverURL = OPDSService.shared.coverURL(for: entry) {
                KFImage(coverURL)
                    .placeholder { Image(systemName: "folder").foregroundStyle(canvas.textSecondary) }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                Image(systemName: "folder")
                    .frame(width: 36, height: 36)
                    .foregroundStyle(canvas.textSecondary)
            }
            Text(entry.title)
                .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                .foregroundStyle(canvas.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(canvas.textSecondary.opacity(0.6))
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(canvas.hairline).frame(height: 1) }
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

    private func loadOPDSRoot() async {
        opdsLoading = true
        do {
            let feed = try await OPDSService.shared.fetchFeed(href: OPDSService.shared.baseURL)
            await MainActor.run {
                opdsRootFeed = feed
                opdsLoading  = false
            }
        } catch {
            await MainActor.run { opdsLoading = false }
        }
    }
}

// MARK: - SourceIconBadge
//
// Gradient-initials icon chip (N.06 installed-source rows). Falls back to a stable,
// name-derived gradient + initials when the source has no icon or it fails to load.

private struct SourceIconBadge: View {
    let name: String
    let iconURL: URL?
    var size: CGFloat = 36

    private static let gradients: [[Color]] = [
        [Color(hex: "#7A1C14"), Color(hex: "#C23A2B")],
        [Color(hex: "#1C4A63"), Color(hex: "#2F7EA0")],
        [Color(hex: "#324E7A"), Color(hex: "#5878B0")],
        [Color(hex: "#4A3D22"), Color(hex: "#7D6A3A")],
        [Color(hex: "#265036"), Color(hex: "#3F8058")],
        [Color(hex: "#5F2749"), Color(hex: "#A6427E")],
    ]

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private var gradient: [Color] {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return SourceIconBadge.gradients[sum % SourceIconBadge.gradients.count]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let iconURL {
                KFImage(iconURL)
                    .placeholder { initialsText }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }

    private var initialsText: some View {
        Text(initials)
            .font(YomiTokens.Font.mono(13, bold: true))
            .foregroundStyle(.white)
    }
}

// MARK: - SourceRow

private struct SourceRow: View {
    let ext: Extension
    @State private var isNovelPlugin: Bool? = nil
    @Environment(\.yomiCanvas) private var canvas

    private var subtitle: String {
        var parts = [ext.language.uppercased()]
        if let isNovel = isNovelPlugin {
            parts.append(isNovel ? "NOVELS" : "MANGA")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            SourceIconBadge(name: ext.name, iconURL: ext.iconURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(YomiTokens.Font.mono(11))
                        .foregroundStyle(canvas.textSecondary)
                    if ext.isNSFW {
                        Text("18+")
                            .font(YomiTokens.Font.mono(10, bold: true))
                            .foregroundStyle(.red)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(canvas.textSecondary.opacity(0.6))
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(canvas.hairline).frame(height: 1) }
        .task(id: ext.id) {
            let id = ext.id
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("Extensions/\(id).js")
            isNovelPlugin = (try? String(contentsOf: url, encoding: .utf8))?.contains("popularNovels") ?? false
        }
    }
}

// MARK: - PopularSourceCarousel

private struct PopularSourceCarousel: View {
    let ext: Extension
    @Environment(\.yomiCanvas) private var canvas
    @State private var mangas: [Manga] = []
    @State private var novels: [Novel] = []
    @State private var isNovel = false
    @State private var bridge: JSBridge? = nil
    @State private var loaded = false

    private var hasContent: Bool {
        loaded && (isNovel ? !novels.isEmpty : !mangas.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasContent {
                HStack(alignment: .lastTextBaseline) {
                    Text("Popular on \(ext.name)")
                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.title2, weight: .medium))
                        .foregroundStyle(canvas.textPrimary)
                    Spacer()
                    NavigationLink {
                        SourceBrowseView(ext: ext)
                    } label: {
                        Text("See all")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(canvas.textSecondary)
                    }
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if isNovel, let b = bridge {
                            ForEach(novels) { novel in
                                NovelCoverCell(novel: novel, bridge: b)
                                    .frame(width: 104)
                            }
                        } else {
                            ForEach(mangas) { manga in
                                MangaCoverCell(manga: manga)
                                    .frame(width: 104)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, hasContent ? 22 : 0)
        .task(id: ext.id) { await load() }
    }

    private func load() async {
        loaded = false
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Extensions/\(ext.id).js")
        guard let b = JSBridge(scriptURL: url) else { loaded = true; return }
        bridge = b
        let sourceId = ext.id
        if b.isLNReaderPlugin {
            isNovel = true
            let items = await Task.detached(priority: .userInitiated) { b.popularNovels(page: 1) }.value
            novels = items.prefix(10).map { item in
                Novel(id: "\(sourceId)_\(item.path)", path: item.path, sourceId: sourceId,
                      title: item.name, coverURL: URL(string: item.cover ?? ""),
                      summary: nil, author: nil, status: "unknown", genres: [],
                      inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
                      readingSeconds: 0, readingStatus: .none, notes: nil)
            }
        } else {
            isNovel = false
            let results = await Task.detached(priority: .userInitiated) { b.getMangaList(page: 1, sourceId: sourceId) }.value
            mangas = Array(results.prefix(10))
        }
        loaded = true
    }
}

// MARK: - SearchScreen

private struct SearchScreen: View {
    var body: some View {
        GlobalSearchView()
    }
}

// MARK: - GlobalSearchView

private struct GlobalSearchView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var searchQuery = ""
    @State private var isSearchPresented = true
    @State private var sections: [SearchSection] = []
    @State private var pendingCount = 0
    @State private var debounceTask: Task<Void, Never>? = nil
    @Environment(\.yomiCanvas) private var canvas

    struct SearchSection: Identifiable {
        let id: String
        let sourceName: String
        let isNovel: Bool
        let mangas: [Manga]
        let novels: [NovelItem]
        let bridge: JSBridge
    }

    var body: some View {
        Group {
            if extensionManager.installed.isEmpty {
                YomiEmptyState(
                    systemImage: "puzzlepiece.extension",
                    title: "No sources installed",
                    message: "Install a source from More → Plugins before searching."
                )
            } else if pendingCount > 0 && sections.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching \(pendingCount) source\(pendingCount == 1 ? "" : "s")…")
                        .font(YomiTokens.Font.mono(12))
                        .foregroundStyle(canvas.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !sections.isEmpty {
                resultsList
            } else if searchQuery.count >= 2 {
                ContentUnavailableView.search(text: searchQuery)
            } else if searchQuery.isEmpty {
                YomiEmptyState(
                    systemImage: "magnifyingglass",
                    title: "Search all sources",
                    message: "Results stream in from all your installed sources."
                )
            } else {
                YomiEmptyState(
                    systemImage: "magnifyingglass",
                    title: "Keep typing",
                    message: "Type at least 2 characters to search."
                )
            }
        }
        .navigationTitle("Search")
        .searchable(text: $searchQuery, isPresented: $isSearchPresented, prompt: "Search titles")
        .onChange(of: searchQuery) { _, newValue in
            scheduleSearch(query: newValue)
        }
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    sectionView(section)
                }
                if pendingCount > 0 {
                    HStack {
                        ProgressView()
                        Text("Searching \(pendingCount) more…")
                            .font(YomiTokens.Font.mono(12))
                            .foregroundStyle(canvas.textSecondary)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(section.sourceName)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.headline, weight: .medium))
                    .foregroundStyle(canvas.textPrimary)
                Spacer()
                Text("\(section.isNovel ? section.novels.count : section.mangas.count)")
                    .font(YomiTokens.Font.mono(11))
                    .foregroundStyle(canvas.textSecondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if section.isNovel {
                        ForEach(section.novels, id: \.path) { item in
                            let novel = Novel(
                                id: "\(section.id)_\(item.path)", path: item.path, sourceId: section.id,
                                title: item.name, coverURL: URL(string: item.cover ?? ""),
                                summary: nil, author: nil,
                                status: "unknown", genres: [],
                                inLibrary: false, lastReadAt: nil,
                                lastUpdatedAt: nil, readingSeconds: 0,
                                readingStatus: .none, notes: nil
                            )
                            NovelCoverCell(novel: novel, bridge: section.bridge)
                                .frame(width: 108)
                        }
                    } else {
                        ForEach(section.mangas) { manga in
                            MangaCoverCell(manga: manga)
                                .frame(width: 108)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
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
                let extId   = ext.id
                let extName = ext.name
                group.addTask {
                    await Task.detached(priority: .userInitiated) {
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let url = docs
                            .appendingPathComponent("Extensions", isDirectory: true)
                            .appendingPathComponent("\(extId).js")
                        guard let bridge = JSBridge(scriptURL: url) else { return nil }
                        if bridge.isLNReaderPlugin {
                            let items = bridge.searchNovels(query: query, page: 1)
                            guard !items.isEmpty else { return nil }
                            return SearchSection(id: extId, sourceName: extName, isNovel: true,
                                                mangas: [], novels: items, bridge: bridge)
                        } else {
                            let items = bridge.searchManga(query: query, page: 1, sourceId: extId)
                            guard !items.isEmpty else { return nil }
                            return SearchSection(id: extId, sourceName: extName, isNovel: false,
                                                mangas: items, novels: [], bridge: bridge)
                        }
                    }.value
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
    @State private var autoBypassFailed = false

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
                YomiEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Failed to load",
                    message: error
                )
            } else if isContentEmpty && searchText.isEmpty {
                YomiEmptyState(
                    systemImage: "books.vertical",
                    title: "No titles found",
                    message: "This source returned no results. The site may be down or Cloudflare-protected.",
                    actionLabel: "Try again",
                    actionIcon: "arrow.clockwise"
                ) {
                    Task { await loadWithBypass() }
                }
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
            if supportsLatest {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if autoBypassFailed {
                HStack(spacing: 10) {
                    Image(systemName: "shield.slash").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-bypass failed")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Tap the shield button to bypass manually.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { autoBypassFailed = false } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
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
        autoBypassFailed = false
        await loadContent()
        guard isContentEmpty, !bypassAttempted,
              let cfURL = bridge?.cfBlockedURL,
              let url = URL(string: cfURL) else { return }
        bypassAttempted = true
        isBypassing = true
        let success = await CFBypassManager.autoBypass(url: url)
        bridge?.clearCFBlock()
        isBypassing = false
        if success {
            await loadContent()
        } else {
            autoBypassFailed = true
        }
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
            supportsLatest = true
            let currentFeed = selectedFeed
            let items = await Task.detached(priority: .userInitiated) {
                currentFeed == .latest ? b.latestNovels(page: 1) : b.popularNovels(page: 1)
            }.value
            novels = items.map { item in
                Novel(id: "\(sourceId)_\(item.path)", path: item.path, sourceId: sourceId,
                      title: item.name, coverURL: URL(string: item.cover ?? ""),
                      summary: nil, author: nil, status: "unknown", genres: [],
                      inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
                      readingSeconds: 0, readingStatus: .none, notes: nil)
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
                feed == .latest ? b.latestNovels(page: nextPage) : b.popularNovels(page: nextPage)
            }.value
            if items.isEmpty {
                hasMoreContent = false
            } else {
                let newNovels = items.map { item in
                    Novel(id: "\(sourceId)_\(item.path)", path: item.path, sourceId: sourceId,
                          title: item.name, coverURL: URL(string: item.cover ?? ""),
                          summary: nil, author: nil, status: "unknown", genres: [],
                          inLibrary: false, lastReadAt: nil, lastUpdatedAt: nil,
                          readingSeconds: 0, readingStatus: .none, notes: nil)
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
    @State private var dbInLibrary: Bool = false
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        NavigationLink {
            NovelDetailView(novel: novel, bridge: bridge)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                CoverImage(url: novel.coverURL)
                    .cornerRadius(YomiTokens.Radius.cover)
                    .clipped()
                .overlay(alignment: .topLeading) {
                    if !novel.inLibrary && dbInLibrary {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.accentColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                            .padding(5)
                    }
                }

                Text(novel.title)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.footnote))
                    .lineLimit(2)
                    .foregroundStyle(canvas.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .task(id: novel.id) {
            dbInLibrary = await Task.detached {
                (try? NovelQueries.fetchOne(id: novel.id))?.inLibrary ?? false
            }.value
        }
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
