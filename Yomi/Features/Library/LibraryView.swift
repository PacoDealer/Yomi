import SwiftUI
import Kingfisher

struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    @State private var extensionManager = ExtensionManager.shared
    @State private var settings = AppSettings.shared
    @Environment(\.yomiCanvas) private var canvas
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var selectedNovelIds: Set<String> = []
    @State private var showNewCategorySheet = false
    @State private var newCategoryName = ""
    @State private var selectedNovel: Novel? = nil
    @State private var showNovelDetail = false
    @State private var randomMangaDest: Manga? = nil
    @State private var showRandomManga = false
    @State private var deepLinkManga: Manga? = nil
    @State private var showDeepLinkManga = false
    var onBrowseTap: (() -> Void)? = nil

    init(viewModel: LibraryViewModel = LibraryViewModel(), onBrowseTap: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onBrowseTap = onBrowseTap
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: max(2, settings.libraryColumns))
    }

    var body: some View {
        NavigationStack {
            Group {
                let hasAnyContent = !viewModel.displayedManga.isEmpty || !viewModel.displayedNovels.isEmpty
                if !hasAnyContent && viewModel.searchText.isEmpty && viewModel.selectedCategoryId == nil {
                    if extensionManager.installed.isEmpty {
                        YomiEmptyState(
                            systemImage: "puzzlepiece.extension",
                            title: "No plugins installed",
                            message: "Plugins connect Yomi to manga and novel sources. Install one to start reading.",
                            actionLabel: "Get plugins",
                            actionIcon: "puzzlepiece.extension"
                        ) {
                            appRouter.openMorePlugins = true
                            appRouter.selectedTab = AppRouter.tabMore
                        }
                    } else {
                        YomiEmptyState(
                            systemImage: "magnifyingglass",
                            title: "Your library is empty",
                            message: "Titles you add from Browse will live here as a catalog — with covers, progress and notation.",
                            actionLabel: "Browse sources",
                            actionIcon: "magnifyingglass"
                        ) {
                            appRouter.selectedTab = AppRouter.tabBrowse
                        }
                    }
                } else if !hasAnyContent {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if !isSelecting { ContinueReadingRow() }
                            if !viewModel.displayedManga.isEmpty {
                                // Show "Manga" header only when novels are also present
                                if !viewModel.displayedNovels.isEmpty {
                                    HStack(alignment: .lastTextBaseline) {
                                        Text("Manga")
                                            .font(YomiTokens.Font.grotesk(22, weight: .medium))
                                            .foregroundStyle(canvas.textPrimary)
                                        Spacer()
                                        Text("\(viewModel.displayedManga.count)")
                                            .font(YomiTokens.Font.mono(12))
                                            .foregroundStyle(canvas.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                }
                                if settings.libraryDisplayMode == "list" {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.displayedManga) { manga in
                                            ZStack(alignment: .leading) {
                                                NavigationLink(destination: MangaDetailView(manga: manga)) {
                                                    MangaListRow(manga: manga,
                                                                 unreadCount: viewModel.unreadCounts[manga.id] ?? 0,
                                                                 isSelecting: isSelecting,
                                                                 isSelected: selectedIds.contains(manga.id))
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(isSelecting)

                                                if isSelecting {
                                                    Color.clear
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            withAnimation(.spring(duration: 0.15)) {
                                                                if selectedIds.contains(manga.id) {
                                                                    selectedIds.remove(manga.id)
                                                                } else {
                                                                    selectedIds.insert(manga.id)
                                                                }
                                                            }
                                                        }
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .contextMenu {
                                                if !isSelecting {
                                                    Button {
                                                        withAnimation(.spring(duration: 0.2)) {
                                                            isSelecting = true
                                                            selectedIds.insert(manga.id)
                                                        }
                                                    } label: {
                                                        Label("Select", systemImage: "checkmark.circle")
                                                    }
                                                    Menu {
                                                        ForEach(ReadingStatus.allCases) { status in
                                                            Button {
                                                                let id = manga.id
                                                                Task.detached { try? MangaQueries.updateReadingStatus(mangaId: id, status: status) }
                                                            } label: {
                                                                Label(status.label, systemImage: status.systemImage)
                                                            }
                                                        }
                                                    } label: {
                                                        Label("Reading Status", systemImage: "bookmark")
                                                    }
                                                    Divider()
                                                    Button(role: .destructive) {
                                                        let m = manga
                                                        Task.detached { try? MangaQueries.toggleLibrary(manga: m) }
                                                        Task { await viewModel.loadLibrary() }
                                                    } label: {
                                                        Label("Remove from Library", systemImage: "trash")
                                                    }
                                                }
                                            }
                                            Divider().padding(.leading, 76)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                } else {
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(Array(viewModel.displayedManga.enumerated()), id: \.element.id) { index, manga in
                                            MangaCoverCell(
                                                manga: manga,
                                                catalogIndex: index + 1,
                                                isSelecting: isSelecting,
                                                isSelected: selectedIds.contains(manga.id),
                                                onLongPress: {
                                                    withAnimation(.spring(duration: 0.2)) {
                                                        isSelecting = true
                                                        selectedIds.insert(manga.id)
                                                    }
                                                },
                                                onSelect: {
                                                    withAnimation(.spring(duration: 0.15)) {
                                                        if selectedIds.contains(manga.id) {
                                                            selectedIds.remove(manga.id)
                                                        } else {
                                                            selectedIds.insert(manga.id)
                                                        }
                                                    }
                                                },
                                                onReadingStatusChange: { status in
                                                    let id = manga.id
                                                    Task.detached { try? MangaQueries.updateReadingStatus(mangaId: id, status: status) }
                                                },
                                                onRemoveFromLibrary: {
                                                    let m = manga
                                                    Task.detached { try? MangaQueries.toggleLibrary(manga: m) }
                                                    Task { await viewModel.loadLibrary() }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.top, 4)
                                }
                            }
                            if !viewModel.displayedNovels.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .lastTextBaseline) {
                                        Text("Novels")
                                            .font(YomiTokens.Font.grotesk(22, weight: .medium))
                                            .foregroundStyle(canvas.textPrimary)
                                        Spacer()
                                        Text("\(viewModel.displayedNovels.count)")
                                            .font(YomiTokens.Font.mono(12))
                                            .foregroundStyle(canvas.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, viewModel.displayedManga.isEmpty ? 8 : 16)
                                    if settings.libraryDisplayMode == "list" {
                                        LazyVStack(spacing: 0) {
                                            ForEach(viewModel.displayedNovels) { novel in
                                                ZStack(alignment: .leading) {
                                                    Button { selectedNovel = novel; showNovelDetail = true } label: {
                                                        NovelLibraryListRow(
                                                            novel: novel,
                                                            unreadCount: viewModel.novelUnreadCounts[novel.id] ?? 0,
                                                            isSelecting: isSelecting,
                                                            isSelected: selectedNovelIds.contains(novel.id)
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                    .disabled(isSelecting)

                                                    if isSelecting {
                                                        Color.clear
                                                            .contentShape(Rectangle())
                                                            .onTapGesture {
                                                                withAnimation(.spring(duration: 0.15)) {
                                                                    if selectedNovelIds.contains(novel.id) {
                                                                        selectedNovelIds.remove(novel.id)
                                                                    } else {
                                                                        selectedNovelIds.insert(novel.id)
                                                                    }
                                                                }
                                                            }
                                                    }
                                                }
                                                .contentShape(Rectangle())
                                                .contextMenu {
                                                    if !isSelecting {
                                                    Button {
                                                        withAnimation(.spring(duration: 0.2)) {
                                                            isSelecting = true
                                                            selectedNovelIds.insert(novel.id)
                                                        }
                                                    } label: {
                                                        Label("Select", systemImage: "checkmark.circle")
                                                    }
                                                    Menu {
                                                        ForEach(ReadingStatus.allCases) { status in
                                                            Button {
                                                                let id = novel.id
                                                                Task.detached { try? NovelQueries.updateReadingStatus(novelId: id, status: status) }
                                                            } label: {
                                                                Label(status.label, systemImage: status.systemImage)
                                                            }
                                                        }
                                                    } label: {
                                                        Label("Reading Status", systemImage: "bookmark")
                                                    }
                                                    Divider()
                                                    Button(role: .destructive) {
                                                        var updated = novel
                                                        updated.inLibrary = false
                                                        Task.detached { try? NovelQueries.upsert(updated) }
                                                        Task { await viewModel.loadLibrary() }
                                                    } label: {
                                                        Label("Remove from Library", systemImage: "trash")
                                                    }
                                                    }
                                                }
                                                Divider().padding(.leading, 76)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    } else {
                                        LazyVGrid(columns: columns, spacing: 12) {
                                            ForEach(Array(viewModel.displayedNovels.enumerated()), id: \.element.id) { index, novel in
                                                NovelLibraryCoverCell(
                                                    novel: novel,
                                                    unreadCount: viewModel.novelUnreadCounts[novel.id] ?? 0,
                                                    onTap: { selectedNovel = novel; showNovelDetail = true },
                                                    catalogIndex: index + 1,
                                                    isSelecting: isSelecting,
                                                    isSelected: selectedNovelIds.contains(novel.id),
                                                    onLongPress: {
                                                        withAnimation(.spring(duration: 0.2)) {
                                                            isSelecting = true
                                                            selectedNovelIds.insert(novel.id)
                                                        }
                                                    },
                                                    onSelect: {
                                                        withAnimation(.spring(duration: 0.15)) {
                                                            if selectedNovelIds.contains(novel.id) {
                                                                selectedNovelIds.remove(novel.id)
                                                            } else {
                                                                selectedNovelIds.insert(novel.id)
                                                            }
                                                        }
                                                    },
                                                    onReadingStatusChange: { status in
                                                        let id = novel.id
                                                        Task.detached { try? NovelQueries.updateReadingStatus(novelId: id, status: status) }
                                                    },
                                                    onRemoveFromLibrary: {
                                                        var updated = novel
                                                        updated.inLibrary = false
                                                        Task.detached { try? NovelQueries.upsert(updated) }
                                                        Task { await viewModel.loadLibrary() }
                                                    }
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable { await viewModel.loadLibrary() }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 40, coordinateSpace: .local)
                            .onEnded { value in
                                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                                let tabIds: [String?] = [nil] + viewModel.categories.map { Optional($0.id) }
                                guard let idx = tabIds.firstIndex(where: { $0 == viewModel.selectedCategoryId }) else { return }
                                if value.translation.width < -50 && idx < tabIds.count - 1 {
                                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.selectedCategoryId = tabIds[idx + 1] }
                                } else if value.translation.width > 50 && idx > 0 {
                                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.selectedCategoryId = tabIds[idx - 1] }
                                }
                            }
                    )
                    .safeAreaInset(edge: .bottom) {
                        if isSelecting {
                            selectionActionBar
                        }
                    }
                }
            }
            .background(canvas.bg.ignoresSafeArea())
            .navigationTitle(isSelecting
                ? { let total = selectedIds.count + selectedNovelIds.count; return total == 0 ? "Select" : "\(total) selected" }()
                : "Library")
            .safeAreaInset(edge: .top, spacing: 0) {
                categoryTabBar
            }
            .searchable(text: $viewModel.searchText, prompt: "Search library")
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            withAnimation(.spring(duration: 0.2)) {
                                isSelecting = false
                                selectedIds = []
                                selectedNovelIds = []
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        let allManga = Set(viewModel.displayedManga.map { $0.id })
                        let allNovels = Set(viewModel.displayedNovels.map { $0.id })
                        let allSelected = selectedIds == allManga && selectedNovelIds == allNovels
                        Button(allSelected ? "Deselect All" : "Select All") {
                            withAnimation(.spring(duration: 0.15)) {
                                if allSelected {
                                    selectedIds = []
                                    selectedNovelIds = []
                                } else {
                                    selectedIds = allManga
                                    selectedNovelIds = allNovels
                                }
                            }
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            settings.libraryDisplayMode = settings.libraryDisplayMode == "grid" ? "list" : "grid"
                        } label: {
                            Image(systemName: settings.libraryDisplayMode == "grid" ? "list.bullet" : "square.grid.2x2")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let pick = viewModel.displayedManga.randomElement() {
                                randomMangaDest = pick
                                showRandomManga = true
                            }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .disabled(viewModel.displayedManga.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(SortOrder.allCases) { order in
                                Button {
                                    viewModel.sortOrder = order
                                } label: {
                                    Label(order.rawValue, systemImage: order.systemImage)
                                    if viewModel.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                            Button {
                                viewModel.statusFilter = nil
                            } label: {
                                Label("All statuses", systemImage: "line.3.horizontal.decrease")
                                if viewModel.statusFilter == nil { Image(systemName: "checkmark") }
                            }
                            ForEach(ReadingStatus.allCases.filter { $0 != .none }) { status in
                                Button {
                                    viewModel.statusFilter = viewModel.statusFilter == status ? nil : status
                                } label: {
                                    Label(status.label, systemImage: status.systemImage)
                                    if viewModel.statusFilter == status { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            let active = viewModel.sortOrder != .lastRead || viewModel.statusFilter != nil
                            Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showRandomManga) {
                if let manga = randomMangaDest {
                    MangaDetailView(manga: manga)
                }
            }
            .navigationDestination(isPresented: $showNovelDetail) {
                if let novel = selectedNovel {
                    NovelDetailView(novel: novel)
                }
            }
            .navigationDestination(isPresented: $showDeepLinkManga) {
                if let manga = deepLinkManga {
                    MangaDetailView(manga: manga)
                }
            }
            .onAppear { Task { await viewModel.loadLibrary() } }
            .onChange(of: appRouter.pendingOpenMangaId, initial: true) { _, id in
                guard let id else { return }
                appRouter.pendingOpenMangaId = nil
                Task.detached {
                    guard let manga = try? MangaQueries.fetchOne(id: id) else { return }
                    await MainActor.run {
                        deepLinkManga = manga
                        showDeepLinkManga = true
                    }
                }
            }
            .onChange(of: appRouter.pendingOpenNovelId, initial: true) { _, id in
                guard let id else { return }
                appRouter.pendingOpenNovelId = nil
                Task.detached {
                    guard let novel = try? NovelQueries.fetchOne(id: id) else { return }
                    await MainActor.run {
                        selectedNovel = novel
                        showNovelDetail = true
                    }
                }
            }
        }
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        let noneSelected = selectedIds.isEmpty && selectedNovelIds.isEmpty
        return HStack {
            Spacer()
            Button { Task { await markSelectedRead() } } label: {
                VStack(spacing: 3) {
                    Image(systemName: "checkmark").font(.title3)
                    Text("Mark read").font(YomiTokens.Font.grotesk(11, weight: .medium))
                }
            }
            .disabled(noneSelected)
            Spacer()
            Button { Task { await downloadSelected() } } label: {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.down").font(.title3)
                    Text("Download").font(YomiTokens.Font.grotesk(11, weight: .medium))
                }
            }
            .disabled(selectedIds.isEmpty)
            Spacer()
            Button { Task { await removeSelected() } } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash").font(.title3)
                    Text("Remove").font(YomiTokens.Font.grotesk(11, weight: .medium))
                }
            }
            .tint(Color.accentColor)
            .disabled(noneSelected)
            Spacer()
        }
        .frame(height: 60)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private func removeSelected() async {
        let ids = selectedIds
        let novelIds = selectedNovelIds
        await Task.detached(priority: .userInitiated) {
            for id in ids {
                guard var manga = try? MangaQueries.fetchOne(id: id) else { continue }
                manga.inLibrary = false
                try? MangaQueries.update(manga)
                let dir = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Downloads/\(id)")
                try? FileManager.default.removeItem(at: dir)
            }
            for id in novelIds {
                guard var novel = try? NovelQueries.fetchOne(id: id) else { continue }
                novel.inLibrary = false
                try? NovelQueries.upsert(novel)
            }
        }.value
        await viewModel.loadLibrary()
        withAnimation(.spring(duration: 0.2)) {
            isSelecting = false
            selectedIds = []
            selectedNovelIds = []
        }
    }

    private func markSelectedRead() async {
        let ids = selectedIds
        let novelIds = selectedNovelIds
        await Task.detached(priority: .userInitiated) {
            for id in ids { try? ChapterQueries.markAllRead(mangaId: id) }
            for id in novelIds { try? NovelQueries.markAllChapters(novelId: id, read: true) }
        }.value
        await viewModel.loadLibrary()
        withAnimation(.spring(duration: 0.2)) { isSelecting = false; selectedIds = []; selectedNovelIds = [] }
    }

    private func downloadSelected() async {
        let ids = selectedIds
        let installed = ExtensionManager.shared.installed
        let em = ExtensionManager.shared
        let mangasAndChapters: [(Manga, [Chapter])] = await Task.detached(priority: .userInitiated) {
            ids.compactMap { id -> (Manga, [Chapter])? in
                guard let manga = try? MangaQueries.fetchOne(id: id) else { return nil }
                let unread = (try? ChapterQueries.fetchUnread(mangaId: id)) ?? []
                return (manga, unread)
            }
        }.value
        for (manga, unread) in mangasAndChapters {
            guard let ext = installed.first(where: { $0.id == manga.sourceId }),
                  let bridge = em.bridge(for: ext) else { continue }
            unread.forEach { DownloadManager.shared.enqueue($0, manga: manga, bridge: bridge) }
        }
        withAnimation(.spring(duration: 0.2)) { isSelecting = false; selectedIds = []; selectedNovelIds = [] }
    }

    // MARK: - Category Tab Bar

    @ViewBuilder
    private var categoryTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    LibraryTab(
                        label: "All",
                        count: settings.showCategoryItemCounts ? viewModel.mangas.count + viewModel.novels.count : nil,
                        isSelected: viewModel.selectedCategoryId == nil
                    ) {
                        viewModel.selectedCategoryId = nil
                    }
                    .id("tab_all")
                    ForEach(viewModel.categories) { category in
                        LibraryTab(
                            label: category.name,
                            count: settings.showCategoryItemCounts ? viewModel.categoryItemCounts[category.id] ?? 0 : nil,
                            isSelected: viewModel.selectedCategoryId == category.id
                        ) {
                            viewModel.selectedCategoryId = category.id
                        }
                        .id("tab_\(category.id)")
                    }
                    Button {
                        newCategoryName = ""
                        showNewCategorySheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 4)
            }
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .onChange(of: viewModel.selectedCategoryId) { _, newId in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newId.map { "tab_\($0)" } ?? "tab_all", anchor: .center)
                }
            }
        }
        .sheet(isPresented: $showNewCategorySheet) {
            NavigationStack {
                Form {
                    Section("Category name") {
                        TextField("e.g. Action, Favourites", text: $newCategoryName)
                            .autocorrectionDisabled()
                    }
                }
                .navigationTitle("New Category")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showNewCategorySheet = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            Task {
                                await Task.detached(priority: .userInitiated) {
                                    _ = try? CategoryQueries.insert(name: name)
                                }.value
                                viewModel.loadCategories()
                                showNewCategorySheet = false
                            }
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.height(180)])
        }
    }
}

// MARK: - LibraryTab

private struct LibraryTab: View {
    let label: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.callout, weight: isSelected ? .medium : .regular))
                    if let count {
                        Text("\(count)")
                            .font(YomiTokens.Font.mono(11))
                            .foregroundStyle(canvas.textSecondary.opacity(0.7))
                    }
                }
                    .foregroundStyle(isSelected ? Color.accentColor : canvas.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .fixedSize()
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - NovelLibraryListRow

private struct NovelLibraryListRow: View {
    let novel: Novel
    let unreadCount: Int
    var isSelecting: Bool = false
    var isSelected: Bool = false
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : canvas.textSecondary)
            }

            Group {
                if let customPath = novel.resolvedCustomCoverPath,
                   let uiImage = UIImage(contentsOfFile: customPath) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    KFImage(novel.coverURL)
                        .placeholder { canvas.surface2 }
                        .fade(duration: 0.2)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(novel.title)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.body))
                    .foregroundStyle(canvas.textPrimary)
                    .lineLimit(2)
                Text(novel.author ?? novel.sourceId)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.footnote))
                    .foregroundStyle(canvas.textSecondary)
                    .lineLimit(1)
                if unreadCount > 0 {
                    Text("\(unreadCount) unread")
                        .font(YomiTokens.Font.mono(YomiTokens.TypeScale.footnote))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(canvas.textSecondary.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - NovelLibraryCoverCell

private struct NovelLibraryCoverCell: View {
    let novel: Novel
    let unreadCount: Int
    let onTap: () -> Void
    var catalogIndex: Int? = nil
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onLongPress: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    var onReadingStatusChange: ((ReadingStatus) -> Void)? = nil
    var onRemoveFromLibrary: (() -> Void)? = nil

    @Environment(\.yomiCanvas) private var canvas
    @State private var sourceName: String? = nil
    @State private var settings = AppSettings.shared
    @State private var readProgress: Double = 0
    @State private var currentReadingStatus: ReadingStatus = .none
    @State private var lastReadChapterName: String? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let customPath = novel.customCoverPath,
                       let uiImage = UIImage(contentsOfFile: customPath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .coverAspectSized()
                    } else {
                        CoverImage(url: novel.coverURL)
                    }
                }
                .cornerRadius(YomiTokens.Radius.cover)
                .clipped()
                .overlay(alignment: .topLeading) {
                    if let catalogIndex, !isSelecting {
                        Text(Notation.catalogIndex(catalogIndex))
                            .font(YomiTokens.Font.mono(15, bold: true))
                            .foregroundStyle(Color.accentColor)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        // "NOVEL" badge — always shown for novels
                        Text("NOVEL")
                            .font(YomiTokens.Font.mono(10, bold: true))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                            .padding(.top, 6)
                            .padding(.trailing, 6)
                        if settings.showUnreadBadge && unreadCount > 0 {
                            Text("\(min(unreadCount, 999))")
                                .font(YomiTokens.Font.mono(11, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                                .padding(.trailing, 6)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        if let name = lastReadChapterName, readProgress > 0 {
                            Text(name)
                                .font(YomiTokens.Font.mono(11))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.black.opacity(0.60))
                        }
                        if readProgress > 0 && readProgress < 1 {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * readProgress, height: 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 3)
                        }
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: YomiTokens.Radius.cover)
                            .fill(Color.accentColor.opacity(0.16))
                    }
                }

                Text(novel.title)
                    .font(YomiTokens.Font.grotesk(YomiTokens.TypeScale.footnote))
                    .lineLimit(2)
                    .foregroundStyle(canvas.textPrimary)

                if let name = sourceName {
                    Text(name)
                        .font(YomiTokens.Font.grotesk(12))
                        .foregroundStyle(canvas.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSelecting)
        .contextMenu {
            if !isSelecting {
                Button {
                    onLongPress?()
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                Menu {
                    ForEach(ReadingStatus.allCases) { status in
                        Button {
                            onReadingStatusChange?(status)
                            currentReadingStatus = status
                        } label: {
                            Label(status.label, systemImage: status.systemImage)
                            if currentReadingStatus == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Label("Reading Status", systemImage: "bookmark")
                }
                Divider()
                Button(role: .destructive) {
                    onRemoveFromLibrary?()
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        }
        .task(id: novel.id) {
            sourceName = ExtensionManager.shared.installed
                .first(where: { $0.id == novel.sourceId })?.name
            let (chapters, fetched) = await (
                Task.detached { (try? NovelQueries.fetchChapters(novelId: novel.id)) ?? [] }.value,
                Task.detached { try? NovelQueries.fetchOne(id: novel.id) }.value
            )
            if !chapters.isEmpty {
                readProgress = Double(chapters.filter { $0.isRead }.count) / Double(chapters.count)
            }
            currentReadingStatus = fetched?.readingStatus ?? novel.readingStatus
            let inProgress = chapters.first(where: { !$0.isRead && ($0.lastScrollPercent ?? 0) > 0.01 })
            let lastRead = chapters
                .filter { $0.readAt != nil }
                .max(by: { ($0.readAt ?? .distantPast) < ($1.readAt ?? .distantPast) })
            lastReadChapterName = (inProgress ?? lastRead)?.name
        }

        if isSelecting {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onSelect?() }
        }
        } // ZStack
        .overlay(alignment: .topLeading) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? AppSettings.shared.accentForeground : .white)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.black.opacity(0.35))
                            .padding(1)
                    )
                    .padding(6)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: YomiTokens.Radius.cover)
                    .stroke(Color.accentColor, lineWidth: 2.5)
            }
        }
    }
}

#Preview {
    LibraryView()
}
