import Foundation
import GRDB

/// Operaciones CRUD para la tabla category y la join table manga_category
enum CategoryQueries {

    // MARK: - Category CRUD

    /// Devuelve todas las categorías ordenadas por sort ASC, luego name ASC
    nonisolated static func fetchAll() throws -> [Category] {
        try appDatabase.read { db in
            try Category
                .order(Column("sort").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Crea una nueva categoría con sort = (máximo actual) + 1 y la persiste
    @discardableResult
    nonisolated static func insert(name: String) throws -> Category {
        try appDatabase.write { db in
            let maxSort = try Int.fetchOne(
                db,
                sql: "SELECT MAX(sort) FROM category"
            ) ?? -1
            let category = Category(
                id:   UUID().uuidString,
                name: name,
                sort: maxSort + 1
            )
            try category.insert(db)
            return category
        }
    }

    /// Renombra una categoría existente
    nonisolated static func rename(id: String, name: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE category SET name = ? WHERE id = ?",
                arguments: [name, id]
            )
        }
    }

    /// Elimina una categoría; las filas de manga_category se eliminan por CASCADE
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Category.deleteOne(db, key: id)
        }
    }

    /// Actualiza el valor de sort de una categoría
    nonisolated static func updateSort(id: String, sort: Int) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE category SET sort = ? WHERE id = ?",
                arguments: [sort, id]
            )
        }
    }

    // MARK: - manga_category join

    /// Asigna un manga a una categoría (INSERT OR IGNORE — no falla si ya existe)
    nonisolated static func assign(mangaId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO manga_category (mangaId, categoryId) VALUES (?, ?)",
                arguments: [mangaId, categoryId]
            )
        }
    }

    /// Elimina la asignación de un manga a una categoría
    nonisolated static func unassign(mangaId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM manga_category WHERE mangaId = ? AND categoryId = ?",
                arguments: [mangaId, categoryId]
            )
        }
    }

    /// Devuelve las categorías asignadas a un manga, ordenadas por sort ASC
    nonisolated static func categoriesForManga(mangaId: String) throws -> [Category] {
        try appDatabase.read { db in
            try Category.fetchAll(
                db,
                sql: """
                    SELECT category.*
                    FROM category
                    JOIN manga_category ON category.id = manga_category.categoryId
                    WHERE manga_category.mangaId = ?
                    ORDER BY category.sort ASC
                    """,
                arguments: [mangaId]
            )
        }
    }

    /// Devuelve los mangaId asignados a una categoría
    nonisolated static func mangaIds(inCategory categoryId: String) throws -> [String] {
        try appDatabase.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT mangaId FROM manga_category WHERE categoryId = ?",
                arguments: [categoryId]
            )
        }
    }
}
