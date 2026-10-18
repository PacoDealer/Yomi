import Foundation
import ImageIO
import Observation
import Kingfisher

/// Loads the pages after the one on screen before they are reached (S161; S158 top-10 #1). Martin, S159: scrolling an
/// Asura chapter "a bit fast", some pages still took a moment to appear — nothing loaded a page until its view was
/// built. Idea from Mihon's `HttpPageLoader` (Apache-2.0; re-written, no code copied): the pages just ahead go first,
/// then one behind, and the plan is rebuilt on every page change; near the end it reaches into the next chapter.
///
/// Pages go to Kingfisher's DISK cache only: a decoded 900x16000 page is ~57 MB, and holding several of them in memory
/// would undo the S160 memory fix (#209). The reader's own load then finds the file on disk. Same cache serializer as
/// `KFImage.readerPageOptions`, so the cache key matches every reader mode.
@MainActor final class ReaderPagePrefetcher {
    static let ahead = 6
    static let behind = 1

    private var prefetcher: ImagePrefetcher?
    private var wanted: [URL] = []

    /// Loading options for a prefetched page. `ImagePrefetcher` does NOT merge `KingfisherManager.defaultOptions`, so
    /// they're added here: the global request modifier carries the user agent and a Keiyoushi page's own headers.
    private static var options: KingfisherOptionsInfo {
        KingfisherManager.shared.defaultOptions + KFImage.readerPageOptions.filter {
            if case .backgroundDecode = $0 { return false }   // nothing is shown, so nothing to decode
            return true
        } + [.memoryCacheExpiration(.expired),                 // = never stored in memory
             .waitForCache]                                     // the file exists when the batch reports back
    }

    /// `current` is the page on screen; `nextChapterPages` is the next chapter's list once the reader has it.
    func update(pages: [String], current: Int, nextChapterPages: [String]) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-noPagePrefetch") { return }   // A/B against the old reader
        #endif
        let network = NetworkMonitor.shared
        guard network.isConnected, !network.isConstrained, !pages.isEmpty else { stop(); return }

        var order: [String] = []
        let last = min(pages.count - 1, current + Self.ahead)
        if current + 1 <= last { order += pages[(current + 1)...last] }
        let spill = Self.ahead - max(0, last - current)
        if spill > 0 { order += nextChapterPages.prefix(spill) }
        for back in stride(from: current - 1, through: max(0, current - Self.behind), by: -1) where back < pages.count {
            order.append(pages[back])
        }
        // Downloaded and local pages are files already.
        let urls = order.compactMap(URL.init(string:)).filter { $0.scheme == "http" || $0.scheme == "https" }
        guard urls != wanted else { return }
        wanted = urls

        // Start the new plan BEFORE stopping the old one: a page both plans want keeps its running download
        // (Kingfisher shares one download per URL) instead of being cancelled and fetched again.
        let old = prefetcher
        if urls.isEmpty {
            prefetcher = nil
        } else {
            // Each prefetched page's shape is read from the file's header (no decode), so its placeholder already has
            // the page's real height and nothing below it jumps when it appears (S161).
            let next = ImagePrefetcher(urls: urls, options: Self.options, completionHandler: { skipped, _, completed in
                Self.learnShapes(of: (skipped + completed).map(\.downloadURL))
            })
            next.maxConcurrentDownloads = 3   // leave room for the page the reader is loading right now
            next.start()
            prefetcher = next
        }
        old?.stop()
    }

    nonisolated private static func learnShapes(of urls: [URL]) {
        Task { @MainActor in await PageShapes.learn(urls.map(\.absoluteString)) }
    }

    func stop() {
        prefetcher?.stop()
        prefetcher = nil
        wanted = []
    }
}

/// Width / height of every page shown or prefetched in the scrolling readers. Saved to Caches (S161): a chapter
/// reopened after a relaunch scrolls to its saved page with every page above it already at its real height, instead
/// of one-screen boxes that grow as they load and push the page you were on away.
@MainActor enum PageShapes {
    private static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("page-shapes.json")
    private static var store: [String: CGFloat]?
    private static var dirty = false

    static func aspect(_ url: String) -> CGFloat? { loaded()[key(url)] }

    static func remember(_ url: String, _ aspect: CGFloat) {
        let key = key(url)
        guard loaded()[key] != aspect else { return }
        if (store?.count ?? 0) > 5000 { store?.removeAll() }
        store?[key] = aspect   // in place: no copy of the whole table per page
        dirty = true
        changes.count += 1
    }

    /// Keiyoushi pages are `127.0.0.1:<port>/image/<random token>` — a new address every launch, so a shape saved
    /// under it never matched again and a resumed chapter met one-screen boxes above the saved page that grew as
    /// they loaded (Martin, S182: "glitches for a second" on resume). Those pages are kept under chapter + index.
    private static var names: [String: String] = [:]

    static func name(_ urls: [String], chapterId: String) {
        if names.count > 5000 { names.removeAll() }
        for (index, url) in urls.enumerated() where KeiyoushiBridge.isBridgeImage(URL(string: url)) {
            names[url] = "\(chapterId)#\(index)"
        }
    }

    private static func key(_ url: String) -> String { names[url] ?? url }

    /// Bumped whenever a shape is learned: two-page mode re-pairs its pages as their shapes come in (F17).
    static let changes = Changes()
    @Observable final class Changes { var count = 0 }

    /// Reads unknown pages' shapes from the file header (no decode): downloaded and local pages from their file, web
    /// pages from Kingfisher's disk cache when they're in it (S161, prefetched pages; F17, two-page mode).
    static func learn(_ urls: [String]) async {
        let cache = ImageCache.default
        let unknown: [(String, String)] = urls.compactMap { url in
            guard aspect(url) == nil, let u = URL(string: url) else { return nil }
            return (url, u.isFileURL ? u.path : cache.cachePath(forKey: u.cacheKey))
        }
        guard !unknown.isEmpty else { return }
        let found = await Task.detached(priority: .utility) { () -> [(String, CGFloat)] in
            unknown.compactMap { url, path in
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
                      let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 else { return nil }
                return (url, w / h)
            }
        }.value
        for (url, aspect) in found { remember(url, aspect) }
    }

    /// Called when the reader closes.
    static func save() {
        guard dirty, let shapes = store else { return }
        dirty = false
        let file = file
        Task.detached(priority: .utility) { try? JSONEncoder().encode(shapes).write(to: file, options: .atomic) }
    }

    private static func loaded() -> [String: CGFloat] {
        if let store { return store }
        let shapes = (try? JSONDecoder().decode([String: CGFloat].self, from: Data(contentsOf: file))) ?? [:]
        store = shapes
        return shapes
    }
}
