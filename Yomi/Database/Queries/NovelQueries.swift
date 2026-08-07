import Foundation
import GRDB

/// CRUD operations for the novel and novel_chapter tables
enum NovelQueries {

    // MARK: - Novel: Read

    /// Returns all novels stored in the database
    nonisolated static func fetchAll() throws -> [Novel] {
        try appDatabase.read { db in
            try Novel.fetchAll(db)
        }
    }

    /// Returns only novels the user has added to their library
    nonisolated static func fetchLibrary() throws -> [Novel] {
        try appDatabase.read { db in
            try Novel
                .filter(Column("inLibrary") == true)
                .fetchAll(db)
        }
    }

    /// Returns the novel with the given id, or nil if not found
    nonisolated static func fetchOne(id: String) throws -> Novel? {
        try appDatabase.read { db in
            try Novel.fetchOne(db, key: id)
        }
    }

    /// Returns novels with lastReadAt != nil, ordered by read date descending
    nonisolated static func fetchHistory() throws -> [Novel] {
        try appDatabase.read { db in
            try Novel
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .fetchAll(db)
        }
    }

    /// Returns recently read novels, ordered by read date descending, up to limit
    nonisolated static func fetchRecentlyRead(limit: Int = 10) throws -> [Novel] {
        try appDatabase.read { db in
            try Novel
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Novel: Write

    /// Inserts a new novel; throws if a row with the same id already exists
    nonisolated static func insert(_ novel: Novel) throws {
        _ = try appDatabase.write { db in
            try novel.insert(db)
        }
    }

    /// Updates all fields of an existing novel by id
    nonisolated static func update(_ novel: Novel) throws {
        _ = try appDatabase.write { db in
            try novel.update(db)
        }
        markCloudDirty(.novel, key: novel.id)
    }

    /// Inserts or updates a novel (uses id as key)
    nonisolated static func upsert(_ novel: Novel) throws {
        _ = try appDatabase.write { db in
            try novel.save(db)
        }
        markCloudDirty(.novel, key: novel.id)
    }

    // MARK: - Novel: Delete

    /// Deletes the novel with the given id (no-op if not found)
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Novel.deleteOne(db, key: id)
        }
    }

