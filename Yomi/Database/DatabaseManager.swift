import Foundation
import GRDB

/// Gestiona la conexión y las migraciones de la base de datos SQLite
final class DatabaseManager {

    // MARK: - Singleton

    nonisolated(unsafe) static let shared = DatabaseManager()
    private init() {}

    // MARK: - Conexión

    /// Cola de acceso a la base de datos; se inicializa en setup()
    nonisolated(unsafe) private(set) var db: DatabaseQueue!

    // MARK: - Setup

    /// Abre (o crea) yomi.db en el directorio de Documentos del usuario y ejecuta las migraciones
    func setup() throws {
        let fileURL = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("yomi.db")

        db = try DatabaseQueue(path: fileURL.path)
        try migrate()
    }

    // MARK: - Migraciones

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        // v1 — tablas iniciales
        migrator.registerMigration("v1_initial") { db in

            // Tabla manga
            try db.create(table: "manga", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("path",          .text).notNull()
                t.column("sourceId",      .text).notNull()
                t.column("title",         .text).notNull()
                // URLs almacenadas como cadena de texto
                t.column("coverURL",      .text)
                t.column("summary",       .text)
                t.column("author",        .text)
                t.column("artist",        .text)
                // Enum serializado como su rawValue
                t.column("status",        .text).notNull().defaults(to: "unknown")
                // Array de géneros serializado como JSON (ej: ["Acción","Aventura"])
                t.column("genres",        .text).notNull().defaults(to: "[]")
                t.column("inLibrary",     .boolean).notNull().defaults(to: false)
                t.column("isLocal",       .boolean).notNull().defaults(to: false)
                t.column("lastReadAt",    .datetime)
                t.column("lastUpdatedAt", .datetime)
            }

            // Tabla chapter
            try db.create(table: "chapter", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                // Clave foránea hacia manga
                t.column("mangaId",       .text).notNull().references("manga", onDelete: .cascade)
                t.column("path",          .text).notNull()
                t.column("name",          .text).notNull()
                t.column("chapterNumber", .double)
                t.column("isRead",        .boolean).notNull().defaults(to: false)
                t.column("isDownloaded",  .boolean).notNull().defaults(to: false)
                t.column("readAt",        .datetime)
                // Valor entre 0.0 y 1.0
                t.column("progress",      .double).notNull().defaults(to: 0.0)
            }

            // Tabla category
            try db.create(table: "category", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sort", .integer).notNull().defaults(to: 0)
            }

            // Tabla source
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

            // Tabla novel
            try db.create(table: "novel", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("path",          .text).notNull()
                t.column("sourceId",      .text).notNull()
                t.column("title",         .text).notNull()
                t.column("coverURL",      .text)
                t.column("summary",       .text)
                t.column("author",        .text)
                t.column("status",        .text).notNull().defaults(to: "unknown")
                // Array de géneros serializado como JSON
                t.column("genres",        .text).notNull().defaults(to: "[]")
                t.column("inLibrary",     .boolean).notNull().defaults(to: false)
                t.column("lastReadAt",    .datetime)
                t.column("lastUpdatedAt", .datetime)
            }

            // Tabla novel_chapter
            try db.create(table: "novel_chapter", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                // Clave foránea hacia novel
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

        try migrator.migrate(db)
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
        // Decodifica el JSON almacenado de vuelta a [String]
        let raw: String = row["genres"] ?? "[]"
        genres        = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        inLibrary      = row["inLibrary"]
        isLocal        = row["isLocal"]
        lastReadAt     = row["lastReadAt"]
        lastUpdatedAt  = row["lastUpdatedAt"]
        readingSeconds = row["readingSeconds"] ?? 0
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]             = id
        container["path"]           = path
        container["sourceId"]       = sourceId
        container["title"]          = title
        container["coverURL"]       = coverURL?.absoluteString
        container["summary"]        = summary
        container["author"]         = author
        container["artist"]         = artist
        container["status"]         = status.rawValue
        // Serializa [String] a JSON para guardarlo en la columna TEXT
        container["genres"]         = (try? JSONEncoder().encode(genres))
                                          .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        container["inLibrary"]      = inLibrary
        container["isLocal"]        = isLocal
        container["lastReadAt"]     = lastReadAt
        container["lastUpdatedAt"]  = lastUpdatedAt
        container["readingSeconds"] = readingSeconds
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
        isRead        = row["isRead"]
        isDownloaded  = row["isDownloaded"]
        readAt        = row["readAt"]
        progress      = row["progress"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]            = id
        container["mangaId"]       = mangaId
        container["path"]          = path
        container["name"]          = name
        container["chapterNumber"] = chapterNumber
        container["isRead"]        = isRead
        container["isDownloaded"]  = isDownloaded
        container["readAt"]        = readAt
        container["progress"]      = progress
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

// MARK: - GRDB: Source

extension Source: FetchableRecord, PersistableRecord {
    static let databaseTableName = "source"

    nonisolated init(row: Row) throws {
        id          = row["id"]
        name        = row["name"]
        language    = row["language"]
        version     = row["version"]
        iconURL     = (row["iconURL"] as String?).flatMap { URL(string: $0) }
        baseURL     = URL(string: row["baseURL"])!
        isInstalled = row["isInstalled"]
        isNSFW      = row["isNSFW"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]          = id
        container["name"]        = name
        container["language"]    = language
        container["version"]     = version
        container["iconURL"]     = iconURL?.absoluteString
        container["baseURL"]     = baseURL.absoluteString
        container["isInstalled"] = isInstalled
        container["isNSFW"]      = isNSFW
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
        sourceListURL = URL(string: row["sourceListURL"])!
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
        // Decodifica el JSON almacenado de vuelta a [String]
        let raw: String = row["genres"] ?? "[]"
        genres        = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        inLibrary      = row["inLibrary"]
        lastReadAt     = row["lastReadAt"]
        lastUpdatedAt  = row["lastUpdatedAt"]
        readingSeconds = row["readingSeconds"] ?? 0
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]             = id
        container["path"]           = path
        container["sourceId"]       = sourceId
        container["title"]          = title
        container["coverURL"]       = coverURL?.absoluteString
        container["summary"]        = summary
        container["author"]         = author
        container["status"]         = status
        // Serializa [String] a JSON para guardarlo en la columna TEXT
        container["genres"]         = (try? JSONEncoder().encode(genres))
                                          .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        container["inLibrary"]      = inLibrary
        container["lastReadAt"]     = lastReadAt
        container["lastUpdatedAt"]  = lastUpdatedAt
        container["readingSeconds"] = readingSeconds
    }
}

// MARK: - GRDB: NovelChapter

extension NovelChapter: FetchableRecord, PersistableRecord {
    static let databaseTableName = "novel_chapter"

    nonisolated init(row: Row) throws {
        id            = row["id"]
        novelId       = row["novelId"]
        path          = row["path"]
        name          = row["name"]
        chapterNumber = row["chapterNumber"]
        isRead        = row["isRead"]
        readAt        = row["readAt"]
        releaseTime   = row["releaseTime"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"]            = id
        container["novelId"]       = novelId
        container["path"]          = path
        container["name"]          = name
        container["chapterNumber"] = chapterNumber
        container["isRead"]        = isRead
        container["readAt"]        = readAt
        container["releaseTime"]   = releaseTime
    }
}
