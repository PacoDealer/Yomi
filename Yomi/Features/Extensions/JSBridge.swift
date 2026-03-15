import Foundation
import JavaScriptCore

// MARK: - Novel Result Types

struct NovelItem {
    var name: String
    var path: String
    var cover: String?
}

struct NovelChapter {
    var name: String
    var path: String
    var chapterNumber: Double?
    var releaseTime: String?
}

struct SourceNovel {
    var path: String
    var name: String
    var cover: String?
    var author: String?
    var summary: String?
    var status: String?
    var chapters: [NovelChapter]
}

// MARK: - JSBridge

/// Executes JavaScript plugin functions and maps results to Swift models.
/// Supports two formats:
///   Format A — Yomi/Manga: global functions getMangaList / getChapterList / getPageList
///   Format B — LNReader/Novel: global `plugin` object with popularNovels / parseNovel / parseChapter / searchNovels
final class JSBridge {

    // nonisolated(unsafe): JSContext is only ever accessed from background threads
    // via nonisolated methods — never from the main actor.
    nonisolated(unsafe) private let context: JSContext

    // MARK: - Init

    nonisolated init?(scriptURL: URL) {
        guard
            let source = try? String(contentsOf: scriptURL, encoding: .utf8),
            let ctx    = JSContext()
        else { return nil }

        context = ctx
        context.exceptionHandler = { _, exception in
            print("❌ JSBridge exception:", exception?.toString() ?? "unknown")
        }
        JSBridge.injectShims(into: ctx)
        ctx.evaluateScript(source)
    }

    /// true when the loaded script exposes a `plugin` global with `popularNovels` (LNReader format)
    nonisolated var isLNReaderPlugin: Bool {
        guard
            let plugin = context.objectForKeyedSubscript("plugin"),
            !plugin.isUndefined, !plugin.isNull,
            let fn = plugin.objectForKeyedSubscript("popularNovels"),
            !fn.isUndefined, !fn.isNull
        else { return false }
        return true
    }

    // MARK: - Shims

    nonisolated private static func injectShims(into ctx: JSContext) {
        injectConsole(into: ctx)
        injectStorage(into: ctx)
        injectSourceFetch(into: ctx)
        injectCheerio(into: ctx)
    }

