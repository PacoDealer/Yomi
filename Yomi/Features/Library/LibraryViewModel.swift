import Foundation

// MARK: - SortOrder

enum SortOrder: String, CaseIterable, Identifiable {
    case lastRead     = "Last Read"
    case alphabetical = "Alphabetical"
    case lastUpdated  = "Last Updated"
    case unreadCount  = "Unread"
    case readingTime  = "Reading Time"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .lastRead:     return "clock"
        case .alphabetical: return "textformat.abc"
        case .lastUpdated:  return "arrow.clockwise"
        case .unreadCount:  return "book.closed"
        case .readingTime:  return "timer"
        }
    }
}

// MARK: - LibraryViewModel

@Observable
final class LibraryViewModel {

    // MARK: - State

    var mangas: [Manga] = [] { didSet { rebuildDisplayed() } }
    var novels: [Novel] = [] { didSet { rebuildDisplayed() } }
    var unreadCounts: [String: Int] = [:] { didSet { rebuildDisplayed() } }
    var novelUnreadCounts: [String: Int] = [:] { didSet { rebuildDisplayed() } }
    var searchText: String = "" { didSet { rebuildDisplayed() } }
    var isLoading: Bool = false
    var errorMessage: String? = nil
    /// The sort of the category being shown — each category keeps its own (S170, Tachimanga v4.1). "All" is the
    /// old global `librarySortOrder`, and the fallback for a category never sorted on its own.
    var sortOrder: SortOrder = {
        SortOrder(rawValue: UserDefaults.standard.string(forKey: "librarySortOrder") ?? "") ?? .lastRead
    }() {
        didSet {
            if !isLoadingCategorySort {
                if let catId = selectedCategoryId {
                    var byCategory = Self.categorySorts
                    byCategory[catId] = sortOrder.rawValue
                    Self.categorySorts = byCategory
                } else {
                    UserDefaults.standard.set(sortOrder.rawValue, forKey: "librarySortOrder")
                }
            }
            rebuildDisplayed()
        }
    }
    @ObservationIgnored private var isLoadingCategorySort = false

