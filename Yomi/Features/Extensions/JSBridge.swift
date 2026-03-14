import Foundation
import JavaScriptCore

/// Executes JavaScript plugin functions and maps results to Swift models
final class JSBridge {

    // MARK: - Properties

    private let context: JSContext

    // MARK: - Init

    /// Loads and evaluates the JS source from the given URL
    init?(scriptURL: URL) {
        guard
            let source = try? String(contentsOf: scriptURL, encoding: .utf8),
            let ctx = JSContext()
        else { return nil }
        context = ctx
        context.exceptionHandler = { _, exception in
            print("❌ JSBridge exception: \(exception?.toString() ?? "unknown")")
        }
        context.evaluateScript(source)
    }

    // MARK: - Plugin API

    /// Calls `getMangaList(page)` and returns an array of partial Manga objects
    func getMangaList(page: Int, sourceId: String) -> [Manga] {
        let result = context
            .objectForKeyedSubscript("getMangaList")
            .call(withArguments: [page])
        return parseMangaArray(result, sourceId: sourceId)
    }

    /// Calls `getChapterList(mangaPath)` and returns an array of Chapter objects
    func getChapterList(mangaPath: String, mangaId: String) -> [Chapter] {
        let result = context
            .objectForKeyedSubscript("getChapterList")
            .call(withArguments: [mangaPath])
        return parseChapterArray(result, mangaId: mangaId)
    }

    /// Calls `getPageList(chapterPath)` and returns an array of page image URL strings
    func getPageList(chapterPath: String) -> [String] {
        let result = context
            .objectForKeyedSubscript("getPageList")
            .call(withArguments: [chapterPath])
        guard
            let array = result?.toArray() as? [String]
        else { return [] }
        return array
    }

    // MARK: - Parsers

    private func parseMangaArray(_ value: JSValue?, sourceId: String) -> [Manga] {
        guard let items = value?.toArray() as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard
                let id    = dict["id"]    as? String,
                let path  = dict["path"]  as? String,
                let title = dict["title"] as? String
            else { return nil }
            return Manga(
                id:            id,
                path:          path,
                sourceId:      sourceId,
                title:         title,
                coverURL:      (dict["coverURL"] as? String).flatMap { URL(string: $0) },
                summary:       dict["summary"]  as? String,
                author:        dict["author"]   as? String,
                artist:        dict["artist"]   as? String,
                status:        MangaStatus(rawValue: dict["status"] as? String ?? "") ?? .unknown,
                genres:        dict["genres"]   as? [String] ?? [],
                inLibrary:     false,
                isLocal:       false,
                lastReadAt:    nil,
                lastUpdatedAt: nil
            )
        }
    }

    private func parseChapterArray(_ value: JSValue?, mangaId: String) -> [Chapter] {
        guard let items = value?.toArray() as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard
                let id   = dict["id"]   as? String,
                let path = dict["path"] as? String,
                let name = dict["name"] as? String
            else { return nil }
            return Chapter(
                id:            id,
                mangaId:       mangaId,
                path:          path,
                name:          name,
                chapterNumber: dict["chapterNumber"] as? Double,
                isRead:        false,
                isDownloaded:  false,
                readAt:        nil,
                progress:      0.0
            )
        }
    }
}
