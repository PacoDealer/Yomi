import Foundation
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
        } + [.memoryCacheExpiration(.expired)]                // = never stored in memory
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
            let next = ImagePrefetcher(urls: urls, options: Self.options)
            next.maxConcurrentDownloads = 3   // leave room for the page the reader is loading right now
            next.start()
            prefetcher = next
        }
        old?.stop()
    }

    func stop() {
        prefetcher?.stop()
        prefetcher = nil
        wanted = []
    }
}
