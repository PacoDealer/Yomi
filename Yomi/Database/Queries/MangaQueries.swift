import Foundation
import GRDB

/// Operaciones CRUD para la tabla manga
enum MangaQueries {

    // MARK: - Lectura

    /// Devuelve todos los manga guardados en la base de datos
    nonisolated static func fetchAll() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga.fetchAll(db)
        }
    }

    /// Devuelve el manga con el id indicado, o nil si no existe
    nonisolated static func fetchOne(id: String) throws -> Manga? {
        try appDatabase.read { db in
            try Manga.fetchOne(db, key: id)
        }
    }

    /// Devuelve solo los manga que el usuario agregó a su biblioteca
    nonisolated static func fetchLibrary() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("inLibrary") == true)
                .fetchAll(db)
        }
    }

    /// Devuelve manga con lastReadAt != nil, ordenados por fecha de lectura descendente
    nonisolated static func fetchHistory() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Escritura

    /// Inserta un nuevo manga; falla si ya existe un registro con el mismo id
    nonisolated static func insert(_ manga: Manga) throws {
        try appDatabase.write { db in
            try manga.insert(db)
        }
    }

    /// Actualiza todos los campos de un manga existente por su id
    nonisolated static func update(_ manga: Manga) throws {
        try appDatabase.write { db in
            try manga.update(db)
        }
    }

    /// Actualiza lastReadAt a la fecha actual para el manga indicado
    nonisolated static func touchLastRead(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("lastReadAt").set(to: Date())])
        }
    }

    // MARK: - Eliminación

    /// Elimina el manga con el id indicado (no lanza error si no existe)
    nonisolated static func delete(id: String) throws {
        try appDatabase.write { db in
            _ = try Manga.deleteOne(db, key: id)
        }
    }
}