    private static var categorySorts: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "librarySortByCategory") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "librarySortByCategory") }
    }

    /// True when the category shown has a sort of its own, not the "All" one.
    var categoryHasOwnSort: Bool { selectedCategoryId.map { Self.categorySorts[$0] != nil } ?? false }

    private func loadCategorySort() {
        let global = SortOrder(rawValue: UserDefaults.standard.string(forKey: "librarySortOrder") ?? "") ?? .lastRead
        let own = selectedCategoryId.flatMap { Self.categorySorts[$0] }.flatMap(SortOrder.init(rawValue:))
        isLoadingCategorySort = true
        sortOrder = own ?? global
        isLoadingCategorySort = false
    }

    // MARK: - Source filter (S170, Tachimanga v4.15/v5.0)

    /// Source ids to show only (empty = every source) and to hide. A source is in at most one of the two.
    var includedSources: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "libraryIncludedSources") ?? []) {
        didSet { UserDefaults.standard.set(Array(includedSources), forKey: "libraryIncludedSources"); rebuildDisplayed() }
    }
    var excludedSources: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "libraryExcludedSources") ?? []) {
        didSet { UserDefaults.standard.set(Array(excludedSources), forKey: "libraryExcludedSources"); rebuildDisplayed() }
    }
    var sourceFilterActive: Bool { !includedSources.isEmpty || !excludedSources.isEmpty }

    enum SourceFilterState { case all, only, hidden }

    func sourceFilterState(_ sourceId: String) -> SourceFilterState {
        includedSources.contains(sourceId) ? .only : excludedSources.contains(sourceId) ? .hidden : .all
    }

    /// Off → show only → hide → off.
    func cycleSourceFilter(_ sourceId: String) {
        switch sourceFilterState(sourceId) {
        case .all: includedSources.insert(sourceId)
        case .only: includedSources.remove(sourceId); excludedSources.insert(sourceId)
        case .hidden: excludedSources.remove(sourceId)
        }
    }

    func clearSourceFilter() {
        includedSources = []
        excludedSources = []
    }

    /// Every source a library title comes from, with its title count, by name.
    var librarySources: [(id: String, name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for id in mangas.map(\.sourceId) + novels.map(\.sourceId) { counts[id, default: 0] += 1 }
        let named = counts.map { (id: $0.key, name: SourceStatus.sourceName($0.key), count: $0.value) }
        // Asura Scans as a plugin and as a Keiyoushi extension: say which is which.
        let names = named.map { $0.name.lowercased() }
        return named.map { source in
            names.filter { $0 == source.name.lowercased() }.count > 1
                ? (id: source.id, name: "\(source.name) · \(SourceStatus.kindLabel(source.id))", count: source.count) : source
        }
        .sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    private func passesSourceFilter(_ sourceId: String) -> Bool {
        (includedSources.isEmpty || includedSources.contains(sourceId)) && !excludedSources.contains(sourceId)
    }
    /// When nil → show all titles regardless of reading status.
    var statusFilter: ReadingStatus? = {
        guard let raw = UserDefaults.standard.string(forKey: "libraryStatusFilter") else { return nil }
        return ReadingStatus(rawValue: raw)
    }() {
        didSet {
            UserDefaults.standard.set(statusFilter?.rawValue, forKey: "libraryStatusFilter")
            rebuildDisplayed()
        }
    }

    // MARK: - Cached display arrays

    private(set) var displayedManga: [Manga] = []
    private(set) var displayedNovels: [Novel] = []

    private func rebuildDisplayed() {
        displayedManga = buildDisplayedManga()
        displayedNovels = buildDisplayedNovels()
    }

    // MARK: - Categories

    var categories: [Category] = []
    var categoryItemCounts: [String: Int] = [:]

    /// When nil → show all library manga. When set → filter to that category.
    var selectedCategoryId: String? = nil {
        didSet {
            loadCategorySort()
            updateFilteredIds()
        }
    }

    private(set) var filteredIds: Set<String> = []

    private(set) var filteredNovelIds: Set<String> = []

    private func updateFilteredIds() {
        guard let catId = selectedCategoryId else {
            filteredIds = []
            filteredNovelIds = []
            rebuildDisplayed()
            return
        }
        Task.detached {
            let mangaIds = (try? CategoryQueries.mangaIds(inCategory: catId)) ?? []
            let novelIds = (try? CategoryQueries.novelIds(inCategory: catId)) ?? []
            await MainActor.run {
                self.filteredIds = Set(mangaIds)
                self.filteredNovelIds = Set(novelIds)
                self.rebuildDisplayed()
            }
        }
    }

    func loadCategories() {
        // Safe Mode: count only the titles the Library shows.
        let visible: Set<String>? = AppSettings.shared.safeMode ? Set(mangas.map(\.id) + novels.map(\.id)) : nil
        Task.detached {
            let cats = (try? CategoryQueries.fetchAll()) ?? []
            var counts = (try? CategoryQueries.fetchItemCounts()) ?? [:]
            if let visible {
                for cat in cats {
                    let ids = ((try? CategoryQueries.mangaIds(inCategory: cat.id)) ?? [])
                        + ((try? CategoryQueries.novelIds(inCategory: cat.id)) ?? [])
                    counts[cat.id] = ids.filter(visible.contains).count
                }
            }
            let finalCounts = counts
            await MainActor.run { self.categories = cats; self.categoryItemCounts = finalCounts }
        }
    }

    // MARK: - Display builders

    private func buildDisplayedManga() -> [Manga] {
        let categoryFiltered = (selectedCategoryId == nil ? mangas : mangas.filter { filteredIds.contains($0.id) })
            .filter { passesSourceFilter($0.sourceId) }
        let base = statusFilter == nil ? categoryFiltered : categoryFiltered.filter { $0.readingStatus == statusFilter }
        let sorted: [Manga]
        switch sortOrder {
        case .lastRead:
            sorted = base.sorted {
                switch ($0.lastReadAt, $1.lastReadAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.title < $1.title
                }
            }
        case .alphabetical:
            sorted = base.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .lastUpdated:
            sorted = base.sorted {
                switch ($0.lastUpdatedAt, $1.lastUpdatedAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.title < $1.title
                }
            }
        case .unreadCount:
            sorted = base.sorted {
                (unreadCounts[$0.id] ?? 0) > (unreadCounts[$1.id] ?? 0)
            }
        case .readingTime:
            sorted = base.sorted { $0.readingSeconds > $1.readingSeconds }
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedStandardContains(searchText) }
    }

    private func buildDisplayedNovels() -> [Novel] {
        let categoryFiltered = (selectedCategoryId == nil ? novels : novels.filter { filteredNovelIds.contains($0.id) })
            .filter { passesSourceFilter($0.sourceId) }
        let base = statusFilter == nil ? categoryFiltered : categoryFiltered.filter { $0.readingStatus == statusFilter }
        let sorted: [Novel]
        switch sortOrder {
        case .lastRead:
            sorted = base.sorted {
                switch ($0.lastReadAt, $1.lastReadAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.title < $1.title
                }
            }
        case .alphabetical:
            sorted = base.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .lastUpdated:
            sorted = base.sorted {
                switch ($0.lastUpdatedAt, $1.lastUpdatedAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.title < $1.title
                }
            }
        case .unreadCount:
            sorted = base.sorted {
                (novelUnreadCounts[$0.id] ?? 0) > (novelUnreadCounts[$1.id] ?? 0)
            }
        case .readingTime:
            sorted = base.sorted { $0.readingSeconds > $1.readingSeconds }
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedStandardContains(searchText) }
    }

    // MARK: - Load

    func loadLibrary() async {
        let perf = Perf.begin("LoadLibrary")
        defer { perf.end() }
        isLoading = true
        errorMessage = nil
        loadCategories()
        let safe = SafeMode.filter
        let result = await Task.detached(priority: .userInitiated) {
            do {
                let m = try MangaQueries.fetchLibrary()
                // The novel half is fetched with the same do/catch rather than `try?`: half a
                // library rendering as the whole one is the same silent failure #150 named for
                // manga. Unread counts stay best-effort — a missing badge isn't a lie about
                // what's in the library.
                let n = try NovelQueries.fetchLibrary()
                let uc = (try? ChapterQueries.fetchUnreadCountsByManga()) ?? [:]
                let nuc = (try? NovelQueries.fetchUnreadCountsByNovel()) ?? [:]
                return (m, n, uc, nuc, nil as String?)
            } catch {
                return ([], [], [:], [:], error.localizedDescription)
            }
        }.value
        // Safe Mode (S179): hidden titles leave every count, filter, shelf and the widget, not just the grid.
        mangas = result.0.filter(safe.allows)
        novels = result.1.filter(safe.allows)
        if safe.isOn { loadCategories() }
        unreadCounts = result.2
        novelUnreadCounts = result.3
        if let err = result.4 { errorMessage = err }
        await writeWidgetData()
        isLoading = false
    }

    private func writeWidgetData() async {
        // Widgets render on the Home Screen / Lock Screen Today View with no authentication —
        // never expose reading history there while the user has App Lock or Secure Screen on.
        guard !AppSettings.shared.appLockEnabled, !AppSettings.shared.secureScreenEnabled else {
            WidgetDataWriter.write([])
            return
        }
        typealias Dated = (id: String, title: String, cover: String?, date: Date)
        let mangaItems: [Dated] = mangas.compactMap {
            guard let d = $0.lastReadAt else { return nil }
            return (id: $0.id, title: $0.title, cover: $0.coverURL?.absoluteString, date: d)
        }
        let novelItems: [Dated] = novels.compactMap {
            guard let d = $0.lastReadAt else { return nil }
            return (id: $0.id, title: $0.title, cover: $0.coverURL?.absoluteString, date: d)
        }
        let top = (mangaItems + novelItems)
            .sorted { $0.date > $1.date }
            .prefix(5)

        // The widget's per-title subtitle used to be the literal "Continue reading" for every
        // entry (Known Issue #129). Two bulk queries — one per media type, only for the ≤5 ids
        // actually shown — resolve the real last-read chapter name.
        let mangaIds = top.map { $0.id }.filter { id in mangaItems.contains { $0.id == id } }
        let novelIds = top.map { $0.id }.filter { id in novelItems.contains { $0.id == id } }
        let names = await Task.detached(priority: .utility) {
            let m = (try? ChapterQueries.fetchLastTouchedChapterNames(mangaIds: mangaIds)) ?? [:]
            let n = (try? NovelQueries.fetchLastTouchedChapterNames(novelIds: novelIds)) ?? [:]
            return m.merging(n) { a, _ in a }
        }.value

        let merged = top.map {
            WidgetReadingItem(
                id: $0.id,
                title: $0.title,
                coverURLString: $0.cover,
                // Falls back to the old literal only when nothing has been read yet — which for a
                // lastReadAt-sorted list means a title whose read state predates chapter records.
                lastChapter: names[$0.id] ?? String(localized: "Continue reading")
            )
        }
        WidgetDataWriter.write(merged)
    }
}
