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

    /// Inserts a new chapter; fails if a record with the same id already exists.
    nonisolated static func insert(_ chapter: Chapter) throws {
        _ = try appDatabase.write { db in
            try chapter.insert(db)
        }
    }

    /// Inserts or updates a chapter (save = INSERT OR REPLACE).
    nonisolated static func upsert(_ chapter: Chapter) throws {
        _ = try appDatabase.write { db in
            try chapter.save(db)
        }
    }

    /// Inserts or updates a collection of chapters in a single transaction.
    nonisolated static func upsertAll(_ chapters: [Chapter]) throws {
        _ = try appDatabase.write { db in
            for chapter in chapters {
                try chapter.save(db)
            }
        }
    }

    /// Inserts new chapters ignoring conflicts (INSERT OR IGNORE).
    /// Never overwrites existing isRead, isDownloaded, or progress values.
    /// Call after fetching the chapter list from JSBridge, before merging with DB state.
    nonisolated static func insertAllIgnoringConflicts(_ chapters: [Chapter]) throws {
        _ = try appDatabase.write { db in
            for chapter in chapters {
                try chapter.insert(db, onConflict: .ignore)
            }
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
        }
    }

    // MARK: - Progress

    /// Marks a chapter as read with isRead=true, readAt=now, progress=1.0 (direct UPDATE, no prior fetch).
    nonisolated static func markRead(id: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ?, progress = 1.0 WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    /// Marks a chapter as read with isRead=true and readAt=now (direct UPDATE, no prior fetch).
    nonisolated static func markRead(id: String, mangaId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Marks a chapter as read or unread.
    nonisolated static func setRead(chapterId: String, isRead: Bool) throws {
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
    }

    /// Marks all chapters for a manga as read with isRead=true and readAt=now.
    nonisolated static func markAllRead(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ? WHERE mangaId = ?",
                arguments: [Date(), mangaId]
            )
        }
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Updates progress, readingSeconds, and lastPageRead for a chapter (direct UPDATE, no prior fetch).
    nonisolated static func updateProgress(id: String, progress: Double, readingSeconds: Int, lastPageRead: Int = 0) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET progress = ?, readingSeconds = ?, lastPageRead = ? WHERE id = ?",
                arguments: [progress, readingSeconds, lastPageRead, id]
            )
        }
    }

    /// Accumulates reading seconds into the chapter's readingSeconds total.
    nonisolated static func addReadingTime(id: String, seconds: Int) throws {
        guard seconds > 0 else { return }
        _ = try appDatabase.write { db in
            try Chapter
                .filter(Column("id") == id)
                .updateAll(db, Column("readingSeconds") += seconds)
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
