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

    // MARK: - Progress

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

    /// Actualiza progress y readingSeconds de un capítulo (UPDATE directo, sin fetch previo)
    nonisolated static func updateProgress(id: String, progress: Double, readingSeconds: Int) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET progress = ?, readingSeconds = ? WHERE id = ?",
                arguments: [progress, readingSeconds, id]
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
