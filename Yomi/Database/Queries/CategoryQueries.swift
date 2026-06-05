import Foundation
import GRDB

/// CRUD operations for the category table and manga_category / novel_category join tables
enum CategoryQueries {

    // MARK: - Category CRUD

    /// Returns all categories ordered by sort ASC, then name ASC
    nonisolated static func fetchAll() throws -> [Category] {
        try appDatabase.read { db in
            try Category
                .order(Column("sort").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Creates a new category with sort = (current max) + 1 and persists it
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

    /// Renames an existing category
    nonisolated static func rename(id: String, name: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE category SET name = ? WHERE id = ?",
                arguments: [name, id]
            )
        }
    }

    /// Deletes a category; manga_category rows are removed by CASCADE
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Category.deleteOne(db, key: id)
        }
    }

    /// Updates the sort value of a category
    nonisolated static func updateSort(id: String, sort: Int) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE category SET sort = ? WHERE id = ?",
                arguments: [sort, id]
            )
        }
    }

    // MARK: - manga_category join

    /// Assigns a manga to a category (INSERT OR IGNORE — no-op if already assigned)
    nonisolated static func assign(mangaId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO manga_category (mangaId, categoryId) VALUES (?, ?)",
                arguments: [mangaId, categoryId]
            )
        }
    }

    /// Removes the assignment of a manga to a category
    nonisolated static func unassign(mangaId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM manga_category WHERE mangaId = ? AND categoryId = ?",
                arguments: [mangaId, categoryId]
            )
        }
    }

    /// Returns categories assigned to a manga, ordered by sort ASC
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

    /// Returns mangaIds assigned to a category
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

    /// Assigns a novel to a category (INSERT OR IGNORE)
    nonisolated static func assignNovel(novelId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO novel_category (novelId, categoryId) VALUES (?, ?)",
                arguments: [novelId, categoryId]
            )
        }
    }

    /// Removes the assignment of a novel to a category
    nonisolated static func unassignNovel(novelId: String, categoryId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM novel_category WHERE novelId = ? AND categoryId = ?",
                arguments: [novelId, categoryId]
            )
        }
    }

    /// Returns categories assigned to a novel, ordered by sort ASC
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

    /// Returns novelIds assigned to a category
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
