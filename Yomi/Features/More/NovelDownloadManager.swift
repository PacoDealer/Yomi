import Foundation
import CryptoKit

// MARK: - NovelDownloadStore

/// Offline novel chapters on disk: `Documents/NovelDownloads/<hash(novelId)>/<hash(chapter path)>.html`,
/// plus a `novel.json` so the Downloads screen can list a title that isn't in the library.
///
/// Keyed by the chapter's source path, not `NovelChapter.id`: ids are "<novelId>-ch-<index>" and shift
/// whenever a source inserts a chapter, so an id-keyed file could come back as the wrong chapter.
/// Novel ids contain the source path (slashes and all), hence the hashed folder name.
/// "Downloaded" means "the file exists" — no DB column, no migration, nothing for CloudKit to sync.
nonisolated enum NovelDownloadStore {

    struct Meta: Codable, Sendable {
        let id: String
        let path: String
        let sourceId: String
        let title: String
        let coverURL: String?
    }

    struct Group: Sendable {
        let meta: Meta
        let chapterCount: Int
        let byteSize: Int64
    }

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovelDownloads", isDirectory: true)
    }

    static func directory(novelId: String) -> URL {
        root.appendingPathComponent(hash(novelId), isDirectory: true)
    }

    static func fileURL(novelId: String, chapterPath: String) -> URL {
        directory(novelId: novelId).appendingPathComponent(hash(chapterPath) + ".html")
    }

    static func content(novelId: String, chapterPath: String) -> String? {
        try? String(contentsOf: fileURL(novelId: novelId, chapterPath: chapterPath), encoding: .utf8)
    }

    static func save(_ html: String, chapterPath: String, meta: Meta) throws {
        let dir = directory(novelId: meta.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let metaURL = dir.appendingPathComponent("novel.json")
        if !FileManager.default.fileExists(atPath: metaURL.path) {
            try JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
        }
        try Data(html.utf8).write(to: fileURL(novelId: meta.id, chapterPath: chapterPath), options: .atomic)
    }

    static func delete(novelId: String, chapterPaths: [String]) {
        for path in chapterPaths {
            try? FileManager.default.removeItem(at: fileURL(novelId: novelId, chapterPath: path))
        }
        // Drop the folder once the last chapter is gone so the Downloads screen stops listing it.
        let dir = directory(novelId: novelId)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        if !left.contains(where: { $0.hasSuffix(".html") }) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func deleteAll(novelId: String) {
        try? FileManager.default.removeItem(at: directory(novelId: novelId))
    }

    /// Ids of the given chapters that have a file on disk. One directory listing + a hash per chapter.
    static func downloadedChapterIds(novelId: String, chapters: [NovelChapter]) -> Set<String> {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: directory(novelId: novelId).path)) ?? [])
        guard !names.isEmpty else { return [] }
        return Set(chapters.filter { names.contains(hash($0.path) + ".html") }.map(\.id))
    }

    /// Every novel with at least one downloaded chapter, for the Downloads screen.
    static func allGroups() -> [Group] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("novel.json")),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data),
                  let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
            else { return nil }
            let chapters = files.filter { $0.pathExtension == "html" }
            guard !chapters.isEmpty else { return nil }
            let bytes = chapters.reduce(Int64(0)) {
                $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return Group(meta: meta, chapterCount: chapters.count, byteSize: bytes)
        }
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - NovelDownloadManager

/// Downloads novel chapter text one chapter at a time (sources are scraped HTML; hammering them gets
/// the whole source Cloudflare-blocked). The manga `DownloadManager` is page-image based and keyed on a
/// DB column, so novels get their own small queue instead of being bolted onto it.
@Observable final class NovelDownloadManager {

    static let shared = NovelDownloadManager()
    private init() {}

    struct Job: Identifiable {
        let chapter: NovelChapter
        let novel: Novel
        var id: String { chapter.id }
    }

    /// Per-novel progress for the Downloads screen: one row per novel, not one per chapter.
    struct Batch: Identifiable {
        let novel: Novel
        var total: Int
        var done: Int
        var id: String { novel.id }
    }

    private(set) var queue: [Job] = []
    private(set) var active: Job? = nil
    private(set) var batches: [Batch] = []

    /// Bumped after every saved chapter; `lastSaved` says which one.
    private(set) var completedCount = 0
    private(set) var lastSaved: (novelId: String, chapterId: String)? = nil
    /// Bumped when a novel's batch finishes or is cancelled — the Downloads screen reloads on this.
    private(set) var finishedBatchCount = 0

    var failureMessage: String? = nil

    private var worker: Task<Void, Never>? = nil

    var isRunning: Bool { active != nil || !queue.isEmpty }
    private(set) var isWaitingForNetwork = false

    func isPending(chapterId: String) -> Bool {
        active?.chapter.id == chapterId || queue.contains { $0.chapter.id == chapterId }
    }

    // MARK: - Enqueue

