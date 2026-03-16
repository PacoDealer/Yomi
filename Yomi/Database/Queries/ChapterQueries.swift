import Foundation
import GRDB

/// Operaciones CRUD para la tabla chapter
enum ChapterQueries {

    // MARK: - Lectura

    /// Devuelve todos los capítulos de un manga ordenados por número de capítulo ascendente
    nonisolated static func fetchAll(mangaId: String) throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .order(Column("chapterNumber").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Escritura

    /// Inserta o actualiza un capítulo (usa el id como clave)
    nonisolated static func upsert(_ chapter: Chapter) throws {
        _ = try appDatabase.write { db in
            try chapter.save(db)
        }
    }

    /// Marca un capítulo como leído: isRead=true, readAt=ahora, progress=1.0
    /// También actualiza lastReadAt del manga padre.
    nonisolated static func markRead(id: String, mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Chapter
                .filter(Column("id") == id)
                .updateAll(db, [
                    Column("isRead").set(to: true),
                    Column("readAt").set(to: Date()),
                    Column("progress").set(to: 1.0)
                ])
        }
        try? MangaQueries.touchLastRead(mangaId: mangaId)
    }

    /// Acumula segundos de lectura en el campo readingSeconds del capítulo
    nonisolated static func addReadingTime(id: String, seconds: Int) throws {
        guard seconds > 0 else { return }
        _ = try appDatabase.write { db in
            try Chapter
                .filter(Column("id") == id)
                .updateAll(db, Column("readingSeconds") += seconds)
        }
    }

    // MARK: - Eliminación

    /// Elimina el capítulo con el id indicado (no lanza error si no existe)
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Chapter.deleteOne(db, key: id)
        }
    }
}
