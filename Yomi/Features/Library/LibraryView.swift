import SwiftUI

struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    @State private var extensionManager = ExtensionManager.shared
    @State private var settings = AppSettings.shared
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var showNewCategorySheet = false
    @State private var newCategoryName = ""
    @State private var selectedNovel: Novel? = nil
    @State private var showNovelDetail = false
    @State private var randomMangaDest: Manga? = nil
    @State private var showRandomManga = false
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
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "No plugins installed",
                                systemImage: "puzzlepiece.extension",
                                description: Text("Plugins connect Yomi to manga and novel sources. Install one to start reading.")
                            )
                            Button("Get plugins") {
                                appRouter.openBrowseExtensions = true
                                appRouter.selectedTab = AppRouter.tabBrowse
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "Your library is empty",
                                systemImage: "books.vertical",
                                description: Text("Browse sources and add titles to see them here.")
                            )
                            Button("Browse sources") {
                                appRouter.selectedTab = AppRouter.tabBrowse
                            }
                            .buttonStyle(.borderedProminent)
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
                                    Text("Manga")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                }
                                if settings.libraryDisplayMode == "list" {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.displayedManga) { manga in
                                            NavigationLink(destination: MangaDetailView(manga: manga)) {
                                                MangaListRow(manga: manga,
                                                             unreadCount: viewModel.unreadCounts[manga.id] ?? 0)
                                            }
                                            .buttonStyle(.plain)
                                            Divider().padding(.leading, 76)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                } else {
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(viewModel.displayedManga) { manga in
                                            MangaCoverCell(
                                                manga: manga,
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
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.top, 4)
                                }
                            }
                            if !isSelecting && !viewModel.displayedNovels.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Novels")
                                        .font(.headline)
                                        .padding(.horizontal, 16)
                                        .padding(.top, viewModel.displayedManga.isEmpty ? 8 : 16)
                                    if settings.libraryDisplayMode == "list" {
                                        LazyVStack(spacing: 0) {
                                            ForEach(viewModel.displayedNovels) { novel in
                                                Button { selectedNovel = novel; showNovelDetail = true } label: {
                                                    NovelLibraryListRow(
                                                        novel: novel,
                                                        unreadCount: viewModel.novelUnreadCounts[novel.id] ?? 0
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                Divider().padding(.leading, 76)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    } else {
                                        LazyVGrid(columns: columns, spacing: 12) {
                                            ForEach(viewModel.displayedNovels) { novel in
                                                NovelLibraryCoverCell(
                                                    novel: novel,
                                                    unreadCount: viewModel.novelUnreadCounts[novel.id] ?? 0
                                                ) {
                                                    selectedNovel = novel; showNovelDetail = true
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable { await viewModel.loadLibrary() }
                    .safeAreaInset(edge: .bottom) {
                        if isSelecting {
                            selectionActionBar
                        }
                    }
                }
            }
            .navigationTitle(isSelecting
                ? (selectedIds.isEmpty ? "Select" : "\(selectedIds.count) selected")
                : "Library")
            .safeAreaInset(edge: .top, spacing: 0) {
                categoryFilterBar
            }
            .searchable(text: $viewModel.searchText, prompt: "Search library")
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            withAnimation(.spring(duration: 0.2)) {
                                isSelecting = false
                                selectedIds = []
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selectedIds.count == viewModel.displayedManga.count ? "Deselect All" : "Select All") {
                            withAnimation(.spring(duration: 0.15)) {
                                if selectedIds.count == viewModel.displayedManga.count {
                                    selectedIds = []
                                } else {
                                    selectedIds = Set(viewModel.displayedManga.map { $0.id })
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
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle\(viewModel.sortOrder == .lastRead ? "" : ".fill")")
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
            .task {
                await viewModel.loadLibrary()
            }
        }
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack(spacing: 16) {
            Spacer()
            Button(role: .destructive) {
                Task { await removeSelected() }
            } label: {
                Label("Remove from Library", systemImage: "heart.slash")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .disabled(selectedIds.isEmpty)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            Spacer()
        }
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func removeSelected() async {
        let ids = selectedIds
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
        }.value
        await viewModel.loadLibrary()
        withAnimation(.spring(duration: 0.2)) {
            isSelecting = false
            selectedIds = []
        }
    }

    // MARK: - Category Filter Bar

    @ViewBuilder
    private var categoryFilterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !viewModel.categories.isEmpty {
                        CategoryChip(
                            label: "All",
                            isSelected: viewModel.selectedCategoryId == nil
                        ) {
                            viewModel.selectedCategoryId = nil
                        }
                        ForEach(viewModel.categories) { category in
                            CategoryChip(
                                label: category.name,
                                isSelected: viewModel.selectedCategoryId == category.id
                            ) {
                                viewModel.selectedCategoryId = category.id
                            }
                        }
                    }
                    // Always show "+" to create categories
                    Button {
                        newCategoryName = ""
                        showNewCategorySheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(.secondary)
                            .background(Capsule().stroke(Color.secondary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            // Reading status filter row — shown when manga or novels are in library
            if !viewModel.mangas.isEmpty || !viewModel.novels.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(label: "All", isSelected: viewModel.statusFilter == nil) {
                            viewModel.statusFilter = nil
                        }
                        ForEach(ReadingStatus.allCases.filter { $0 != .none }) { status in
                            CategoryChip(
                                label: status.label,
                                isSelected: viewModel.statusFilter == status
                            ) {
                                viewModel.statusFilter = (viewModel.statusFilter == status) ? nil : status
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(.bar)
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

// MARK: - CategoryChip

private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor)
                    } else {
                        Capsule().stroke(Color.secondary, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NovelLibraryListRow

private struct NovelLibraryListRow: View {
    let novel: Novel
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: novel.coverURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(novel.title)
                    .font(.body)
                    .lineLimit(2)
                Text(novel.author ?? novel.sourceId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if unreadCount > 0 {
                    Text("\(unreadCount) unread")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - NovelLibraryCoverCell

private struct NovelLibraryCoverCell: View {
    let novel: Novel
    let unreadCount: Int
    let onTap: () -> Void

    @State private var sourceName: String? = nil
    @State private var settings = AppSettings.shared
    @State private var readProgress: Double = 0

    var body: some View {
        Button(action: onTap) {
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
                .overlay(alignment: .topTrailing) {
                    if settings.showUnreadBadge && unreadCount > 0 {
                        Text("\(min(unreadCount, 999))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottom) {
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

                Text(novel.title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if let name = sourceName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: novel.id) {
            sourceName = ExtensionManager.shared.installed
                .first(where: { $0.id == novel.sourceId })?.name
            let chapters = await Task.detached {
                (try? NovelQueries.fetchChapters(novelId: novel.id)) ?? []
            }.value
            if !chapters.isEmpty {
                readProgress = Double(chapters.filter { $0.isRead }.count) / Double(chapters.count)
            }
        }
    }
}

#Preview {
    LibraryView()
}
