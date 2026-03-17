import Foundation

@Observable
final class LibraryViewModel {

    // MARK: - State

    var mangas: [Manga] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil

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

    /// Manga shown in the grid: category-filtered first, then title search.
    var displayedManga: [Manga] {
        let base = selectedCategoryId == nil ? mangas : mangas.filter { filteredIds.contains($0.id) }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.title.localizedStandardContains(searchText) }
    }

    /// Legacy alias kept for any existing callsite that uses filteredMangas.
    var filteredMangas: [Manga] { displayedManga }

    // MARK: - Load

    func loadLibrary() async {
        isLoading = true
        errorMessage = nil
        loadCategories()
        do {
            let fetched = try MangaQueries.fetchLibrary()
            mangas = fetched.sorted {
                switch ($0.lastReadAt, $1.lastReadAt) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.title < $1.title
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
