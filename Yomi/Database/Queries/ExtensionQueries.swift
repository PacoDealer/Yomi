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

    /// Returns all extensions (installed or not)
    nonisolated static func fetchAll() throws -> [Extension] {
        try appDatabase.read { db in
            try Extension.fetchAll(db)
        }
    }

    // MARK: - Write

    /// Inserts or updates an extension record
    nonisolated static func upsert(_ ext: Extension) throws {
        try appDatabase.write { db in
            try ext.save(db)
        }
    }

    // MARK: - Delete

    /// Removes the extension with the given id
    nonisolated static func delete(id: String) throws {
        try appDatabase.write { db in
            _ = try Extension.deleteOne(db, key: id)
        }
    }
}