    /// console.log / warn / error → Swift print()
    nonisolated private static func injectConsole(into ctx: JSContext) {
        let log:   @convention(block) (String) -> Void = { print("📋 JS log:",   $0) }
        let warn:  @convention(block) (String) -> Void = { print("⚠️  JS warn:",  $0) }
        let error: @convention(block) (String) -> Void = { print("❌ JS error:", $0) }
        let console = JSValue(newObjectIn: ctx)
        console?.setObject(log,   forKeyedSubscript: "log"   as NSString)
        console?.setObject(warn,  forKeyedSubscript: "warn"  as NSString)
        console?.setObject(error, forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    /// localStorage / sessionStorage — pure in-memory JS objects
    nonisolated private static func injectStorage(into ctx: JSContext) {
        ctx.evaluateScript("""
        (function() {
            function makeStorage() {
                var _s = {};
                return {
                    getItem:    function(k)    { return Object.prototype.hasOwnProperty.call(_s, k) ? _s[k] : null; },
                    setItem:    function(k, v) { _s[k] = String(v); },
                    removeItem: function(k)    { delete _s[k]; },
                    clear:      function()     { _s = {}; }
                };
            }
            var localStorage    = makeStorage();
            var sessionStorage  = makeStorage();
            this.localStorage   = localStorage;
            this.sessionStorage = sessionStorage;
        }).call(this);
        """)
    }

    /// SOURCE.fetch(url, options?) — synchronous HTTP GET via DispatchSemaphore
    nonisolated private static func injectSourceFetch(into ctx: JSContext) {
        let fetch: @convention(block) (String, JSValue?) -> String = { urlString, options in
            guard let url = URL(string: urlString) else { return "" }
            var request = URLRequest(url: url, timeoutInterval: 30)
            // Apply optional headers: { headers: { "X-Key": "value" } }
            if let opts = options, !opts.isUndefined, !opts.isNull,
               let headers = opts.objectForKeyedSubscript("headers"),
               !headers.isUndefined, !headers.isNull,
               let dict = headers.toDictionary() as? [String: Any] {
                for (key, value) in dict {
                    request.setValue("\(value)", forHTTPHeaderField: key)
                }
            }
            var body = ""
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data { body = String(data: data, encoding: .utf8) ?? "" }
                sem.signal()
            }.resume()
            sem.wait()
            return body
        }
        let source = JSValue(newObjectIn: ctx)
        source?.setObject(fetch, forKeyedSubscript: "fetch" as NSString)
        ctx.setObject(source, forKeyedSubscript: "SOURCE" as NSString)
    }

    /// Minimal cheerio stub — prevents crashes in plugins that call cheerio.load()
    /// Full DOM traversal is not available without a real HTML parser; selectors return empty results.
    nonisolated private static func injectCheerio(into ctx: JSContext) {
        ctx.evaluateScript("""
        var cheerio = {
            load: function(html, options) {
                function $(selector) {
                    return {
                        length:  0,
                        text:    function()     { return ''; },
                        html:    function()     { return ''; },
                        attr:    function(name) { return undefined; },
                        find:    function(sel)  { return $(sel); },
                        filter:  function(sel)  { return $(sel); },
                        each:    function(fn)   { return this; },
                        map:     function(fn)   { return []; },
                        first:   function()     { return this; },
                        last:    function()     { return this; },
                        eq:      function(i)    { return this; },
                        parent:  function()     { return this; },
                        children:function(sel)  { return sel ? $(sel) : this; },
                        next:    function()     { return this; },
                        prev:    function()     { return this; },
                        is:      function()     { return false; },
                        hasClass:function()     { return false; },
                        toArray: function()     { return []; }
                    };
                }
                $.root  = function() { return $(null); };
                $.load  = cheerio.load;
                return $;
            }
        };
        """)
    }

    // MARK: - Plugin API — Manga (Format A)

    nonisolated func getMangaList(page: Int, sourceId: String) -> [Manga] {
        let result = context
            .objectForKeyedSubscript("getMangaList")?
            .call(withArguments: [page])
        return JSBridge.parseMangaArray(result, sourceId: sourceId)
    }

    nonisolated func getChapterList(mangaPath: String, mangaId: String) -> [Chapter] {
        let result = context
            .objectForKeyedSubscript("getChapterList")?
            .call(withArguments: [mangaPath])
        return JSBridge.parseChapterArray(result, mangaId: mangaId)
    }

    nonisolated func getPageList(chapterPath: String) -> [String] {
        let result = context
            .objectForKeyedSubscript("getPageList")?
            .call(withArguments: [chapterPath])
        return result?.toArray() as? [String] ?? []
    }

    // MARK: - Plugin API — Novel (Format B)

    nonisolated func popularNovels(page: Int) -> [NovelItem] {
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("popularNovels")?
            .call(withArguments: [page, JSValue(nullIn: context) as Any])
        return JSBridge.parseNovelItems(result)
    }

    nonisolated func searchNovels(query: String, page: Int) -> [NovelItem] {
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("searchNovels")?
            .call(withArguments: [query, page])
        return JSBridge.parseNovelItems(result)
    }

    nonisolated func parseNovel(path: String) -> SourceNovel? {
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("parseNovel")?
            .call(withArguments: [path])
        guard let dict = result?.toDictionary() as? [String: Any] else { return nil }
        let chapters: [NovelChapter] = (dict["chapters"] as? [[String: Any]] ?? []).compactMap {
            guard let name = $0["name"] as? String, let cPath = $0["path"] as? String else { return nil }
            return NovelChapter(
                name:          name,
                path:          cPath,
                chapterNumber: $0["chapterNumber"] as? Double,
                releaseTime:   $0["releaseTime"]   as? String
            )
        }
        return SourceNovel(
            path:     dict["path"]    as? String ?? path,
            name:     dict["name"]    as? String ?? "",
            cover:    dict["cover"]   as? String,
            author:   dict["author"]  as? String,
            summary:  dict["summary"] as? String,
            status:   dict["status"]  as? String,
            chapters: chapters
        )
    }

    nonisolated func parseChapter(path: String) -> String {
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("parseChapter")?
            .call(withArguments: [path])
        return result?.toString() ?? ""
    }

    // MARK: - Parsers

    nonisolated private static func parseMangaArray(_ value: JSValue?, sourceId: String) -> [Manga] {
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
                summary:       dict["summary"] as? String,
                author:        dict["author"]  as? String,
                artist:        dict["artist"]  as? String,
                status:        MangaStatus(rawValue: dict["status"] as? String ?? "") ?? .unknown,
                genres:        dict["genres"]  as? [String] ?? [],
                inLibrary:     false,
                isLocal:       false,
                lastReadAt:    nil,
                lastUpdatedAt: nil
            )
        }
    }

    nonisolated private static func parseChapterArray(_ value: JSValue?, mangaId: String) -> [Chapter] {
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

    nonisolated private static func parseNovelItems(_ value: JSValue?) -> [NovelItem] {
        guard let items = value?.toArray() as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard
                let name = dict["name"] as? String,
                let path = dict["path"] as? String
            else { return nil }
            return NovelItem(name: name, path: path, cover: dict["cover"] as? String)
        }
    }
}
