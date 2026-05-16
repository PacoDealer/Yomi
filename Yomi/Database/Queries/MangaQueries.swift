import Foundation
import GRDB

/// CRUD operations for the manga table
enum MangaQueries {

    // MARK: - Read

    /// Returns all manga stored in the database
    nonisolated static func fetchAll() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga.fetchAll(db)
        }
    }

    /// Returns the manga with the given id, or nil if not found
    nonisolated static func fetchOne(id: String) throws -> Manga? {
        try appDatabase.read { db in
            try Manga.fetchOne(db, key: id)
        }
    }

    /// Returns only manga the user has added to their library
    nonisolated static func fetchLibrary() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("inLibrary") == true)
                .fetchAll(db)
        }
    }

    /// Returns manga with lastReadAt != nil, ordered by read date descending
    nonisolated static func fetchHistory() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .fetchAll(db)
        }
    }

    /// Returns recently read manga, ordered by read date descending, up to limit
    nonisolated static func fetchRecentlyRead(limit: Int = 50) throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Returns library manga ordered by lastUpdatedAt DESC, excluding rows with nil lastUpdatedAt
    nonisolated static func fetchLibraryByLastUpdated() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("inLibrary") == true)
                .filter(Column("lastUpdatedAt") != nil)
                .order(Column("lastUpdatedAt").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Write

    /// Toggles inLibrary, sets lastUpdatedAt to now, saves, and returns the updated manga
    @discardableResult
    nonisolated static func toggleLibrary(manga: Manga) throws -> Manga {
        var updated = manga
        updated.inLibrary = !manga.inLibrary
        updated.lastUpdatedAt = Date()
        _ = try appDatabase.write { db in
            try updated.save(db)
        }
        return updated
    }

    /// Inserts a new manga; throws if a row with the same id already exists
    nonisolated static func insert(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.insert(db)
        }
    }

    /// Updates all fields of an existing manga by id
    nonisolated static func update(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.update(db)
        }
    }

    /// Inserts or updates a manga (save = INSERT OR REPLACE)
    nonisolated static func upsert(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.save(db)
        }
    }

    /// Sets lastReadAt to now for the given manga
    nonisolated static func touchLastRead(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("lastReadAt").set(to: Date())])
        }
    }

    /// Clears lastReadAt for the given manga (removes it from history)
    nonisolated static func clearLastRead(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE manga SET lastReadAt = NULL WHERE id = ?",
                arguments: [mangaId]
            )
        }
    }

    /// Sets lastUpdatedAt to now for the given manga
    nonisolated static func touchLastUpdated(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("lastUpdatedAt").set(to: Date())])
        }
    }

    /// Updates the user-defined reading status for a manga
    nonisolated static func updateReadingStatus(mangaId: String, status: ReadingStatus) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("readingStatus").set(to: status.rawValue)])
        }
    }

    /// Saves the user's personal notes for a manga
    nonisolated static func updateNotes(mangaId: String, notes: String?) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("notes").set(to: notes)])
        }
    }

    // MARK: - Delete

    /// Deletes the manga with the given id (no-op if not found)
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Manga.deleteOne(db, key: id)
        }
    }
}