    /// Sets lastReadAt to now for the given novel
    nonisolated static func touchLastRead(novelId: String) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("lastReadAt").set(to: Date())])
        }
        markCloudDirty(.novel, key: novelId)
    }

    /// Clears lastReadAt for a novel (swipe-to-delete in History)
    nonisolated static func clearLastRead(novelId: String) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("lastReadAt").set(to: nil)])
        }
    }

    /// Sets lastUpdatedAt to now for the given novel
    nonisolated static func touchLastUpdated(novelId: String) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("lastUpdatedAt").set(to: Date())])
        }
    }

    /// Saves the user's personal notes for a novel
    nonisolated static func updateNotes(novelId: String, notes: String) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("notes").set(to: notes.isEmpty ? nil : notes)])
        }
        markCloudDirty(.novel, key: novelId)
    }

    /// Updates the user-defined reading status for a novel
    nonisolated static func updateReadingStatus(novelId: String, status: ReadingStatus) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("readingStatus").set(to: status.rawValue)])
        }
        markCloudDirty(.novel, key: novelId)
    }

    // MARK: - NovelChapter: Read

    /// Returns all chapters for a novel ordered by chapter number ascending
    nonisolated static func fetchChapters(novelId: String) throws -> [NovelChapter] {
        try appDatabase.read { db in
            try NovelChapter
                .filter(Column("novelId") == novelId)
                .order(Column("chapterNumber").asc)
                .fetchAll(db)
        }
    }

    /// Returns unread chapter counts grouped by novelId
    nonisolated static func fetchUnreadCountsByNovel() throws -> [String: Int] {
        try appDatabase.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT novelId, COUNT(*) as cnt
                FROM novel_chapter
                WHERE isRead = 0
                GROUP BY novelId
            """)
            return Dictionary(uniqueKeysWithValues: rows.map {
                ($0["novelId"] as String, $0["cnt"] as Int)
            })
        }
    }

    // MARK: - NovelChapter: Write

    /// Bulk-inserts chapters using INSERT OR IGNORE — never overwrites existing isRead or readingSeconds
    nonisolated static func insertAllIgnoringConflicts(_ chapters: [NovelChapter]) throws {
        _ = try appDatabase.write { db in
            for ch in chapters {
                try ch.insert(db, onConflict: .ignore)
            }
        }
    }

    /// Inserts or updates a chapter (uses id as key)
    nonisolated static func upsertChapter(_ chapter: NovelChapter) throws {
        _ = try appDatabase.write { db in
            try chapter.save(db)
        }
    }

    /// Accumulates reading seconds on a chapter and updates lastReadAt + readingSeconds on the novel.
    /// Single atomic write — no read-modify-write race.
    nonisolated static func addReadingTime(chapterId: String, novelId: String, seconds: Int) throws {
        _ = try appDatabase.write { db in
            try NovelChapter
                .filter(Column("id") == chapterId)
                .updateAll(db, [Column("readingSeconds").set(to: Column("readingSeconds") + seconds)])
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [
                    Column("readingSeconds").set(to: Column("readingSeconds") + seconds),
                    Column("lastReadAt").set(to: Date())
                ])
        }
        markCloudDirty(.novelChapterState, key: "\(novelId)|\(chapterId)")
        markCloudDirty(.novel, key: novelId)
    }

    /// Marks a chapter as read: isRead=true, readAt=now
    nonisolated static func markRead(chapterId: String, novelId: String) throws {
        _ = try appDatabase.write { db in
            try NovelChapter
                .filter(Column("id") == chapterId)
                .updateAll(db, [
                    Column("isRead").set(to: true),
                    Column("readAt").set(to: Date())
                ])
        }
        markCloudDirty(.novelChapterState, key: "\(novelId)|\(chapterId)")
        try? touchLastRead(novelId: novelId)
    }

    /// Marks a chapter as unread: isRead=false, readAt=nil
    nonisolated static func markUnread(chapterId: String) throws {
        var novelId: String?
        _ = try appDatabase.write { db in
            try NovelChapter
                .filter(Column("id") == chapterId)
                .updateAll(db, [
                    Column("isRead").set(to: false),
                    Column("readAt").set(to: DatabaseValue.null)
                ])
            novelId = try String.fetchOne(db, sql: "SELECT novelId FROM novel_chapter WHERE id = ?", arguments: [chapterId])
        }
        if let novelId {
            markCloudDirty(.novelChapterState, key: "\(novelId)|\(chapterId)")
        }
    }

    nonisolated static func updateScrollPercent(chapterId: String, percent: Double) throws {
        var novelId: String?
        _ = try appDatabase.write { db in
            try NovelChapter
                .filter(Column("id") == chapterId)
                .updateAll(db, [Column("lastScrollPercent").set(to: percent)])
            novelId = try String.fetchOne(db, sql: "SELECT novelId FROM novel_chapter WHERE id = ?", arguments: [chapterId])
        }
        if let novelId {
            markCloudDirty(.novelChapterState, key: "\(novelId)|\(chapterId)")
        }
    }

    /// Marks all chapters of a novel as read or unread in a single write
    nonisolated static func markAllChapters(novelId: String, read: Bool) throws {
        let chapterIds: [String]? = try? appDatabase.write { db in
            try db.execute(
                sql: "UPDATE novel_chapter SET isRead = ?, readAt = ? WHERE novelId = ?",
                arguments: [read, read ? Date() : nil, novelId]
            )
            return try String.fetchAll(db, sql: "SELECT id FROM novel_chapter WHERE novelId = ?", arguments: [novelId])
        }
        for chapterId in chapterIds ?? [] {
            markCloudDirty(.novelChapterState, key: "\(novelId)|\(chapterId)")
        }
        if read {
            try? touchLastRead(novelId: novelId)
        }
    }
}
