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
        markCloudDirty(.manga, key: updated.id)
        return updated
    }

    /// Updates all fields of an existing manga by id
    nonisolated static func update(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.update(db)
        }
        markCloudDirty(.manga, key: manga.id)
    }

    /// Refreshes only what a *source* knows about a manga — title, cover, summary, author, artist, genres,
    /// status — on the saved row, inside one transaction. Never touches user state (library membership,
    /// lastReadAt, reading status, notes, custom cover, reading time). A full-row `update(_:)` of a manga opened
    /// from Browse wrote that model's defaults over all of it (S124: Keiyoushi/Suwayomi titles vanished from
    /// History). No-op if the row doesn't exist yet.
    nonisolated static func updateSourceMetadata(_ source: Manga) throws {
        let changed: Bool = try appDatabase.write { db in
            guard var row = try Manga.fetchOne(db, key: source.id) else { return false }
            row.title = source.title
            if let cover = source.coverURL { row.coverURL = cover }
            if let summary = source.summary, !summary.isEmpty { row.summary = summary }
            if let author = source.author, !author.isEmpty { row.author = author }
            if let artist = source.artist, !artist.isEmpty { row.artist = artist }
            if !source.genres.isEmpty { row.genres = source.genres }
            if source.status != .unknown { row.status = source.status }
            try row.update(db)
            return true
        }
        if changed { markCloudDirty(.manga, key: source.id) }
    }

    /// Adds reading time atomically. The reader used to fetch the row, add, and write the whole row back on a
    /// detached task racing the progress save's `touchLastRead` — whichever wrote last won, and lastReadAt could
    /// be restored to NULL (S124).
    nonisolated static func addReadingSeconds(mangaId: String, seconds: Int) throws {
        guard seconds > 0 else { return }
        _ = try appDatabase.write { db in
            try db.execute(sql: "UPDATE manga SET readingSeconds = readingSeconds + ? WHERE id = ?",
                           arguments: [seconds, mangaId])
        }
        markCloudDirty(.manga, key: mangaId)
    }

    /// Sets only the custom cover path (relative to Documents), leaving the rest of the row alone.
    nonisolated static func updateCustomCover(mangaId: String, path: String?) throws {
        _ = try appDatabase.write { db in
            try db.execute(sql: "UPDATE manga SET customCoverPath = ? WHERE id = ?", arguments: [path, mangaId])
        }
        markCloudDirty(.manga, key: mangaId)
    }

    /// Inserts or updates a manga (save = INSERT OR REPLACE)
    nonisolated static func upsert(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.save(db)
        }
        markCloudDirty(.manga, key: manga.id)
    }

    /// Sets lastReadAt to now for the given manga
    nonisolated static func touchLastRead(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("lastReadAt").set(to: Date())])
        }
        markCloudDirty(.manga, key: mangaId)
    }

    /// Clears lastReadAt for the given manga (removes it from history)
    nonisolated static func clearLastRead(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE manga SET lastReadAt = NULL WHERE id = ?",
                arguments: [mangaId]
            )
        }
        markCloudDirty(.manga, key: mangaId)
    }

    /// Sets lastUpdatedAt to now for the given manga
    nonisolated static func touchLastUpdated(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("lastUpdatedAt").set(to: Date())])
        }
        markCloudDirty(.manga, key: mangaId)
    }

    /// Updates the user-defined reading status for a manga
    nonisolated static func updateReadingStatus(mangaId: String, status: ReadingStatus) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("readingStatus").set(to: status.rawValue)])
        }
        markCloudDirty(.manga, key: mangaId)
    }

    /// Saves the user's personal notes for a manga
    nonisolated static func updateNotes(mangaId: String, notes: String?) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("notes").set(to: notes)])
        }
        markCloudDirty(.manga, key: mangaId)
    }

    // MARK: - Delete

    /// Deletes the manga with the given id (no-op if not found)
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Manga.deleteOne(db, key: id)
        }
    }
}
