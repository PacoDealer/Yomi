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
    var sortOrder: SortOrder = .lastRead

    // MARK: - Categories

    var categories: [Category] = []

    /// When nil → show all library manga. When set → filter to that category.
    var selectedCategoryId: String? = nil {
        didSet { updateFilteredIds() }
    }

    private(set) var filteredIds: Set<String> = []

    private func updateFilteredIds() {
        guard let catId = selectedCategoryId else {
            filteredIds = []
            return
        }
        Task.detached {
            let ids = (try? CategoryQueries.mangaIds(inCategory: catId)) ?? []
            await MainActor.run { self.filteredIds = Set(ids) }
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
        let base = selectedCategoryId == nil ? mangas : mangas.filter { filteredIds.contains($0.id) }
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

    /// Legacy alias kept for any existing callsite that uses filteredMangas.
    var filteredMangas: [Manga] { displayedManga }

    /// Novels shown in the grid: sorted by sortOrder, then title search.
    var displayedNovels: [Novel] {
        let sorted: [Novel]
        switch sortOrder {
        case .lastRead:
            sorted = novels.sorted {
                switch ($0.lastReadAt, $1.lastReadAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.title < $1.title
                }
            }
        case .alphabetical:
            sorted = novels.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .lastUpdated:
            sorted = novels.sorted {
                switch ($0.lastUpdatedAt, $1.lastUpdatedAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.title < $1.title
                }
            }
        case .unreadCount:
            sorted = novels.sorted {
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
        do {
            mangas = try MangaQueries.fetchLibrary()
            novels = (try? NovelQueries.fetchLibrary()) ?? []
            unreadCounts = (try? ChapterQueries.fetchUnreadCountsByManga()) ?? [:]
            novelUnreadCounts = (try? NovelQueries.fetchUnreadCountsByNovel()) ?? [:]
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