    /// Queues the chapters that aren't downloaded or already queued. `front` puts them ahead of a bulk
    /// download — download-ahead from the reader must not wait behind "Download all".
    func enqueue(_ chapters: [NovelChapter], novel: Novel, front: Bool = false) {
        let novelId = novel.id
        let jobs = chapters
            .filter { ch in
                !isPending(chapterId: ch.id)
                    && !FileManager.default.fileExists(atPath: NovelDownloadStore.fileURL(novelId: novelId, chapterPath: ch.path).path)
            }
            .map { Job(chapter: $0, novel: novel) }
        guard !jobs.isEmpty else { return }
        if front {
            queue.insert(contentsOf: jobs, at: 0)
        } else {
            queue.append(contentsOf: jobs)
            // Only for downloads the user asked for — download-ahead waiting quietly is expected.
            NetworkMonitor.shared.noteQueued()
        }
        if let i = batches.firstIndex(where: { $0.novel.id == novelId }) {
            batches[i].total += jobs.count
        } else {
            batches.append(Batch(novel: novel, total: jobs.count, done: 0))
        }
        if worker == nil {
            worker = Task { await run() }
        }
    }

    /// Keeps the `count` chapters after `index` on device. Library novels only — a browse-only novel
    /// would leave files nothing in the app points back to.
    func downloadAhead(novel: Novel, chapters: [NovelChapter], after index: Int, count: Int) {
        guard count > 0, novel.inLibrary, index + 1 < chapters.count else { return }
        let upper = min(chapters.count, index + 1 + count)
        enqueue(Array(chapters[(index + 1)..<upper]), novel: novel, front: true)
    }

    // MARK: - Cancel / delete

    func cancel(novelId: String) {
        queue.removeAll { $0.novel.id == novelId }
        finishBatch(novelId: novelId)
    }

    func delete(chapters: [NovelChapter], novelId: String) {
        let ids = Set(chapters.map(\.id))
        queue.removeAll { $0.novel.id == novelId && ids.contains($0.chapter.id) }
        NovelDownloadStore.delete(novelId: novelId, chapterPaths: chapters.map(\.path))
        finishedBatchCount += 1
    }

    func deleteAll(novelId: String) {
        cancel(novelId: novelId)
        NovelDownloadStore.deleteAll(novelId: novelId)
        finishedBatchCount += 1
    }

    // MARK: - Worker

    private func run() async {
        // One worker, so a bridge is never used by two tasks at once (JSBridge rule). Fresh bridges,
        // not the detail view's or the reader's, since those are busy on their own tasks.
        var bridges: [String: JSBridge] = [:]
        var failuresInARow: [String: Int] = [:]

        while !queue.isEmpty {
            // Pause between chapters while the Wi-Fi-only setting holds downloads back; resumes on its own.
            if !NetworkMonitor.shared.downloadsAllowed {
                isWaitingForNetwork = true
                await NetworkMonitor.shared.waitUntilDownloadsAllowed()
                isWaitingForNetwork = false
                guard !queue.isEmpty else { break }
            }
            let job = queue.removeFirst()
            active = job
            let novel = job.novel
            let sourceId = novel.sourceId
            if bridges[sourceId] == nil,
               let ext = ExtensionManager.shared.installed.first(where: { $0.id == sourceId }) {
                bridges[sourceId] = ExtensionManager.shared.bridge(for: ext)
            }
            guard let bridge = bridges[sourceId] else {
                active = nil
                failureMessage = "\(novel.title): its source isn't installed"
                cancel(novelId: novel.id)
                continue
            }

            let path = job.chapter.path
            let meta = NovelDownloadStore.Meta(id: novel.id, path: novel.path, sourceId: sourceId,
                                               title: novel.title, coverURL: novel.coverURL?.absoluteString)
            let saved = await Task.detached(priority: .utility) { () -> Bool in
                let html = bridge.parseChapter(path: path)
                guard !html.isEmpty else { return false }
                return (try? NovelDownloadStore.save(html, chapterPath: path, meta: meta)) != nil
            }.value
            active = nil

            if saved {
                failuresInARow[novel.id] = 0
                lastSaved = (novel.id, job.chapter.id)
                completedCount += 1
            } else {
                let fails = (failuresInARow[novel.id] ?? 0) + 1
                failuresInARow[novel.id] = fails
                // Three misses in a row is a blocked or offline source, not a bad chapter — stop
                // instead of burning through hundreds of queued requests against it.
                if fails >= 3 {
                    failureMessage = "\(novel.title): downloads stopped — the source isn't returning chapters"
                    cancel(novelId: novel.id)
                    continue
                }
            }
            if let i = batches.firstIndex(where: { $0.novel.id == novel.id }) {
                batches[i].done += 1
            }
            if !queue.contains(where: { $0.novel.id == novel.id }) {
                finishBatch(novelId: novel.id)
            }
            // Space requests out a little; these are scraped sites.
            try? await Task.sleep(for: .milliseconds(250))
        }
        worker = nil
        NetworkMonitor.shared.queueDrained()
    }

    private func finishBatch(novelId: String) {
        guard active?.novel.id != novelId else { return }
        batches.removeAll { $0.novel.id == novelId }
        finishedBatchCount += 1
    }
}
