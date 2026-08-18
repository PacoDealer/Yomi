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
    }

    /// Runs entirely off MainActor — safe to call from Task.detached.
    nonisolated static func migrate(
        from oldManga: Manga,
        to newManga: Manga,
        bridge: JSBridge,
        removeOld: Bool
    ) throws -> Result {
        // 1. Persist the new manga as a library entry, carrying over user-owned state.
        var toSave = newManga
        toSave.inLibrary = true
        toSave.readingStatus = oldManga.readingStatus
        toSave.notes = oldManga.notes
        toSave.lastReadAt = oldManga.lastReadAt
        toSave.readingSeconds = oldManga.readingSeconds
        try MangaQueries.upsert(toSave)

        // 2. Fetch + persist chapters for the new source.
        let newChapters = bridge.getChapterList(mangaPath: newManga.path, mangaId: newManga.id)
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
        var matched = 0
        for oldCh in readOldChapters {
            guard let oldNum = oldCh.chapterNumber,
                  let newCh = freshNewChapters.first(where: { $0.chapterNumber == oldNum })
            else { continue }
            if oldCh.isRead {
                try ChapterQueries.setRead(chapterId: newCh.id, mangaId: newManga.id, isRead: true)
            }
            try ChapterQueries.updateProgress(
                id: newCh.id,
                progress: oldCh.progress,
                readingSeconds: oldCh.readingSeconds,
                lastPageRead: oldCh.lastPageRead
            )
            matched += 1
        }

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

        return Result(matchedChapters: matched, oldReadChapters: readOldChapters.count)
    }
}
