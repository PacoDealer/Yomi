import Foundation
import GRDB

/// Operaciones CRUD para la tabla manga
enum MangaQueries {

    // MARK: - Lectura

    /// Devuelve todos los manga guardados en la base de datos
    static func fetchAll() throws -> [Manga] {
        try DatabaseManager.shared.db.read { db in
            try Manga.fetchAll(db)
        }
    }

    /// Devuelve solo los manga que el usuario agregó a su biblioteca
    static func fetchLibrary() throws -> [Manga] {
        try DatabaseManager.shared.db.read { db in
            try Manga
                .filter(Column("inLibrary") == true)
                .fetchAll(db)
        }
    }

    // MARK: - Escritura

    /// Inserta un nuevo manga; falla si ya existe un registro con el mismo id
    static func insert(_ manga: Manga) throws {
        try DatabaseManager.shared.db.write { db in
            try manga.insert(db)
        }
    }

    /// Actualiza todos los campos de un manga existente por su id
    static func update(_ manga: Manga) throws {
        try DatabaseManager.shared.db.write { db in
            try manga.update(db)
        }
    }

    // MARK: - Eliminación

    /// Elimina el manga con el id indicado (no lanza error si no existe)
    static func delete(id: String) throws {
        try DatabaseManager.shared.db.write { db in
            _ = try Manga.deleteOne(db, key: id)
        }
    }
}
