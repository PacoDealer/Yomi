import Foundation
import GRDB

/// Operaciones CRUD para la tabla chapter
enum ChapterQueries {

    // MARK: - Lectura

    /// Devuelve todos los capítulos de un manga ordenados por número de capítulo ascendente
    static func fetchAll(mangaId: String) throws -> [Chapter] {
        try DatabaseManager.shared.db.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .order(Column("chapterNumber").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Escritura

    /// Inserta o actualiza un capítulo (usa el id como clave)
    static func upsert(_ chapter: Chapter) throws {
        try DatabaseManager.shared.db.write { db in
            try chapter.save(db)
        }
    }

    /// Marca un capítulo como leído: isRead=true, readAt=ahora, progress=1.0
    static func markRead(id: String) throws {
        try DatabaseManager.shared.db.write { db in
            try Chapter
                .filter(Column("id") == id)
                .updateAll(db, [
                    Column("isRead").set(to: true),
                    Column("readAt").set(to: Date()),
                    Column("progress").set(to: 1.0)
                ])
        }
    }

    // MARK: - Eliminación

    /// Elimina el capítulo con el id indicado (no lanza error si no existe)
    static func delete(id: String) throws {
        try DatabaseManager.shared.db.write { db in
            _ = try Chapter.deleteOne(db, key: id)
        }
    }
}
