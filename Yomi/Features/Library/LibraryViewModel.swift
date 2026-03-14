import Foundation

@Observable
final class LibraryViewModel {
    var mangas: [Manga] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil

    /// Filtra por título ignorando mayúsculas y diacríticos (ej: "attack" encuentra "Ättack")
    var filteredMangas: [Manga] {
        guard !searchText.isEmpty else { return mangas }
        return mangas.filter {
            $0.title.localizedStandardContains(searchText)
        }
    }

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

    func loadPreviewData() {
        mangas = [
            Manga(id: "1", path: "/one-piece",            sourceId: "en.mangadex", title: "One Piece",            coverURL: nil, summary: nil, author: "Eiichiro Oda",    artist: "Eiichiro Oda",    status: .ongoing,   genres: ["Acción", "Aventura"],       inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil),
            Manga(id: "2", path: "/berserk",              sourceId: "en.mangadex", title: "Berserk",              coverURL: nil, summary: nil, author: "Kentaro Miura",  artist: "Kentaro Miura",  status: .hiatus,    genres: ["Acción", "Dark Fantasy"],   inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil),
            Manga(id: "3", path: "/vinland-saga",         sourceId: "en.mangadex", title: "Vinland Saga",         coverURL: nil, summary: nil, author: "Makoto Yukimura",artist: "Makoto Yukimura",status: .ongoing,   genres: ["Acción", "Histórico"],      inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil),
            Manga(id: "4", path: "/fullmetal-alchemist",  sourceId: "en.mangadex", title: "Fullmetal Alchemist",  coverURL: nil, summary: nil, author: "Hiromu Arakawa", artist: "Hiromu Arakawa", status: .completed, genres: ["Acción", "Aventura"],       inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil),
            Manga(id: "5", path: "/solo-leveling",        sourceId: "en.mangadex", title: "Solo Leveling",        coverURL: nil, summary: nil, author: "Chugong",        artist: "DUBU",           status: .completed, genres: ["Acción", "Fantasía"],       inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil),
            Manga(id: "6", path: "/chainsaw-man",         sourceId: "en.mangadex", title: "Chainsaw Man",         coverURL: nil, summary: nil, author: "Tatsuki Fujimoto",artist: "Tatsuki Fujimoto",status: .ongoing, genres: ["Acción", "Horror"],         inLibrary: true, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil),
        ]
    }
}
