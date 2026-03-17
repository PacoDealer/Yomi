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

    /// Devuelve todos los manga con lastReadAt != nil, ordenados por fecha de lectura descendente
    nonisolated static func fetchHistory() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .fetchAll(db)
        }
    }

    /// Devuelve manga con lastReadAt != nil, ordenados por fecha de lectura descendente, con límite
    nonisolated static func fetchRecentlyRead(limit: Int = 50) throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("lastReadAt") != nil)
                .order(Column("lastReadAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Devuelve los manga en biblioteca ordenados por lastUpdatedAt DESC.
    /// Excluye los que tienen lastUpdatedAt nil.
    nonisolated static func fetchLibraryByLastUpdated() throws -> [Manga] {
        try appDatabase.read { db in
            try Manga
                .filter(Column("inLibrary") == true)
                .filter(Column("lastUpdatedAt") != nil)
                .order(Column("lastUpdatedAt").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Escritura

    /// Alterna inLibrary, actualiza lastUpdatedAt y guarda; devuelve el manga actualizado
    @discardableResult
    nonisolated static func toggleLibrary(manga: Manga) throws -> Manga {
        var updated = manga
        updated.inLibrary = !manga.inLibrary
        updated.lastUpdatedAt = Date()
        _ = try appDatabase.write { db in
            try updated.save(db)
        }
        return updated
    }

    /// Inserta un nuevo manga; falla si ya existe un registro con el mismo id
    nonisolated static func insert(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.insert(db)
        }
    }

    /// Actualiza todos los campos de un manga existente por su id
    nonisolated static func update(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.update(db)
        }
    }

    /// Inserta o actualiza un manga (save = insert or replace)
    nonisolated static func upsert(_ manga: Manga) throws {
        _ = try appDatabase.write { db in
            try manga.save(db)
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

    /// Actualiza lastUpdatedAt a la fecha actual para el manga indicado
    nonisolated static func touchLastUpdated(mangaId: String) throws {
        _ = try appDatabase.write { db in
            try Manga
                .filter(Column("id") == mangaId)
                .updateAll(db, [Column("lastUpdatedAt").set(to: Date())])
        }
    }

    // MARK: - Eliminación

    /// Elimina el manga con el id indicado (no lanza error si no existe)
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Manga.deleteOne(db, key: id)
        }
    }
}
