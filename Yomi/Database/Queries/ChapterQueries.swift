import Foundation
import GRDB

/// Operaciones CRUD para la tabla chapter
enum ChapterQueries {

    // MARK: - Read

    /// Devuelve todos los capítulos de un manga ordenados por chapterNumber ASC, nulos al final
    nonisolated static func fetchAll(mangaId: String) throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .order(Column("chapterNumber").ascNullsLast)
                .fetchAll(db)
        }
    }

    /// Devuelve el capítulo con el id indicado, o nil si no existe
    nonisolated static func fetchOne(id: String) throws -> Chapter? {
        try appDatabase.read { db in
            try Chapter.fetchOne(db, key: id)
        }
    }

    /// Devuelve el número de capítulos descargados de un manga
    nonisolated static func downloadedCount(mangaId: String) throws -> Int {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .filter(Column("isDownloaded") == true)
                .fetchCount(db)
        }
    }

    /// Devuelve un diccionario [mangaId: unreadCount] para todos los manga de la biblioteca.
    /// Una sola query SQL, sin N+1.
    nonisolated static func fetchUnreadCountsByManga() throws -> [String: Int] {
        try appDatabase.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT mangaId, COUNT(*) as cnt FROM chapter WHERE isRead = 0 GROUP BY mangaId"
            )
            return Dictionary(uniqueKeysWithValues: rows.map { (($0["mangaId"] as String), ($0["cnt"] as Int)) })
        }
    }

    /// Devuelve los capítulos no leídos de un manga ordenados por chapterNumber ASC, nulos al final
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

    /// Inserta un nuevo capítulo; falla si ya existe un registro con el mismo id
    nonisolated static func insert(_ chapter: Chapter) throws {
        _ = try appDatabase.write { db in
            try chapter.insert(db)
        }
    }

    /// Inserta o actualiza un capítulo (save = insert or replace)
    nonisolated static func upsert(_ chapter: Chapter) throws {
        _ = try appDatabase.write { db in
            try chapter.save(db)
        }
    }

    /// Inserta o actualiza una colección de capítulos en una sola transacción
    nonisolated static func upsertAll(_ chapters: [Chapter]) throws {
        _ = try appDatabase.write { db in
            for chapter in chapters {
                try chapter.save(db)
            }
        }
    }

    /// Inserta capítulos nuevos ignorando conflictos (INSERT OR IGNORE).
    /// Nunca sobreescribe isRead, isDownloaded ni progress de filas existentes.
    /// Llamar después de obtener la lista desde JSBridge, antes del merge con DB.
    nonisolated static func insertAllIgnoringConflicts(_ chapters: [Chapter]) throws {
        _ = try appDatabase.write { db in
            for chapter in chapters {
                try chapter.insert(db, onConflict: .ignore)
            }
        }
    }

    /// Inserta el manga y sus capítulos en una sola transacción (INSERT OR IGNORE).
    /// El INSERT OR IGNORE del manga garantiza que la FK constraint se satisfaga
    /// aunque el manga no esté todavía en la biblioteca (browsing sin añadir al library).
    nonisolated static func insertMangaAndChapters(manga: Manga, chapters: [Chapter]) throws {
        _ = try appDatabase.write { db in
            try manga.insert(db, onConflict: .ignore)
            for chapter in chapters {
                try chapter.insert(db, onConflict: .ignore)
            }
        }
    }

    // MARK: - Progress

    /// Marca un capítulo como leído con isRead=true, readAt=ahora y progress=1.0 (UPDATE directo, sin fetch previo)
    nonisolated static func markRead(id: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ?, progress = 1.0 WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    /// Marca un capítulo como leído con isRead=true y readAt=ahora (UPDATE directo, sin fetch previo)
    nonisolated static func markRead(id: String, mangaId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Marca un capítulo como leído o no leído (isRead flexible)
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

    /// Marca todos los capítulos de un manga como leídos con isRead=true y readAt=ahora
    nonisolated static func markAllRead(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isRead = 1, readAt = ? WHERE mangaId = ?",
                arguments: [Date(), mangaId]
            )
        }
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Actualiza progress, readingSeconds y lastPageRead de un capítulo (UPDATE directo, sin fetch previo)
    nonisolated static func updateProgress(id: String, progress: Double, readingSeconds: Int, lastPageRead: Int = 0) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET progress = ?, readingSeconds = ?, lastPageRead = ? WHERE id = ?",
                arguments: [progress, readingSeconds, lastPageRead, id]
            )
        }
    }

    /// Acumula segundos de lectura en readingSeconds del capítulo
    nonisolated static func addReadingTime(id: String, seconds: Int) throws {
        guard seconds > 0 else { return }
        _ = try appDatabase.write { db in
            try Chapter
                .filter(Column("id") == id)
                .updateAll(db, Column("readingSeconds") += seconds)
        }
    }

    // MARK: - Delete

    /// Elimina el capítulo con el id indicado (no lanza error si no existe)
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Chapter.deleteOne(db, key: id)
        }
    }

    /// Elimina todos los capítulos de un manga
    nonisolated static func deleteAll(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .deleteAll(db)
        }
    }
}
