import Foundation

// MARK: - SortOrder

enum SortOrder: String, CaseIterable, Identifiable {
    case lastRead     = "Last Read"
    case alphabetical = "Alphabetical"
    case lastUpdated  = "Last Updated"
    case unreadCount  = "Unread"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .lastRead:     return "clock"
        case .alphabetical: return "textformat.abc"
        case .lastUpdated:  return "arrow.clockwise"
        case .unreadCount:  return "book.closed"
        }
    }
}

// MARK: - LibraryViewModel

@Observable
final class LibraryViewModel {

    // MARK: - State

    var mangas: [Manga] = []
    var novels: [Novel] = []
    var unreadCounts: [String: Int] = [:]
    var novelUnreadCounts: [String: Int] = [:]
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var sortOrder: SortOrder = {
        SortOrder(rawValue: UserDefaults.standard.string(forKey: "librarySortOrder") ?? "") ?? .lastRead
    }() {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "librarySortOrder") }
    }
    /// When nil → show all titles regardless of reading status.
    var statusFilter: ReadingStatus? = {
        guard let raw = UserDefaults.standard.string(forKey: "libraryStatusFilter") else { return nil }
        return ReadingStatus(rawValue: raw)
    }() {
        didSet { UserDefaults.standard.set(statusFilter?.rawValue, forKey: "libraryStatusFilter") }
    }

    // MARK: - Categories

    var categories: [Category] = []

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
            return
        }
        Task.detached {
            let mangaIds = (try? CategoryQueries.mangaIds(inCategory: catId)) ?? []
            let novelIds = (try? CategoryQueries.novelIds(inCategory: catId)) ?? []
            await MainActor.run {
                self.filteredIds = Set(mangaIds)
                self.filteredNovelIds = Set(novelIds)
            }
        }
    }

    func loadCategories() {
        Task.detached {
            let cats = (try? CategoryQueries.fetchAll()) ?? []
            await MainActor.run { self.categories = cats }
        }
    }

    // MARK: - Computed

    /// Manga shown in the grid: category-filtered, sorted by sortOrder, then title search.
    var displayedManga: [Manga] {
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
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedStandardContains(searchText) }
    }

    /// Novels shown in the grid: category-filtered, status-filtered, sorted by sortOrder, then title search.
    var displayedNovels: [Novel] {
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
                let n = (try? NovelQueries.fetchLibrary()) ?? []
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
