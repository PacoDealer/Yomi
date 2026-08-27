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
    var sortOrder: SortOrder = {
        SortOrder(rawValue: UserDefaults.standard.string(forKey: "librarySortOrder") ?? "") ?? .lastRead
    }() {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: "librarySortOrder")
            rebuildDisplayed()
        }
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
        didSet { updateFilteredIds() }
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
        Task.detached {
            let cats = (try? CategoryQueries.fetchAll()) ?? []
            let counts = (try? CategoryQueries.fetchItemCounts()) ?? [:]
            await MainActor.run { self.categories = cats; self.categoryItemCounts = counts }
        }
    }

    // MARK: - Display builders

    private func buildDisplayedManga() -> [Manga] {
        let categoryFiltered = selectedCategoryId == nil ? mangas : mangas.filter { filteredIds.contains($0.id) }
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
        let categoryFiltered = selectedCategoryId == nil ? novels : novels.filter { filteredNovelIds.contains($0.id) }
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
        isLoading = true
        errorMessage = nil
        loadCategories()
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
        mangas = result.0
        novels = result.1
        unreadCounts = result.2
        novelUnreadCounts = result.3
        if let err = result.4 { errorMessage = err }
        writeWidgetData()
        isLoading = false
    }

    private func writeWidgetData() {
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
        let merged = (mangaItems + novelItems)
            .sorted { $0.date > $1.date }
            .prefix(5)
            .map { WidgetReadingItem(id: $0.id, title: $0.title, coverURLString: $0.cover, lastChapter: "Continue reading") }
        WidgetDataWriter.write(merged)
    }
}
