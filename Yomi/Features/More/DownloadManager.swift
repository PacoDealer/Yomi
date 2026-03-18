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
    var activeChapterId: String? = nil
    var progress: [String: Double] = [:]
    var isRunning: Bool = false

    // MARK: - Private

    private struct QueueItem {
        let chapter: Chapter
        let manga: Manga
        let bridge: JSBridge
    }

    private var items: [QueueItem] = []
    private var currentTask: Task<Void, Never>? = nil

    // MARK: - Directories

    private func downloadsDirectory(mangaId: String, chapterId: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads/\(mangaId)/\(chapterId)", isDirectory: true)
    }

    // MARK: - Enqueue

    func enqueue(_ chapter: Chapter, manga: Manga, bridge: JSBridge) {
        guard !chapter.isDownloaded,
              !items.contains(where: { $0.chapter.id == chapter.id })
        else { return }
        items.append(QueueItem(chapter: chapter, manga: manga, bridge: bridge))
        queue = items.map(\.chapter)
        processQueue()
    }

    // MARK: - Cancel

    func cancel(chapterId: String) {
        if activeChapterId == chapterId {
            currentTask?.cancel()
            currentTask = nil
            activeChapter = nil
            activeChapterId = nil
            isRunning = false
            progress.removeValue(forKey: chapterId)
        } else {
            items.removeAll { $0.chapter.id == chapterId }
            queue = items.map(\.chapter)
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

    func localURLs(for chapter: Chapter) -> [URL]? {
        let dir = downloadsDirectory(mangaId: chapter.mangaId, chapterId: chapter.id)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return nil }
        let sorted = files
            .filter { $0.pathExtension == "dat" }
            .sorted {
                let a = Int($0.deletingPathExtension().lastPathComponent) ?? 0
                let b = Int($1.deletingPathExtension().lastPathComponent) ?? 0
                return a < b
            }
        return sorted.isEmpty ? nil : sorted
    }

    // MARK: - Process Queue

    private func processQueue() {
        guard !isRunning, !items.isEmpty else { return }
        let item = items.removeFirst()
        queue = items.map(\.chapter)
        isRunning = true
        activeChapter = item.chapter
        activeChapterId = item.chapter.id
        progress[item.chapter.id] = 0.0

        currentTask = Task {
            await performDownload(item)
            processQueue()
        }
    }

    // MARK: - Download

    private func performDownload(_ item: QueueItem) async {
        let chapterId   = item.chapter.id
        let chapterPath = item.chapter.path
        let bridge      = item.bridge

        // 1. Get page list — bridge.getPageList blocks via DispatchSemaphore, must run off MainActor
        let urls = await Task.detached(priority: .userInitiated) {
            bridge.getPageList(chapterPath: chapterPath)
        }.value

        guard !urls.isEmpty else {
            activeChapter = nil
            activeChapterId = nil
            isRunning = false
            return
        }

        // 2. Create destination directory
        let dir = downloadsDirectory(mangaId: item.manga.id, chapterId: chapterId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let total = urls.count
        var completed = 0

        // 3. Download pages — max 3 concurrent via sliding-window withTaskGroup
        await withTaskGroup(of: (Int, Data?).self) { group in
            var nextIndex = 0

            // Seed initial batch
            while nextIndex < min(3, total) {
                let idx    = nextIndex
                let urlStr = urls[idx]
                group.addTask {
                    guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
                    else { return (idx, nil) }
                    let data = try? await URLSession.shared.data(from: url).0
                    return (idx, data)
                }
                nextIndex += 1
            }

            // Process results; add next task as each slot frees up
            for await (idx, data) in group {
                completed += 1

                if let data {
                    let fileURL = dir.appendingPathComponent("\(idx).dat")
                    try? data.write(to: fileURL)
                }

                // 4. Update progress (already on MainActor — direct assignment)
                progress[chapterId] = Double(completed) / Double(total)

                if nextIndex < total {
                    let ni     = nextIndex
                    let urlStr = urls[ni]
                    group.addTask {
                        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
                        else { return (ni, nil) }
                        let data = try? await URLSession.shared.data(from: url).0
                        return (ni, data)
                    }
                    nextIndex += 1
                }
            }
        }

        // 5. Persist download state in DB
        try? DownloadQueries.markDownloaded(chapterId: chapterId)

        // 6. Reset active state
        activeChapter = nil
        activeChapterId = nil
        isRunning = false
    }
}
