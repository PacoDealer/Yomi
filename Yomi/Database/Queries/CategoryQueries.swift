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

    // MARK: - novel_category join

    /// Asigna una novela a una categoría (INSERT OR IGNORE)
    nonisolated static func assignNovel(novelId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO novel_category (novelId, categoryId) VALUES (?, ?)",
                arguments: [novelId, categoryId]
            )
        }
    }

    /// Elimina la asignación de una novela a una categoría
    nonisolated static func unassignNovel(novelId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM novel_category WHERE novelId = ? AND categoryId = ?",
                arguments: [novelId, categoryId]
            )
        }
    }

    /// Devuelve las categorías asignadas a una novela, ordenadas por sort ASC
    nonisolated static func categoriesForNovel(novelId: String) throws -> [Category] {
        try appDatabase.read { db in
            try Category.fetchAll(
                db,
                sql: """
                    SELECT category.*
                    FROM category
                    JOIN novel_category ON category.id = novel_category.categoryId
                    WHERE novel_category.novelId = ?
                    ORDER BY category.sort ASC
                    """,
                arguments: [novelId]
            )
        }
    }

    /// Devuelve los novelId asignados a una categoría
    nonisolated static func novelIds(inCategory categoryId: String) throws -> [String] {
        try appDatabase.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT novelId FROM novel_category WHERE categoryId = ?",
                arguments: [categoryId]
            )
        }
    }

    /// Returns total item count (manga + novels) per category ID.
    nonisolated static func fetchItemCounts() throws -> [String: Int] {
        try appDatabase.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT categoryId, SUM(cnt) AS total FROM (
                    SELECT categoryId, COUNT(*) AS cnt FROM manga_category GROUP BY categoryId
                    UNION ALL
                    SELECT categoryId, COUNT(*) AS cnt FROM novel_category GROUP BY categoryId
                ) GROUP BY categoryId
                """)
            return Dictionary(uniqueKeysWithValues: rows.map {
                ($0["categoryId"] as String, $0["total"] as Int)
            })
        }
    }
}
