import Foundation
import GRDB

/// A novel's term replacement rules (v30, S177). `novelId == nil` = applies to every novel.
nonisolated struct TermReplacement: Identifiable, Equatable, Sendable {
    var id: String
    var novelId: String?
    var find: String
    var replacement: String
    var matchCase: Bool
    var createdAt: Date

    var rule: TermRule { TermRule(find: find, replace: replacement, matchCase: matchCase) }

    static func new(novelId: String?, find: String = "", replacement: String = "") -> TermReplacement {
        TermReplacement(id: UUID().uuidString, novelId: novelId, find: find, replacement: replacement,
                        matchCase: true, createdAt: Date())
    }

    fileprivate init(id: String, novelId: String?, find: String, replacement: String, matchCase: Bool, createdAt: Date) {
        self.id = id; self.novelId = novelId; self.find = find; self.replacement = replacement
        self.matchCase = matchCase; self.createdAt = createdAt
    }

    fileprivate init(row: Row) {
        self.init(id: row["id"], novelId: row["novelId"], find: row["find"], replacement: row["replacement"],
                  matchCase: row["matchCase"], createdAt: row["createdAt"])
    }
}

nonisolated enum TermReplacementQueries {
    /// This novel's rules, then the ones for every novel; oldest first within each.
    static func all(novelId: String) throws -> [TermReplacement] {
        try appDatabase.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM term_replacement WHERE novelId = ? OR novelId IS NULL
                ORDER BY novelId IS NULL, createdAt
                """, arguments: [novelId]).map(TermReplacement.init(row:))
        }
    }

    /// Rules to apply to a chapter: the novel's own win over global ones with the same term (`TermReplacer.prepared`).
    static func rules(novelId: String) -> [TermRule] {
        ((try? all(novelId: novelId)) ?? []).map(\.rule)
    }

    static func save(_ r: TermReplacement) throws {
        _ = try appDatabase.write { db in
            try db.execute(sql: """
                INSERT INTO term_replacement (id, novelId, find, replacement, matchCase, createdAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET novelId = excluded.novelId, find = excluded.find,
                    replacement = excluded.replacement, matchCase = excluded.matchCase
                """, arguments: [r.id, r.novelId, r.find, r.replacement, r.matchCase, r.createdAt])
        }
    }

    static func delete(id: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(sql: "DELETE FROM term_replacement WHERE id = ?", arguments: [id])
        }
    }

    // MARK: Backup

    static func exportRows() throws -> [[String: Any]] {
        try appDatabase.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM term_replacement ORDER BY createdAt").map { row in
                var d: [String: Any] = ["id": row["id"] as String, "find": row["find"] as String,
                                        "replacement": row["replacement"] as String,
                                        "matchCase": row["matchCase"] as Bool,
                                        "createdAt": (row["createdAt"] as Date).timeIntervalSince1970]
                if let novelId = row["novelId"] as String? { d["novelId"] = novelId }
                return d
            }
        }
    }

    /// Restore adds rules it doesn't have (by id); a novel-specific rule needs its novel in the library.
    static func importRows(_ rows: [[String: Any]], db: Database) throws {
        for d in rows {
            guard let id = d["id"] as? String, let find = d["find"] as? String,
                  let replacement = d["replacement"] as? String else { continue }
            let novelId = d["novelId"] as? String
            let created = Date(timeIntervalSince1970: (d["createdAt"] as? Double) ?? Date().timeIntervalSince1970)
            try db.execute(sql: """
                INSERT OR IGNORE INTO term_replacement (id, novelId, find, replacement, matchCase, createdAt)
                SELECT ?, ?, ?, ?, ?, ? WHERE ? IS NULL OR EXISTS (SELECT 1 FROM novel WHERE id = ?)
                """, arguments: [id, novelId, find, replacement, (d["matchCase"] as? Bool) ?? true, created,
                                 novelId, novelId])
        }
    }
}
