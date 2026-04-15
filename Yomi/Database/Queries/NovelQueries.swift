import Foundation
import GRDB

/// Operaciones CRUD para las tablas novel y novel_chapter
enum NovelQueries {

    // MARK: - Novel: Lectura

    /// Devuelve todas las novelas guardadas en la base de datos
    nonisolated static func fetchAll() throws -> [Novel] {
        try appDatabase.read { db in
            try Novel.fetchAll(db)
        }
    }

    /// Devuelve solo las novelas que el usuario agregó a su biblioteca
    nonisolated static func fetchLibrary() throws -> [Novel] {
        try appDatabase.read { db in
            try Novel
                .filter(Column("inLibrary") == true)
                .fetchAll(db)
        }
    }

    /// Devuelve la novela con el id indicado, o nil si no existe
    nonisolated static func fetchOne(id: String) throws -> Novel? {
        try appDatabase.read { db in
            try Novel.fetchOne(db, key: id)
        }
    }

    /// Devuelve novelas con lastReadAt != nil, ordenadas por fecha de lectura descendente
    nonisolated static func fetchHistory() throws -> [Novel] {
        try appDatabase.read { db in
            try Novel
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .fetchAll(db)
        }
    }

    /// Devuelve novelas con lastReadAt != nil, ordenadas por fecha de lectura descendente, con límite
    nonisolated static func fetchRecentlyRead(limit: Int = 10) throws -> [Novel] {
        try appDatabase.read { db in
            try Novel
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Novel: Escritura

    /// Inserta una nueva novela; falla si ya existe un registro con el mismo id
    nonisolated static func insert(_ novel: Novel) throws {
        try appDatabase.write { db in
            try novel.insert(db)
        }
    }

    /// Actualiza todos los campos de una novela existente por su id
    nonisolated static func update(_ novel: Novel) throws {
        try appDatabase.write { db in
            try novel.update(db)
        }
    }

    /// Inserta o actualiza una novela (usa el id como clave)
    nonisolated static func upsert(_ novel: Novel) throws {
        try appDatabase.write { db in
            try novel.save(db)
        }
    }

    // MARK: - Novel: Eliminación

    /// Elimina la novela con el id indicado (no lanza error si no existe)
    nonisolated static func delete(id: String) throws {
        try appDatabase.write { db in
            _ = try Novel.deleteOne(db, key: id)
        }
    }

    /// Borra lastReadAt de una novela (swipe-to-delete en History)
    nonisolated static func clearLastRead(novelId: String) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("lastReadAt").set(to: nil)])
        }
    }

    /// Actualiza lastUpdatedAt de una novela a la fecha actual
    nonisolated static func touchLastUpdated(novelId: String) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("lastUpdatedAt").set(to: Date())])
        }
    }

    /// Actualiza el readingStatus de una novela (estado definido por el usuario)
    nonisolated static func updateReadingStatus(novelId: String, status: ReadingStatus) throws {
        _ = try appDatabase.write { db in
            try Novel
                .filter(Column("id") == novelId)
                .updateAll(db, [Column("readingStatus").set(to: status.rawValue)])
        }
    }

    // MARK: - NovelChapter: Lectura

    /// Devuelve todos los capítulos de una novela ordenados por número de capítulo ascendente
    nonisolated static func fetchChapters(novelId: String) throws -> [NovelChapter] {
        try appDatabase.read { db in
            try NovelChapter
                .filter(Column("novelId") == novelId)
                .order(Column("chapterNumber").asc)
                .fetchAll(db)
        }
    }

    /// Devuelve el conteo de capítulos no leídos agrupado por novelId
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

    // MARK: - NovelChapter: Escritura

    /// Inserta capítulos en lote usando INSERT OR IGNORE — nunca sobreescribe isRead ni readingSeconds existentes
    nonisolated static func insertAllIgnoringConflicts(_ chapters: [NovelChapter]) throws {
        try appDatabase.write { db in
            for ch in chapters {
                try ch.insert(db, onConflict: .ignore)
            }
        }
    }

    /// Inserta o actualiza un capítulo (usa el id como clave)
    nonisolated static func upsertChapter(_ chapter: NovelChapter) throws {
        try appDatabase.write { db in
            try chapter.save(db)
        }
    }

    /// Inserta o actualiza un lote de capítulos en una sola transacción
    nonisolated static func upsertChapters(_ chapters: [NovelChapter]) throws {
        try appDatabase.write { db in
            for chapter in chapters {
                try chapter.save(db)
            }
        }
    }

    /// Acumula segundos de lectura en un capítulo y actualiza lastReadAt + readingSeconds en la novela
    nonisolated static func addReadingTime(chapterId: String, novelId: String, seconds: Int) throws {
        _ = try appDatabase.write { db in
            try NovelChapter
                .filter(Column("id") == chapterId)
                .updateAll(db, [Column("readingSeconds").set(to: Column("readingSeconds") + seconds)])
        }
        guard var novel = try appDatabase.read({ db in try Novel.fetchOne(db, key: novelId) }) else { return }
        novel.readingSeconds += seconds
        novel.lastReadAt = Date()
        _ = try appDatabase.write { db in try novel.update(db) }
    }

    /// Marca un capítulo como leído: isRead=true, readAt=ahora
    nonisolated static func markRead(chapterId: String) throws {
        _ = try appDatabase.write { db in
            try NovelChapter
                .filter(Column("id") == chapterId)
                .updateAll(db, [
                    Column("isRead").set(to: true),
                    Column("readAt").set(to: Date())
                ])
        }
    }
}
