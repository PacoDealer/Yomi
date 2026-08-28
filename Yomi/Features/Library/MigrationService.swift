import Foundation

// MARK: - MigrationService
//
// Tachimanga parity: move a library manga from one source to another, preserving reading
// progress/categories/status. Chapter read-state transfers by matching chapterNumber between
// the old and new source's chapter lists — sources rarely agree on chapter IDs/paths, but
// chapter numbering is the one thing that's usually consistent across scanlations.

enum MigrationService {

    struct Result {
        let matchedChapters: Int
        let oldReadChapters: Int
        let newChapterCount: Int
    }

    enum MigrationError: LocalizedError {
        case noChaptersFromNewSource

        var errorDescription: String? {
            switch self {
            case .noChaptersFromNewSource:
                return "The new source returned no chapters. Nothing was changed — your original "
                     + "entry is untouched. The source may be temporarily blocked or unreachable."
            }
        }
    }

    /// Runs entirely off MainActor — safe to call from Task.detached.
    nonisolated static func migrate(
        from oldManga: Manga,
        to newManga: Manga,
        bridge: JSBridge,
        removeOld: Bool
    ) throws -> Result {
        // 1. Fetch the new source's chapters FIRST. A plugin swallows its own JS exceptions and
        // returns [] on failure, indistinguishable from "this title genuinely has no chapters" —
        // either way there is nothing to migrate to, so bail before touching the library. Doing
        // this before the writes below is what keeps a failed migration from deleting the old
        // entry (and its downloads) and stranding the user with a chapterless manga.
        let newChapters = bridge.getChapterList(mangaPath: newManga.path, mangaId: newManga.id)
        guard !newChapters.isEmpty else { throw MigrationError.noChaptersFromNewSource }

        // 2. Persist the new manga as a library entry, carrying over user-owned state.
        var toSave = newManga
        toSave.inLibrary = true
        toSave.readingStatus = oldManga.readingStatus
        toSave.notes = oldManga.notes
        toSave.lastReadAt = oldManga.lastReadAt
        toSave.readingSeconds = oldManga.readingSeconds
        try MangaQueries.upsert(toSave)

        try ChapterQueries.insertAllIgnoringConflicts(newChapters)
        let freshNewChapters = try ChapterQueries.fetchAll(mangaId: newManga.id)

        // 3. Transfer categories.
        let oldCategories = try CategoryQueries.categoriesForManga(mangaId: oldManga.id)
        for cat in oldCategories {
            try CategoryQueries.assign(mangaId: newManga.id, categoryId: cat.id)
        }

        // 4. Transfer chapter read-state by matching chapterNumber.
        let oldChapters = try ChapterQueries.fetchAll(mangaId: oldManga.id)
        let readOldChapters = oldChapters.filter { $0.isRead || $0.progress > 0 }
        // Index once instead of re-scanning `freshNewChapters` per old chapter, and collect the
        // writes so they go out as two batched transactions rather than up to two per matched
        // chapter — a fully-read 1000-chapter series was issuing thousands (Known Issue #143).
        var newByNumber: [Double: Chapter] = [:]
        for ch in freshNewChapters {
            // `keys.contains` rather than `newByNumber[num] == nil`: the latter needs Chapter's
            // Equatable, whose conformance is MainActor-isolated and unusable here.
            if let num = ch.chapterNumber, !newByNumber.keys.contains(num) { newByNumber[num] = ch }
        }
        var readIds: [String] = []
        var progressUpdates: [ChapterQueries.ProgressUpdate] = []
        var matched = 0
        for oldCh in readOldChapters {
            guard let oldNum = oldCh.chapterNumber, let newCh = newByNumber[oldNum] else { continue }
            if oldCh.isRead { readIds.append(newCh.id) }
            progressUpdates.append(.init(
                id: newCh.id,
                progress: oldCh.progress,
                readingSeconds: oldCh.readingSeconds,
                lastPageRead: oldCh.lastPageRead
            ))
            matched += 1
        }
        try ChapterQueries.setReadBatch(chapterIds: readIds, mangaId: newManga.id, isRead: true)
        try ChapterQueries.updateProgressBatch(progressUpdates, mangaId: newManga.id)

        // 5. Remove the old entry from the library if requested (default — matches Tachiyomi's
        // "replace" convention). Keeping it just leaves both inLibrary.
        if removeOld {
            var old = oldManga
            old.inLibrary = false
            try MangaQueries.upsert(old)
            // Match the app's other two "remove from library" paths (LibraryView.removeSelected,
            // MangaDetailView.toggleLibrary) — without this, downloaded chapter files for the old
            // source sit orphaned on disk, still enumerated by DownloadsView regardless of inLibrary.
            let dir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Downloads/\(oldManga.id)")
            try? FileManager.default.removeItem(at: dir)
        }

        return Result(
            matchedChapters: matched,
            oldReadChapters: readOldChapters.count,
            newChapterCount: freshNewChapters.count
        )
    }
}
