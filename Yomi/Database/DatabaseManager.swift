import Foundation
import GRDB

/// Gestiona la conexión y las migraciones de la base de datos SQLite
final class DatabaseManager {

    // MARK: - Singleton

    static let shared = DatabaseManager()
    private init() {}

    // MARK: - Conexión

    /// Cola de acceso a la base de datos; se inicializa en setup()
    private(set) var db: DatabaseQueue!

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

        try migrator.migrate(db)
    }
}

// MARK: - GRDB: Manga

extension Manga: FetchableRecord, PersistableRecord {
    static let databaseTableName = "manga"

    init(row: Row) throws {
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
        inLibrary     = row["inLibrary"]
        isLocal       = row["isLocal"]
        lastReadAt    = row["lastReadAt"]
        lastUpdatedAt = row["lastUpdatedAt"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"]            = id
        container["path"]          = path
        container["sourceId"]      = sourceId
        container["title"]         = title
        container["coverURL"]      = coverURL?.absoluteString
        container["summary"]       = summary
        container["author"]        = author
        container["artist"]        = artist
        container["status"]        = status.rawValue
        // Serializa [String] a JSON para guardarlo en la columna TEXT
        container["genres"]        = (try? JSONEncoder().encode(genres))
                                         .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        container["inLibrary"]     = inLibrary
        container["isLocal"]       = isLocal
        container["lastReadAt"]    = lastReadAt
        container["lastUpdatedAt"] = lastUpdatedAt
    }
}

// MARK: - GRDB: Chapter

extension Chapter: FetchableRecord, PersistableRecord {
    static let databaseTableName = "chapter"

    init(row: Row) throws {
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

    func encode(to container: inout PersistenceContainer) throws {
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

    init(row: Row) throws {
        id   = row["id"]
        name = row["name"]
        sort = row["sort"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"]   = id
        container["name"] = name
        container["sort"] = sort
    }
}

// MARK: - GRDB: Source

extension Source: FetchableRecord, PersistableRecord {
    static let databaseTableName = "source"

    init(row: Row) throws {
        id          = row["id"]
        name        = row["name"]
        language    = row["language"]
        version     = row["version"]
        iconURL     = (row["iconURL"] as String?).flatMap { URL(string: $0) }
        baseURL     = URL(string: row["baseURL"])!
        isInstalled = row["isInstalled"]
        isNSFW      = row["isNSFW"]
    }

    func encode(to container: inout PersistenceContainer) throws {
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
