import Foundation
import GRDB

/// CRUD operations for the extension table
enum ExtensionQueries {

    // MARK: - Read

    /// Returns all installed extensions
    static func fetchInstalled() throws -> [Extension] {
        try DatabaseManager.shared.database.read { db in
            try Extension
                .filter(Column("isInstalled") == true)
                .fetchAll(db)
        }
    }

    /// Returns all extensions (installed or not)
    static func fetchAll() throws -> [Extension] {
        try DatabaseManager.shared.database.read { db in
            try Extension.fetchAll(db)
        }
    }

    // MARK: - Write

    /// Inserts or updates an extension record
    static func upsert(_ ext: Extension) throws {
        try DatabaseManager.shared.database.write { db in
            try ext.save(db)
        }
    }

    // MARK: - Delete

    /// Removes the extension with the given id
    static func delete(id: String) throws {
        try DatabaseManager.shared.database.write { db in
            _ = try Extension.deleteOne(db, key: id)
        }
    }
}
