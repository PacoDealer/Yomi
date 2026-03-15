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
            mangas = try MangaQueries.fetchLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
