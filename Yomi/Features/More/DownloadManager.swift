import Foundation
import SwiftUI

// MARK: - DownloadManager

@Observable final class DownloadManager {

    // MARK: - Singleton

    static let shared = DownloadManager()
    private init() {}

    // MARK: - Public State

    var queue: [Chapter] = []
    var activeChapter: Chapter? = nil
    var activeManga: Manga? = nil
    var activeChapterId: String? = nil
    var progress: [String: Double] = [:]
    var isRunning: Bool = false

    /// Manga for queued items, in queue order
    var queueMangas: [Manga] = []

    /// Increments each time a download finishes — views observe this to refresh chapter state
    var completedDownloadCount: Int = 0

    /// Set when a chapter download completes with missing pages (network/disk failure) instead of
    /// being silently marked "Downloaded". Views surface it via `.yomiToast($...)` and clear it.
    var failureMessage: String? = nil

    /// S162: user pause, or the low-storage stop. A paused queue keeps its items (the running chapter goes back to the
    /// front, its pages stay on disk) and starts nothing until `resume()`.
    var isPaused: Bool = false
    /// Why the queue paused on its own (low storage); nil for a user pause.
    var pauseMessage: String? = nil

    /// A chapter whose download didn't finish — kept so the Downloads screen can offer "Retry". Its pages stay on
    /// disk, so a retry only fetches the missing ones.
    struct FailedDownload: Identifiable {
        let chapter: Chapter
        let manga: Manga
        let reason: String
        fileprivate let bridge: JSBridge?
        var id: String { chapter.id }
    }
    var failed: [FailedDownload] = []

    /// Below this much free space the queue pauses before the next chapter (or after a page write fails).
    nonisolated static let minimumFreeBytes: Int64 = 200 * 1024 * 1024

    // MARK: - Private

    private struct QueueItem {
        let chapter: Chapter
        let manga: Manga
        /// nil for Keiyoushi and Suwayomi titles — pages come from the on-device extension / the server (S142).
        let bridge: JSBridge?
    }

    /// Whether a manga's chapters can be downloaded: a JS plugin, or a Keiyoushi / Suwayomi title.
    /// Keiyoushi titles were locked out until S142 because the queue required a JS plugin.
    static func canDownload(_ manga: Manga, bridge: JSBridge?) -> Bool {
        bridge != nil || KeiyoushiMapping.isKeiyoushiSourceId(manga.sourceId)
            || SuwayomiService.isSuwayomiSourceId(manga.sourceId)
    }

    private var items: [QueueItem] = []
    private var currentTask: Task<Void, Never>? = nil

    /// Why the running task was cancelled: a cancel deletes the chapter's pages, a pause keeps them.
    private enum StopReason { case cancel, pause }
    private var stopReason: StopReason? = nil

    private enum Outcome { case done, failed(String), stopped, lowStorage }

    private func publishQueue() {
        queue = items.map(\.chapter)
        queueMangas = items.map { $0.manga }
    }

    // MARK: - Directories

    private func downloadsDirectory(mangaId: String, chapterId: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads/\(mangaId)/\(chapterId)", isDirectory: true)
    }

    // MARK: - Enqueue

    func enqueue(_ chapter: Chapter, manga: Manga, bridge: JSBridge?) {
        guard Self.canDownload(manga, bridge: bridge),
              !chapter.isDownloaded,
              chapter.id != activeChapterId,   // #112: the running one already left `items`
              !items.contains(where: { $0.chapter.id == chapter.id })
        else { return }
        failed.removeAll { $0.chapter.id == chapter.id }
        items.append(QueueItem(chapter: chapter, manga: manga, bridge: bridge))
        NetworkMonitor.shared.noteQueued()
        publishQueue()
        processQueue()
    }

    // MARK: - Retry

    func retry(_ item: FailedDownload) {
        enqueue(item.chapter, manga: item.manga, bridge: item.bridge)
    }

    func retryAllFailed() {
        for item in failed { retry(item) }
    }

    func dismissFailed() {
        failed = []
    }

