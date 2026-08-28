import Foundation
import GRDB

// MARK: - appDatabase

/// Module-level DatabaseQueue accessible from any isolation context.
/// Assigned once in DatabaseManager.setup() before any query runs.
/// GRDB DatabaseQueue is internally thread-safe.
nonisolated(unsafe) var appDatabase: DatabaseQueue!

// MARK: - DatabaseManager

/// Manages the SQLite database connection and migrations.
final class DatabaseManager {

    // MARK: - Singleton

    static let shared = DatabaseManager()
    private init() {}

    // MARK: - Setup

    /// Opens (or creates) yomi.db in the user's Documents directory and runs migrations.
    func setup() throws {
        let fileURL = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("yomi.db")

        appDatabase = try DatabaseQueue(path: fileURL.path)
        try migrate(appDatabase)
    }

    // MARK: - Migrations

    private func migrate(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        // v1 — initial tables
        migrator.registerMigration("v1_initial") { db in

            try db.create(table: "manga", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("path",          .text).notNull()
                t.column("sourceId",      .text).notNull()
                t.column("title",         .text).notNull()
                t.column("coverURL",      .text)
                t.column("summary",       .text)
                t.column("author",        .text)
                t.column("artist",        .text)
                t.column("status",        .text).notNull().defaults(to: "unknown")
                t.column("genres",        .text).notNull().defaults(to: "[]")
                t.column("inLibrary",     .boolean).notNull().defaults(to: false)
                t.column("isLocal",       .boolean).notNull().defaults(to: false)
                t.column("lastReadAt",    .datetime)
                t.column("lastUpdatedAt", .datetime)
            }

            try db.create(table: "chapter", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("mangaId",       .text).notNull().references("manga", onDelete: .cascade)
                t.column("path",          .text).notNull()
                t.column("name",          .text).notNull()
                t.column("chapterNumber", .double)
                t.column("isRead",        .boolean).notNull().defaults(to: false)
                t.column("isDownloaded",  .boolean).notNull().defaults(to: false)
                t.column("readAt",        .datetime)
                t.column("progress",      .double).notNull().defaults(to: 0.0)
            }

            try db.create(table: "category", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sort", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "source", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name",        .text).notNull()
                t.column("language",    .text).notNull()
                t.column("version",     .text).notNull()
                t.column("iconURL",     .text)
                t.column("baseURL",     .text).notNull()
                t.column("isInstalled", .boolean).notNull().defaults(to: false)
                t.column("isNSFW",      .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v2_extensions") { db in
            try db.create(table: "extension", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name",          .text).notNull()
                t.column("version",       .text).notNull()
                t.column("language",      .text).notNull()
                t.column("iconURL",       .text)
                t.column("sourceListURL", .text).notNull()
                t.column("isInstalled",   .boolean).notNull().defaults(to: false)
                t.column("isNSFW",        .boolean).notNull().defaults(to: false)
                t.column("sourceIds",     .text).notNull().defaults(to: "[]")
            }
        }

        migrator.registerMigration("v3_novels") { db in

            try db.create(table: "novel", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("path",          .text).notNull()
                t.column("sourceId",      .text).notNull()
                t.column("title",         .text).notNull()
                t.column("coverURL",      .text)
                t.column("summary",       .text)
                t.column("author",        .text)
                t.column("status",        .text).notNull().defaults(to: "unknown")
                t.column("genres",        .text).notNull().defaults(to: "[]")
                t.column("inLibrary",     .boolean).notNull().defaults(to: false)
                t.column("lastReadAt",    .datetime)
                t.column("lastUpdatedAt", .datetime)
            }

            try db.create(table: "novel_chapter", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("novelId",       .text).notNull().references("novel", onDelete: .cascade)
                t.column("path",          .text).notNull()
                t.column("name",          .text).notNull()
                t.column("chapterNumber", .double)
                t.column("isRead",        .boolean).notNull().defaults(to: false)
                t.column("readAt",        .datetime)
                t.column("releaseTime",   .text)
            }
        }

        migrator.registerMigration("v4_reading_insights") { db in
            try db.alter(table: "manga") { t in
                t.add(column: "readingSeconds", .integer).notNull().defaults(to: 0)
            }
            try db.alter(table: "novel") { t in
                t.add(column: "readingSeconds", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v4_reading_time") { db in
            try db.alter(table: "chapter") { t in
                t.add(column: "readingSeconds", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v5_categories") { db in
            // Join table: manga ↔ category (many-to-many)
            try db.create(table: "manga_category", ifNotExists: true) { t in
                t.column("mangaId",    .text).notNull().references("manga",    onDelete: .cascade)
                t.column("categoryId", .text).notNull().references("category", onDelete: .cascade)
                t.primaryKey(["mangaId", "categoryId"])
            }
            // category.sort already exists from v1_initial — no ALTER needed
        }

        migrator.registerMigration("v6_downloads") { db in
            try db.alter(table: "chapter") { t in
                t.add(column: "downloadedAt", .text)
            }
        }

        migrator.registerMigration("v7_reading_status") { db in
            try db.alter(table: "manga") { t in
                t.add(column: "readingStatus", .text).notNull().defaults(to: "none")
            }
        }

        migrator.registerMigration("v8_last_page") { db in
            try db.alter(table: "chapter") { t in
                t.add(column: "lastPageRead", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v9_novel_chapter_reading_time") { db in
            try db.alter(table: "novel_chapter") { t in
                t.add(column: "readingSeconds", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v10_novel_category") { db in
            try db.create(table: "novel_category", ifNotExists: true) { t in
                t.column("novelId", .text).notNull()
                    .references("novel", onDelete: .cascade)
                t.column("categoryId", .text).notNull()
                    .references("category", onDelete: .cascade)
                t.primaryKey(["novelId", "categoryId"])
            }
        }

        migrator.registerMigration("v11_novel_reading_status") { db in
            try db.alter(table: "novel") { t in
                t.add(column: "readingStatus", .text).notNull().defaults(to: "none")
            }
        }

        migrator.registerMigration("v12_scanlator") { db in
            try db.alter(table: "chapter") { t in
                t.add(column: "scanlator", .text)
            }
        }

        migrator.registerMigration("v13_custom_cover") { db in
            try db.alter(table: "manga") { t in
                t.add(column: "customCoverPath", .text)
            }
        }

        migrator.registerMigration("v14_manga_notes") { db in
            try db.alter(table: "manga") { t in
                t.add(column: "notes", .text)
            }
        }

        migrator.registerMigration("v15_novel_notes") { db in
            try db.alter(table: "novel") { t in
                t.add(column: "notes", .text)
            }
        }

        migrator.registerMigration("v16_novel_custom_cover") { db in
            try db.alter(table: "novel") { t in
                t.add(column: "customCoverPath", .text)
            }
        }

        migrator.registerMigration("v17_novel_scroll") { db in
            try db.alter(table: "novel_chapter") { t in
                t.add(column: "lastScrollPercent", .double)
            }
        }

        migrator.registerMigration("v18_indexes") { db in
            try db.create(index: "idx_chapter_mangaid",
                          on: "chapter", columns: ["mangaId"], ifNotExists: true)
            try db.create(index: "idx_chapter_unread",
                          on: "chapter", columns: ["mangaId", "isRead"], ifNotExists: true)
            try db.create(index: "idx_novel_chapter_novelid",
                          on: "novel_chapter", columns: ["novelId"], ifNotExists: true)
        }

        migrator.registerMigration("v19_source_indexes") { db in
            try db.create(index: "idx_manga_sourceid",
                          on: "manga", columns: ["sourceId"], ifNotExists: true)
            try db.create(index: "idx_novel_sourceid",
                          on: "novel", columns: ["sourceId"], ifNotExists: true)
        }

        // CloudKit sync (S102): recordName -> (recordType, localKey) reverse index.
        // CKSyncEngine's pending-change queue only carries CKRecord.IDs (recordName is a SHA256 hash
        // of the local key, to stay within CloudKit's recordName limits regardless of source-URL
        // length) — this table is what lets CloudSyncManager turn a bare recordID back into "which
        // GRDB row do I re-fetch to build this record" when the engine asks for a send batch.
        migrator.registerMigration("v20_cloud_sync_map") { db in
            try db.create(table: "cloud_sync_map", ifNotExists: true) { t in
                t.column("recordName", .text).primaryKey()
                t.column("recordType", .text).notNull()
                t.column("key", .text).notNull()
                // Archived CKRecord (NSSecureCoding via CKRecord's own coder) from the last time we
                // saved or fetched this record — reused as the base for the next save so it carries
                // the real server recordChangeTag. Without this, every save would be a "fresh" record
                // with no change tag, defeating CloudKit's conflict detection entirely.
                t.column("recordData", .blob)
            }
        }

        // CloudKit sync fixes (S105, code-review findings #41/#43):
        // - `pendingChange` on cloud_sync_map durably records a dirty/delete mark made while no
        //   CKSyncEngine is running yet (the async window during CloudSyncManager.enable()'s
        //   accountStatus check) — drained into the engine's own persisted state right after the
        //   engine is created, instead of being silently dropped.
        // - `pending_chapter_state`/`pending_novel_chapter_state` hold a remote chapter-state change
        //   that arrived before the chapter row itself was ever locally cached (its detail page was
        //   never opened on this device). A real upsert isn't possible here — the sync payload only
        //   carries read-state fields, not the full chapter row (title/url/chapterNumber/etc. only
        //   exist plugin-side) — so the change is stashed and replayed once the chapter actually gets
        //   inserted locally (ChapterQueries.insertAllIgnoringConflicts/insertMangaAndChapters,
        //   NovelQueries.insertAllIgnoringConflicts).
        migrator.registerMigration("v21_cloud_sync_pending") { db in
            try db.alter(table: "cloud_sync_map") { t in
                t.add(column: "pendingChange", .text)
            }
            try db.create(table: "pending_chapter_state", ifNotExists: true) { t in
                t.column("mangaId", .text).notNull()
                t.column("chapterId", .text).notNull()
                t.column("isRead", .boolean).notNull()
                t.column("progress", .double).notNull()
                t.column("lastPageRead", .integer).notNull()
                t.column("readAt", .datetime)
                t.column("readingSeconds", .integer).notNull()
                t.primaryKey(["mangaId", "chapterId"])
            }
            try db.create(table: "pending_novel_chapter_state", ifNotExists: true) { t in
                t.column("novelId", .text).notNull()
                t.column("chapterId", .text).notNull()
                t.column("isRead", .boolean).notNull()
                t.column("readAt", .datetime)
                t.column("readingSeconds", .integer).notNull()
                t.column("lastScrollPercent", .double)
                t.primaryKey(["novelId", "chapterId"])
            }
        }

        // `NovelQueries.fetchUnreadCountsByNovel()` runs `WHERE isRead = 0 GROUP BY novelId` on
        // every Library load; `chapter` had `idx_chapter_unread` for the identical query since
        // v18, `novel_chapter` never got its counterpart (Known Issue #144).
        migrator.registerMigration("v22_novel_chapter_unread_index") { db in
            try db.create(index: "idx_novel_chapter_unread",
                          on: "novel_chapter", columns: ["novelId", "isRead"], ifNotExists: true)
        }

        try migrator.migrate(db)
    }

    // MARK: - Repair

    /// User-facing "Repair Database" action (Tachimanga parity — Storage screen). Runs SQLite's
    /// own integrity check, then VACUUMs to reclaim space and defragment. `integrity_check`
    /// returns a single row "ok" when clean, or one row per problem found — surfaced verbatim to
    /// the user rather than summarized, since a real corruption report needs the raw detail.
    nonisolated func repair() throws -> String {
        let issues: [String] = try appDatabase.read { db in
            try String.fetchAll(db, sql: "PRAGMA integrity_check")
        }
        // VACUUM must run outside a transaction — appDatabase.write wraps its closure in one,
        // which SQLite rejects VACUUM inside of.
        try appDatabase.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
        if issues == ["ok"] {
            return "No issues found. Database optimized."
        }
        return "Issues found and left as-is (repair doesn't rewrite data):\n" + issues.joined(separator: "\n")
    }
}

// MARK: - GRDB: Manga

extension Manga: FetchableRecord, PersistableRecord {
    static let databaseTableName = "manga"

    nonisolated init(row: Row) throws {
        id            = row["id"]
        path          = row["path"]
        sourceId      = row["sourceId"]
        title         = row["title"]
        coverURL      = (row["coverURL"] as String?).flatMap { URL(string: $0) }
        summary       = row["summary"]
        author        = row["author"]
        artist        = row["artist"]
        status        = MangaStatus(rawValue: row["status"]) ?? .unknown
        let raw: String = row["genres"] ?? "[]"
        genres        = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        inLibrary      = row["inLibrary"]
        isLocal        = row["isLocal"]
        lastReadAt     = row["lastReadAt"]
        lastUpdatedAt  = row["lastUpdatedAt"]
        readingSeconds  = row["readingSeconds"] ?? 0
        readingStatus   = ReadingStatus(rawValue: row["readingStatus"] ?? "none") ?? .none
        customCoverPath = row["customCoverPath"]
        notes           = row["notes"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]              = id
        container["path"]            = path
        container["sourceId"]        = sourceId
        container["title"]           = title
        container["coverURL"]        = coverURL?.absoluteString
        container["summary"]         = summary
        container["author"]          = author
        container["artist"]          = artist
        container["status"]          = status.rawValue
        container["genres"]          = (try? JSONEncoder().encode(genres))
                                           .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        container["inLibrary"]       = inLibrary
        container["isLocal"]         = isLocal
        container["lastReadAt"]      = lastReadAt
        container["lastUpdatedAt"]   = lastUpdatedAt
        container["readingSeconds"]  = readingSeconds
        container["readingStatus"]   = readingStatus.rawValue
        container["customCoverPath"] = customCoverPath
        container["notes"]           = notes
    }
}

// MARK: - GRDB: Chapter

extension Chapter: FetchableRecord, PersistableRecord {
    static let databaseTableName = "chapter"

    nonisolated init(row: Row) throws {
        id            = row["id"]
        mangaId       = row["mangaId"]
        path          = row["path"]
        name          = row["name"]
        chapterNumber = row["chapterNumber"]
        isRead          = row["isRead"]
        isDownloaded    = row["isDownloaded"]
        downloadedAt    = row["downloadedAt"]
        readAt          = row["readAt"]
        progress        = row["progress"]
        readingSeconds  = row["readingSeconds"] ?? 0
        lastPageRead    = row["lastPageRead"] ?? 0
        scanlator       = row["scanlator"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]             = id
        container["mangaId"]        = mangaId
        container["path"]           = path
        container["name"]           = name
        container["chapterNumber"]  = chapterNumber
        container["isRead"]         = isRead
        container["isDownloaded"]   = isDownloaded
        container["downloadedAt"]   = downloadedAt
        container["readAt"]         = readAt
        container["progress"]       = progress
        container["readingSeconds"] = readingSeconds
        container["lastPageRead"]   = lastPageRead
        container["scanlator"]      = scanlator
    }
}

// MARK: - GRDB: Category

extension Category: FetchableRecord, PersistableRecord {
    static let databaseTableName = "category"

    nonisolated init(row: Row) throws {
        id   = row["id"]
        name = row["name"]
        sort = row["sort"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]   = id
        container["name"] = name
        container["sort"] = sort
    }
}

// MARK: - GRDB: Extension

extension Extension: FetchableRecord, PersistableRecord {
    static let databaseTableName = "extension"

    nonisolated init(row: Row) throws {
        id            = row["id"]
        name          = row["name"]
        version       = row["version"]
        language      = row["language"]
        iconURL       = (row["iconURL"] as String?).flatMap { URL(string: $0) }
        guard let rawURL: String = row["sourceListURL"], let parsed = URL(string: rawURL) else {
            throw DatabaseError(message: "Extension row has invalid sourceListURL")
        }
        sourceListURL = parsed
        isInstalled   = row["isInstalled"]
        isNSFW        = row["isNSFW"]
        let raw: String = row["sourceIds"] ?? "[]"
        sourceIds     = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]            = id
        container["name"]          = name
        container["version"]       = version
        container["language"]      = language
        container["iconURL"]       = iconURL?.absoluteString
        container["sourceListURL"] = sourceListURL.absoluteString
        container["isInstalled"]   = isInstalled
        container["isNSFW"]        = isNSFW
        container["sourceIds"]     = (try? JSONEncoder().encode(sourceIds))
                                         .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

// MARK: - GRDB: Novel

extension Novel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "novel"

    nonisolated init(row: Row) throws {
        id            = row["id"]
        path          = row["path"]
        sourceId      = row["sourceId"]
        title         = row["title"]
        coverURL      = (row["coverURL"] as String?).flatMap { URL(string: $0) }
        summary       = row["summary"]
        author        = row["author"]
        status        = row["status"] ?? "unknown"
        let raw: String = row["genres"] ?? "[]"
        genres        = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        inLibrary      = row["inLibrary"]
        lastReadAt     = row["lastReadAt"]
        lastUpdatedAt  = row["lastUpdatedAt"]
        readingSeconds = row["readingSeconds"] ?? 0
        readingStatus  = ReadingStatus(rawValue: row["readingStatus"] ?? "none") ?? .none
        notes          = row["notes"]
        customCoverPath = row["customCoverPath"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]              = id
        container["path"]            = path
        container["sourceId"]        = sourceId
        container["title"]           = title
        container["coverURL"]        = coverURL?.absoluteString
        container["summary"]         = summary
        container["author"]          = author
        container["status"]          = status
        container["genres"]          = (try? JSONEncoder().encode(genres))
                                           .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        container["inLibrary"]       = inLibrary
        container["lastReadAt"]      = lastReadAt
        container["lastUpdatedAt"]   = lastUpdatedAt
        container["readingSeconds"]  = readingSeconds
        container["readingStatus"]   = readingStatus.rawValue
        container["notes"]           = notes
        container["customCoverPath"] = customCoverPath
    }
}

// MARK: - GRDB: NovelChapter

extension NovelChapter: FetchableRecord, PersistableRecord {
    static let databaseTableName = "novel_chapter"

    nonisolated init(row: Row) throws {
        id                = row["id"]
        novelId           = row["novelId"]
        path              = row["path"]
        name              = row["name"]
        chapterNumber     = row["chapterNumber"]
        isRead            = row["isRead"]
        readAt            = row["readAt"]
        releaseTime       = row["releaseTime"]
        readingSeconds    = row["readingSeconds"] ?? 0
        lastScrollPercent = row["lastScrollPercent"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]                = id
        container["novelId"]           = novelId
        container["path"]              = path
        container["name"]              = name
        container["chapterNumber"]     = chapterNumber
        container["isRead"]            = isRead
        container["readAt"]            = readAt
        container["releaseTime"]       = releaseTime
        container["readingSeconds"]    = readingSeconds
        container["lastScrollPercent"] = lastScrollPercent
    }
}
