import Foundation

// MARK: - Suwayomi REST models

struct SuwayomiSource: Codable, Identifiable {
    let id: String
    let name: String
    let lang: String
    let iconUrl: String
    let supportsLatest: Bool
    let isNsfw: Bool
}

struct SuwayomiMangaItem: Codable, Identifiable {
    let id: Int
    let title: String
    let thumbnailUrl: String?
    let url: String?
}

struct SuwayomiMangaPage: Codable {
    let mangaList: [SuwayomiMangaItem]
    let hasNextPage: Bool
}

struct SuwayomiMangaDetail: Codable {
    let id: Int
    let title: String
    let thumbnailUrl: String?
    let author: String?
    let description: String?
    let genre: [String]?
    let status: String?
}

struct SuwayomiChapterItem: Codable, Identifiable {
    let id: Int
    let index: Int
    let name: String
    let chapterNumber: Float
    let pageCount: Int?
    let uploadDate: Int64?
    let scanlator: String?
    let read: Bool?
}

// MARK: - SuwayomiService

final class SuwayomiService {

    // MARK: - Singleton

    static let shared = SuwayomiService()
    private init() {}

    // MARK: - Helpers

    var baseURL: String {
        var url = AppSettings.shared.suwayomiURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }

    var isEnabled: Bool { !baseURL.isEmpty }

    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - API

    func fetchSources() async throws -> [SuwayomiSource] {
        try await fetch("/api/v1/source/list")
    }

    func fetchPopular(sourceId: String, page: Int) async throws -> SuwayomiMangaPage {
        try await fetch("/api/v1/source/\(sourceId)/popular/\(page)")
    }

    func fetchLatest(sourceId: String, page: Int) async throws -> SuwayomiMangaPage {
        try await fetch("/api/v1/source/\(sourceId)/latest/\(page)")
    }

    func fetchSearch(sourceId: String, query: String, page: Int) async throws -> SuwayomiMangaPage {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await fetch("/api/v1/source/\(sourceId)/search/\(page)?searchTerm=\(encoded)")
    }

    func fetchMangaDetail(mangaId: Int) async throws -> SuwayomiMangaDetail {
        try await fetch("/api/v1/manga/\(mangaId)")
    }

    func fetchChapters(mangaId: Int) async throws -> [SuwayomiChapterItem] {
        try await fetch("/api/v1/manga/\(mangaId)/chapters?onlineFetch=true")
    }

    func fetchChapterPageCount(mangaId: Int, chapterIndex: Int) async throws -> Int {
        let chapter: SuwayomiChapterItem = try await fetch(
            "/api/v1/manga/\(mangaId)/chapter/\(chapterIndex)?onlineFetch=true"
        )
        return chapter.pageCount ?? 0
    }

    /// Constructs proxy page URLs served by the Suwayomi server.
    func pageURLs(mangaId: Int, chapterIndex: Int, pageCount: Int) -> [String] {
        (0..<pageCount).map { i in
            "\(baseURL)/api/v1/manga/\(mangaId)/chapter/\(chapterIndex)/page/\(i)"
        }
    }

    // MARK: - Conversion helpers

    func toManga(item: SuwayomiMangaItem, sourceId: String) -> Manga {
        let rawCover = item.thumbnailUrl.flatMap { raw -> String? in
            raw.hasPrefix("http") ? raw : "\(baseURL)\(raw)"
        }
        return Manga(
            id: "suwayomi_\(sourceId)_\(item.id)",
            path: item.url ?? "/manga/\(item.id)",
            sourceId: "suwayomi_\(sourceId)",
            title: item.title,
            coverURL: rawCover.flatMap { URL(string: $0) },
            summary: nil,
            author: nil,
            artist: nil,
            status: .unknown,
            genres: [],
            inLibrary: false,
            isLocal: false,
            lastReadAt: nil,
            lastUpdatedAt: nil,
            readingSeconds: 0
        )
    }

    /// Extracts the Suwayomi integer mangaId from a Yomi id like "suwayomi_{sourceId}_{mangaId}".
    func suwayomiMangaId(from yomiId: String) -> Int? {
        // Format: "suwayomi_{sourceId}_{intId}" — last component after final underscore
        guard yomiId.hasPrefix("suwayomi_"),
              let lastUnderscore = yomiId.lastIndex(of: "_") else { return nil }
        return Int(yomiId[yomiId.index(after: lastUnderscore)...])
    }
}