    // MARK: - Pause / Resume

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        if activeChapterId != nil {
            stopReason = .pause
            currentTask?.cancel()
        }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        pauseMessage = nil
        processQueue()
    }

    // MARK: - Cancel

    func cancel(chapterId: String) {
        if activeChapterId == chapterId {
            // The task finishes on its own (deletes the pages, then starts the next item); `isRunning` stays true until
            // then so nothing new starts underneath it.
            stopReason = .cancel
            currentTask?.cancel()
            activeChapter = nil
            activeManga = nil
            activeChapterId = nil
            progress.removeValue(forKey: chapterId)
        } else {
            items.removeAll { $0.chapter.id == chapterId }
            publishQueue()
            progress.removeValue(forKey: chapterId)
        }
    }

    // MARK: - Delete

    func deleteDownload(chapter: Chapter) {
        let dir = downloadsDirectory(mangaId: chapter.mangaId, chapterId: chapter.id)
        try? FileManager.default.removeItem(at: dir)
        try? DownloadQueries.markNotDownloaded(chapterId: chapter.id)
    }

    // MARK: - Query

    func isDownloaded(chapterId: String) -> Bool {
        (try? ChapterQueries.fetchOne(id: chapterId))?.isDownloaded ?? false
    }

    /// Recursive byte size of a manga's downloads folder. Pure FileManager I/O — safe to call
    /// from Task.detached (Downloads screen computes this per manga off MainActor).
    nonisolated func directorySize(mangaId: String) -> Int64 {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads/\(mangaId)", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func localURLs(for chapter: Chapter) -> [URL]? {
        localPages(for: chapter)?.urls
    }

    /// A downloaded chapter's images in reading order, with the source page each one belongs to (D12: a tall page may
    /// be stored as several parts).
    func localPages(for chapter: Chapter) -> DownloadedPages? {
        DownloadedPages(dir: downloadsDirectory(mangaId: chapter.mangaId, chapterId: chapter.id))
    }

    // MARK: - Process Queue

    /// True while the queue is held back by the Wi-Fi-only setting (or no connection). The waiting
    /// item stays in `queue` — nothing is "active" until the network allows it.
    var isWaitingForNetwork: Bool = false

    private func processQueue() {
        guard !isRunning, !isPaused else { return }
        guard !items.isEmpty else {
            NetworkMonitor.shared.queueDrained()
            return
        }
        isRunning = true

        currentTask = Task {
            // Pause between chapters, not mid-chapter: a switch to cellular holds the next one.
            if !NetworkMonitor.shared.downloadsAllowed {
                isWaitingForNetwork = true
                await NetworkMonitor.shared.waitUntilDownloadsAllowed()
                isWaitingForNetwork = false
            }
            // Everything may have been cancelled, or the queue paused, while waiting.
            guard !items.isEmpty, !isPaused else {
                isRunning = false
                processQueue()
                return
            }
            guard Self.hasRoomForDownloads() else {
                pauseForLowStorage()
                isRunning = false
                return
            }
            let item = items.removeFirst()
            publishQueue()
            activeChapter = item.chapter
            activeManga = item.manga
            activeChapterId = item.chapter.id
            progress[item.chapter.id] = 0.0
            stopReason = nil

            let outcome = await performDownload(item)
            let dir = downloadsDirectory(mangaId: item.manga.id, chapterId: item.chapter.id)
            switch outcome {
            case .done:
                try? DownloadQueries.markDownloaded(chapterId: item.chapter.id)
            case .failed(let reason):
                // Pages that did land stay on disk: Retry skips them.
                failed.removeAll { $0.chapter.id == item.chapter.id }
                failed.append(FailedDownload(chapter: item.chapter, manga: item.manga, reason: reason, bridge: item.bridge))
                failureMessage = "\(item.chapter.name): \(reason)"
                YomiHaptics.error()
            case .lowStorage:
                items.insert(item, at: 0)
                publishQueue()
                pauseForLowStorage()
            case .stopped:
                if stopReason == .pause {
                    items.insert(item, at: 0)
                    publishQueue()
                } else {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
            stopReason = nil
            progress.removeValue(forKey: item.chapter.id)

            // Signal completion so MangaDetailView can refresh chapter state
            completedDownloadCount += 1
            activeChapter = nil
            activeManga = nil
            activeChapterId = nil
            isRunning = false
            processQueue()
        }
    }

    private func pauseForLowStorage() {
        isPaused = true
        pauseMessage = String(localized: "Paused — less than 200 MB free on this iPhone")
        YomiHaptics.error()
    }

    /// Free space for user-requested data ("important usage" counts space iOS can purge for us).
    nonisolated static func hasRoomForDownloads() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-yomiSimulateLowStorage") { return false }
        #endif
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let free = try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        else { return true }
        return free >= minimumFreeBytes
    }

    // MARK: - Download

    /// Downloads one chapter's missing pages. Never marks the chapter downloaded itself — the caller does, on `.done`.
    private func performDownload(_ item: QueueItem) async -> Outcome {
        let chapterId   = item.chapter.id
        let chapterPath = item.chapter.path
        let bridge      = item.bridge

        // 1. Get the page list the same way the reader does (JS plugin off MainActor, Keiyoushi through the
        //    embedded JVM — its pages are 127.0.0.1 image URLs the extension serves, already descrambled).
        let urls = await ChapterReaderView.fetchPages(bridge: bridge, path: chapterPath)
        if Task.isCancelled { return .stopped }

        // An empty page list means the plugin fetch failed (JS exceptions are swallowed and return []) — surface it
        // instead of dropping the chapter out of the queue silently.
        guard !urls.isEmpty else { return .failed("could not load pages") }

        // 2. Create destination directory. Pages already there (an earlier failed or paused try) are kept and skipped:
        //    every page is written atomically, so a file that exists is a whole page.
        let dir = downloadsDirectory(mangaId: item.manga.id, chapterId: chapterId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Self.removeStalePages(in: dir, keepingBelow: urls.count)
        let onDisk = DownloadedPages.scan(dir)
        for file in onDisk.incomplete { try? FileManager.default.removeItem(at: file) }

        let total = urls.count
        var missing: [Int] = []
        for idx in 0..<total where onDisk.pages[idx] == nil { missing.append(idx) }
        var completed = total - missing.count
        var failedPages = 0
        var outOfSpace = false
        progress[chapterId] = Double(completed) / Double(total)

        // 3. Download pages — concurrent via sliding-window withTaskGroup
        let concurrentLimit = max(1, AppSettings.shared.concurrentDownloads)
        let splitTall = AppSettings.shared.splitTallPages
        await withTaskGroup(of: (Int, [Data]?).self) { group in
            var next = 0
            func addNext() {
                guard next < missing.count else { return }
                let idx = missing[next]
                let urlStr = urls[idx]
                group.addTask {
                    guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
                    else { return (idx, nil) }
                    guard let data = await Self.pageDataWithRetries(url) else { return (idx, nil) }
                    // D12: a very tall page is stored as parts (`TallPageSplitter`); anything else as fetched.
                    guard splitTall, let parts = await TallPageSplitter.shared.parts(of: data) else { return (idx, [data]) }
                    return (idx, parts)
                }
                next += 1
            }
            for _ in 0..<concurrentLimit { addNext() }

            for await (idx, parts) in group {
                // A page counts as landed only if its bytes actually reached disk — both the fetch and the write can
                // fail, and neither must be mistaken for success. A split page counts once all its parts are written;
                // a half-written set is removed (and `DownloadedPages.scan` ignores one a crash leaves behind).
                if let parts {
                    let files = parts.indices.map {
                        dir.appendingPathComponent(DownloadedPages.fileName(page: idx, part: $0, of: parts.count))
                    }
                    do {
                        for (part, file) in zip(parts, files) { try part.write(to: file, options: .atomic) }
                        completed += 1
                    } catch {
                        for file in files { try? FileManager.default.removeItem(at: file) }
                        failedPages += 1
                        if !Self.hasRoomForDownloads() { outOfSpace = true }
                    }
                } else {
                    failedPages += 1
                }
                progress[chapterId] = Double(completed) / Double(total)
                if Task.isCancelled || outOfSpace {
                    group.cancelAll()
                } else {
                    addNext()
                }
            }
        }

        if Task.isCancelled { return .stopped }
        if outOfSpace { return .lowStorage }
        if failedPages > 0 { return .failed("\(failedPages) of \(total) pages failed to download") }
        return .done
    }

    /// A chapter whose page list got shorter since the last try must not keep the old extra pages — `localURLs`
    /// would show them at the end.
    nonisolated private static func removeStalePages(in dir: URL, keepingBelow count: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "dat" {
            // `<page>.dat` or a part `<page>-<part>of<count>.dat` (D12)
            let name = file.deletingPathExtension().lastPathComponent
            if let idx = Int(name.split(separator: "-").first ?? ""), idx >= count {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Page fetch

    private enum PageResult: Sendable { case page(Data), retryable, permanent }

    /// Waits before each retry of a page. Three retries, then the page counts as failed.
    nonisolated private static let retryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]

    nonisolated private static func pageDataWithRetries(_ url: URL) async -> Data? {
        var attempt = 0
        while true {
            switch await pageData(url) {
            case .page(let data): return data
            case .permanent: return nil
            case .retryable:
                guard attempt < retryDelays.count, !Task.isCancelled else { return nil }
                do { try await Task.sleep(for: retryDelays[attempt]) } catch { return nil }
                attempt += 1
            }
        }
    }

    #if DEBUG
    /// `-yomiDownloadFlakyPages`: every page's first request fails as if the connection dropped, so the retry path runs.
    /// `-yomiDownloadFailPages`: every page fails for good (the Failed list / Retry path).
    nonisolated private static let flakyPages = ProcessInfo.processInfo.arguments.contains("-yomiDownloadFlakyPages")
    nonisolated private static let failPages = ProcessInfo.processInfo.arguments.contains("-yomiDownloadFailPages")
    nonisolated(unsafe) private static var flakySeen = Set<URL>()
    nonisolated private static let flakyLock = NSLock()
    #endif

    /// One page's bytes. Keiyoushi pages now come back as direct CDN URLs that may need the source's headers (S159),
    /// and a refused request returns an error page, not an image — only a 2xx body counts as a page. Network errors,
    /// 5xx, 408 and 429 are worth retrying; any other 4xx (gone, forbidden) is not.
    nonisolated private static func pageData(_ url: URL) async -> PageResult {
        #if DEBUG
        if failPages { return .permanent }
        if flakyPages {
            let first = flakyLock.withLock { flakySeen.insert(url).inserted }
            if first { return .retryable }
        }
        #endif
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: KeiyoushiCovers.shared.request(for: url))
        } catch {
            if (error as? URLError)?.code == .cancelled || Task.isCancelled { return .permanent }
            return .retryable
        }
        guard let http = response as? HTTPURLResponse else { return .page(data) }
        switch http.statusCode {
        case 200..<300: return .page(data)
        case 408, 429, 500...: return .retryable
        default: return .permanent
        }
    }
}
