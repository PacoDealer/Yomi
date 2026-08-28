import Foundation
import GRDB

/// CRUD operations for the chapter table.
enum ChapterQueries {

    // MARK: - Read

    /// Returns all chapters for a manga ordered by chapterNumber ASC, nulls last.
    nonisolated static func fetchAll(mangaId: String) throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .order(Column("chapterNumber").ascNullsLast)
                .fetchAll(db)
        }
    }

    /// Returns the chapter with the given id, or nil if not found.
    nonisolated static func fetchOne(id: String) throws -> Chapter? {
        try appDatabase.read { db in
            try Chapter.fetchOne(db, key: id)
        }
    }

    /// Returns the number of downloaded chapters for a manga.
    nonisolated static func downloadedCount(mangaId: String) throws -> Int {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .filter(Column("isDownloaded") == true)
                .fetchCount(db)
        }
    }

    /// Returns a [mangaId: unreadCount] dictionary for all library manga in a single SQL query.
    nonisolated static func fetchUnreadCountsByManga() throws -> [String: Int] {
        try appDatabase.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT mangaId, COUNT(*) as cnt FROM chapter WHERE isRead = 0 GROUP BY mangaId"
            )
            return Dictionary(uniqueKeysWithValues: rows.map { (($0["mangaId"] as String), ($0["cnt"] as Int)) })
        }
    }

    /// Most recently read-or-started chapter name per manga, in ONE query.
    ///
    /// Backs the Home Screen widget's per-title subtitle, which was a hardcoded "Continue reading"
    /// literal for every entry (Known Issue #129). Bulk rather than per-title on purpose — the
    /// widget writes on every library load, and an N+1 here is the same shape as #140.
    nonisolated static func fetchLastTouchedChapterNames(mangaIds: [String]) throws -> [String: String] {
        guard !mangaIds.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: mangaIds.count).joined(separator: ",")
        return try appDatabase.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT mangaId, name FROM (
                    SELECT mangaId, name, ROW_NUMBER() OVER (
                        PARTITION BY mangaId
                        ORDER BY readAt DESC NULLS LAST, chapterNumber DESC
                    ) AS rn
                    FROM chapter
                    WHERE mangaId IN (\(placeholders)) AND (isRead = 1 OR progress > 0)
                ) WHERE rn = 1
                """, arguments: StatementArguments(mangaIds))
            return Dictionary(uniqueKeysWithValues: rows.map { (($0["mangaId"] as String), ($0["name"] as String)) })
        }
    }

    /// All chapters for many manga in ONE query, grouped by mangaId — the bulk form of
    /// `fetchAll(mangaId:)` for callers that would otherwise loop it (Known Issue #140).
    nonisolated static func fetchAllGrouped(mangaIds: [String]) throws -> [String: [Chapter]] {
        guard !mangaIds.isEmpty else { return [:] }
        let chapters: [Chapter] = try appDatabase.read { db in
            try Chapter
                .filter(mangaIds.contains(Column("mangaId")))
                .order(Column("chapterNumber").ascNullsLast)
                .fetchAll(db)
        }
        return Dictionary(grouping: chapters, by: { $0.mangaId })
    }

    /// Returns unread chapters for a manga ordered by chapterNumber ASC, nulls last.
    nonisolated static func fetchUnread(mangaId: String) throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .filter(Column("isRead") == false)
                .order(Column("chapterNumber").ascNullsLast)
                .fetchAll(db)
        }
    }

    // MARK: - Write

    /// Inserts or updates a chapter (save = INSERT OR REPLACE).
    nonisolated static func upsert(_ chapter: Chapter) throws {
        _ = try appDatabase.write { db in
            try chapter.save(db)
        }
        markCloudDirty(.mangaChapterState, key: "\(chapter.mangaId)|\(chapter.id)")
    }

    /// Inserts new chapters ignoring conflicts (INSERT OR IGNORE).
    /// Never overwrites existing isRead, isDownloaded, or progress values.
    /// Call after fetching the chapter list from JSBridge, before merging with DB state.
    nonisolated static func insertAllIgnoringConflicts(_ chapters: [Chapter]) throws {
        _ = try appDatabase.write { db in
            for chapter in chapters {
                try chapter.insert(db, onConflict: .ignore)
            }
            // Replays any CloudKit chapter-state change that arrived before these chapters existed
            // locally — see CloudSyncManager's code-review finding #41.
            try CloudSyncManager.applyPendingChapterStates(chapters, db: db)
        }
    }

    /// Inserts a manga and its chapters in a single transaction (INSERT OR IGNORE).
    /// The manga INSERT OR IGNORE ensures the FK constraint is satisfied even when
    /// the manga is not yet in the library (browsing without adding to library).
    nonisolated static func insertMangaAndChapters(manga: Manga, chapters: [Chapter]) throws {
        _ = try appDatabase.write { db in
            try manga.insert(db, onConflict: .ignore)
            for chapter in chapters {
                try chapter.insert(db, onConflict: .ignore)
            }
            try CloudSyncManager.applyPendingChapterStates(chapters, db: db)
        }
    }

    // MARK: - Progress

    /// Marks a chapter as read with isRead=true and readAt=now (direct UPDATE, no prior fetch).
    nonisolated static func markRead(id: String, mangaId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
        markCloudDirty(.mangaChapterState, key: "\(mangaId)|\(id)")
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Marks a chapter as read or unread.
    nonisolated static func setRead(chapterId: String, mangaId: String, isRead: Bool) throws {
        _ = try appDatabase.write { db in
            if isRead {
                try db.execute(
                    sql: "UPDATE chapter SET isRead = 1, readAt = ? WHERE id = ?",
                    arguments: [Date(), chapterId]
                )
            } else {
                try db.execute(
                    sql: "UPDATE chapter SET isRead = 0, readAt = NULL WHERE id = ?",
                    arguments: [chapterId]
                )
            }
        }
        markCloudDirty(.mangaChapterState, key: "\(mangaId)|\(chapterId)")
        if isRead {
            try? MangaQueries.touchLastRead(mangaId: mangaId)
        }
    }

    /// Marks a specific set of chapters read/unread in ONE transaction.
    ///
    /// The per-chapter `setRead` costs 4 write transactions each (UPDATE + dirty-mark +
    /// touchLastRead + its own dirty-mark); callers with a whole list — Updates' "mark all read",
    /// a source migration — were paying that per chapter (Known Issues #141/#143).
    nonisolated static func setReadBatch(chapterIds: [String], mangaId: String, isRead: Bool) throws {
        guard !chapterIds.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: chapterIds.count).joined(separator: ",")
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = ?, readAt = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([isRead, isRead ? Date() : nil] as [DatabaseValueConvertible?])
                    + StatementArguments(chapterIds)
            )
        }
        markCloudDirtyBatch(.mangaChapterState, keys: chapterIds.map { "\(mangaId)|\($0)" })
        if isRead { try? MangaQueries.touchLastRead(mangaId: mangaId) }
    }

    /// One chapter's resume/progress state, for `updateProgressBatch`.
    struct ProgressUpdate: Sendable {
        let id: String
        let progress: Double
        let readingSeconds: Int
        let lastPageRead: Int
    }

    /// Applies many chapters' progress in ONE transaction (see `setReadBatch` for why).
    nonisolated static func updateProgressBatch(_ updates: [ProgressUpdate], mangaId: String) throws {
        guard !updates.isEmpty else { return }
        _ = try appDatabase.write { db in
            for u in updates {
                try db.execute(
                    sql: "UPDATE chapter SET progress = ?, readingSeconds = ?, lastPageRead = ? WHERE id = ?",
                    arguments: [u.progress, u.readingSeconds, u.lastPageRead, u.id]
                )
            }
        }
        markCloudDirtyBatch(.mangaChapterState, keys: updates.map { "\(mangaId)|\($0.id)" })
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Marks all chapters for a manga as read with isRead=true and readAt=now.
    nonisolated static func markAllRead(mangaId: String) throws {
        let chapterIds: [String] = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ? WHERE mangaId = ?",
                arguments: [Date(), mangaId]
            )
            return try String.fetchAll(db, sql: "SELECT id FROM chapter WHERE mangaId = ?", arguments: [mangaId])
        }
        markCloudDirtyBatch(.mangaChapterState, keys: chapterIds.map { "\(mangaId)|\($0)" })
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Updates progress, readingSeconds, and lastPageRead for a chapter (direct UPDATE, no prior fetch).
    nonisolated static func updateProgress(id: String, progress: Double, readingSeconds: Int, lastPageRead: Int = 0) throws {
        var mangaId: String?
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET progress = ?, readingSeconds = ?, lastPageRead = ? WHERE id = ?",
                arguments: [progress, readingSeconds, lastPageRead, id]
            )
            mangaId = try String.fetchOne(db, sql: "SELECT mangaId FROM chapter WHERE id = ?", arguments: [id])
        }
        if let mangaId {
            markCloudDirty(.mangaChapterState, key: "\(mangaId)|\(id)")
            // This is the only write on the ordinary "closed the reader partway through" path — the
            // ≥80% markChapterRead() path never runs for it. Without this touch, a manga genuinely
            // being read but never finished keeps lastReadAt NULL and never appears in History or
            // the Continue shelf at all (Known Issue #114).
            try? MangaQueries.touchLastRead(mangaId: mangaId)
        }
    }

    /// Accumulates reading seconds into the chapter's readingSeconds total.
    nonisolated static func addReadingTime(id: String, seconds: Int) throws {
        guard seconds > 0 else { return }
        var mangaId: String?
        _ = try appDatabase.write { db in
            try Chapter
                .filter(Column("id") == id)
                .updateAll(db, Column("readingSeconds") += seconds)
            mangaId = try String.fetchOne(db, sql: "SELECT mangaId FROM chapter WHERE id = ?", arguments: [id])
        }
        if let mangaId {
            markCloudDirty(.mangaChapterState, key: "\(mangaId)|\(id)")
        }
    }

    // MARK: - Delete

    /// Deletes the chapter with the given id (no-op if not found).
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Chapter.deleteOne(db, key: id)
        }
    }

    /// Deletes all chapters for a manga.
    nonisolated static func deleteAll(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .deleteAll(db)
        }
    }
}
