import Foundation
import GRDB

/// CRUD operations for the extension table
enum ExtensionQueries {

    // MARK: - Read

    /// Returns all installed extensions
    nonisolated static func fetchInstalled() throws -> [Extension] {
        try appDatabase.read { db in
            try Extension
                .filter(Column("isInstalled") == true)
                .fetchAll(db)
        }
    }

    /// Whether any saved manga or novel (library, history, progress) still belongs to this source.
    nonisolated static func hasTitles(sourceId: String) throws -> Bool {
        try appDatabase.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM manga WHERE sourceId = ?)
                    OR EXISTS(SELECT 1 FROM novel WHERE sourceId = ?)
                """, arguments: [sourceId, sourceId]) ?? false
        }
    }

    /// Every source id saved titles use.
    nonisolated static func titleSourceIds() throws -> Set<String> {
        try appDatabase.read { db in
            Set(try String.fetchAll(db, sql: "SELECT sourceId FROM manga UNION SELECT sourceId FROM novel"))
        }
    }

    /// Moves every saved manga and novel from one source id to another.
    nonisolated static func moveTitles(from oldId: String, to newId: String) throws {
        try appDatabase.write { db in
            try db.execute(sql: "UPDATE manga SET sourceId = ? WHERE sourceId = ?", arguments: [newId, oldId])
            try db.execute(sql: "UPDATE novel SET sourceId = ? WHERE sourceId = ?", arguments: [newId, oldId])
        }
    }

    // MARK: - Write

    /// Inserts or updates an extension record
    nonisolated static func upsert(_ ext: Extension) throws {
        _ = try appDatabase.write { db in
            try ext.save(db)
        }
    }

    // MARK: - Delete

    /// Removes the extension with the given id
    nonisolated static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            _ = try Extension.deleteOne(db, key: id)
        }
    }
}
