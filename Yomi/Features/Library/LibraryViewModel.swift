import Foundation

@Observable
final class LibraryViewModel {

    // MARK: - State

    var mangas: [Manga] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Computed

    /// Filtra por título ignorando mayúsculas y diacríticos (ej: "attack" encuentra "Ättack")
    var filteredMangas: [Manga] {
        guard !searchText.isEmpty else { return mangas }
        return mangas.filter {
            $0.title.localizedStandardContains(searchText)
        }
    }

    // MARK: - Load

    func loadLibrary() async {
        isLoading = true
        errorMessage = nil
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
