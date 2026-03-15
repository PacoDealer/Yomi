import Foundation
import GRDB

/// Operaciones CRUD para las tablas novel y novel_chapter
enum NovelQueries {

    // MARK: - Novel: Lectura

    /// Devuelve todas las novelas guardadas en la base de datos
    static func fetchAll() throws -> [Novel] {
        try DatabaseManager.shared.database.read { db in
            try Novel.fetchAll(db)
        }
    }

    /// Devuelve solo las novelas que el usuario agregó a su biblioteca
    static func fetchLibrary() throws -> [Novel] {
        try DatabaseManager.shared.database.read { db in
            try Novel
                .filter(Column("inLibrary") == true)
                .fetchAll(db)
        }
    }

    // MARK: - Novel: Escritura

    /// Inserta una nueva novela; falla si ya existe un registro con el mismo id
    static func insert(_ novel: Novel) throws {
        try DatabaseManager.shared.database.write { db in
            try novel.insert(db)
        }
    }

    /// Actualiza todos los campos de una novela existente por su id
    static func update(_ novel: Novel) throws {
        try DatabaseManager.shared.database.write { db in
            try novel.update(db)
        }
    }

    /// Inserta o actualiza una novela (usa el id como clave)
    static func upsert(_ novel: Novel) throws {
        try DatabaseManager.shared.database.write { db in
            try novel.save(db)
        }
    }

    // MARK: - Novel: Eliminación

    /// Elimina la novela con el id indicado (no lanza error si no existe)
    static func delete(id: String) throws {
        try DatabaseManager.shared.database.write { db in
            _ = try Novel.deleteOne(db, key: id)
        }
    }

    // MARK: - NovelChapter: Lectura

    /// Devuelve todos los capítulos de una novela ordenados por número de capítulo ascendente
    static func fetchChapters(novelId: String) throws -> [NovelChapter] {
        try DatabaseManager.shared.database.read { db in
            try NovelChapter
                .filter(Column("novelId") == novelId)
                .order(Column("chapterNumber").asc)
                .fetchAll(db)
        }
    }

    // MARK: - NovelChapter: Escritura

    /// Inserta o actualiza un capítulo (usa el id como clave)
    static func upsertChapter(_ chapter: NovelChapter) throws {
        try DatabaseManager.shared.database.write { db in
            try chapter.save(db)
        }
    }

    /// Inserta o actualiza un lote de capítulos en una sola transacción
    static func upsertChapters(_ chapters: [NovelChapter]) throws {
        try DatabaseManager.shared.database.write { db in
            for chapter in chapters {
                try chapter.save(db)
            }
        }
    }

    /// Marca un capítulo como leído: isRead=true, readAt=ahora
    static func markRead(chapterId: String) throws {
        _ = try DatabaseManager.shared.database.write { db in
            try NovelChapter
                .filter(Column("id") == chapterId)
                .updateAll(db, [
                    Column("isRead").set(to: true),
                    Column("readAt").set(to: Date())
                ])
        }
    }
}
