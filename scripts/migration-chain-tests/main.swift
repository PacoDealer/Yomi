import Foundation
import GRDB

// S193: the migration chain had no test (S189 audit #15). Two runs of the app's real `makeMigrator()`:
//  1. fresh install — every migration applies, database is consistent;
//  2. a library from the first release (v1 schema, with data) upgraded through every step — data survives and the
//     data-changing migrations (v24 chapter numbers, v25 dead imports, v32 state stamps) do what they say.

var failures = 0, checks = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !ok { failures += 1; print("FAIL \(name) \(detail())") }
}

func consistent(_ db: DatabaseQueue) throws -> (integrity: [String], fk: Int) {
    try db.read { db in
        (try String.fetchAll(db, sql: "PRAGMA integrity_check"),
         try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count)
    }
}

let migrator = DatabaseManager.makeMigrator()
let names = migrator.migrations
check("migration ids are unique", Set(names).count == names.count, "\(names)")
check("migration ids are ordered by version", names.first == "v1_initial" && names.last?.hasPrefix("v32") == true,
      "\(names.first ?? "") … \(names.last ?? "")")

// MARK: 1. Fresh install

do {
    let db = try DatabaseQueue()
    try migrator.migrate(db)
    let done = try db.read { try migrator.appliedMigrations($0) }
    check("fresh: all migrations applied", done == names, "\(done.count)/\(names.count)")
    let c = try consistent(db)
    check("fresh: integrity ok", c.integrity == ["ok"], "\(c.integrity)")
    check("fresh: no broken foreign keys", c.fk == 0, "\(c.fk)")
    let tables = try db.read { try String.fetchAll(db: $0) }
    for t in ["manga", "chapter", "novel", "novel_chapter", "category", "manga_category", "novel_category",
              "cloud_sync_map", "pending_chapter_state", "pending_novel_chapter_state"] {
        check("fresh: table \(t) exists", tables.contains(t))
    }
    try migrator.migrate(db)   // a second launch
    check("fresh: second run is a no-op", try db.read { try migrator.appliedMigrations($0) } == names)
} catch { check("fresh install ran", false, "\(error)") }

extension String {
    static func fetchAll(db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
    }
}

// MARK: 2. A v1-era library upgraded step by step

do {
    let db = try DatabaseQueue()
    try migrator.migrate(db, upTo: "v1_initial")
    try db.write { db in
        // A title in the library: two chapters saved without numbers, one read.
        try db.execute(sql: "INSERT INTO manga (id, path, sourceId, title, inLibrary) VALUES ('m1', '/m1', 'asura', 'Solo Leveling', 1)")
        try db.execute(sql: """
            INSERT INTO chapter (id, mangaId, path, name, isRead, progress) VALUES
              ('c1', 'm1', '/c1', 'Chapter 12', 1, 1.0),
              ('c2', 'm1', '/c2', 'Chapter 13', 0, 0.4),
              ('c3', 'm1', '/c3', 'Side story', 0, 0)
            """)
        // A dead .tachibk import nobody touched (v25 removes it) and one in the library (v25 keeps it).
        try db.execute(sql: "INSERT INTO manga (id, path, sourceId, title, inLibrary) VALUES ('dead', '/d', 'tachiyomi_123', 'Dead', 0)")
        try db.execute(sql: "INSERT INTO chapter (id, mangaId, path, name) VALUES ('dc', 'dead', '/dc', 'Chapter 1')")
        try db.execute(sql: "INSERT INTO manga (id, path, sourceId, title, inLibrary) VALUES ('kept', '/k', 'tachiyomi_456', 'Kept', 1)")
    }
    // Novels arrive in v3.
    try migrator.migrate(db, upTo: "v3_novels")
    try db.write { db in
        try db.execute(sql: "INSERT INTO novel (id, path, sourceId, title, inLibrary) VALUES ('n1', '/n1', 'wetried', 'A Novel', 1)")
        try db.execute(sql: "INSERT INTO novel_chapter (id, novelId, path, name, isRead) VALUES ('nc1', 'n1', '/nc1', 'Chapter 7', 1)")
    }
    try migrator.migrate(db, upTo: "v24_parse_missing_chapter_numbers")
    let numbers = try db.read { db in
        try Row.fetchAll(db, sql: "SELECT id, chapterNumber FROM chapter WHERE mangaId = 'm1' ORDER BY id")
            .map { ($0["id"] as String, $0["chapterNumber"] as Double?) }
    }
    check("v24: numbers parsed from names", numbers.map(\.1) == [12, 13, nil], "\(numbers)")
    let novelNumber = try db.read { try Double.fetchOne($0, sql: "SELECT chapterNumber FROM novel_chapter WHERE id = 'nc1'") }
    check("v24: novel chapter number parsed", novelNumber == 7, "\(String(describing: novelNumber))")
    // Sync mappings for the dead import: one never uploaded, one uploaded.
    try db.write { db in
        try db.execute(sql: "INSERT INTO cloud_sync_map (recordName, recordType, key) VALUES ('r-new', 'manga', 'dead')")
        try db.execute(sql: "INSERT INTO cloud_sync_map (recordName, recordType, key, recordData) VALUES ('r-up', 'mangaChapterState', 'dead|dc', x'00')")
        try db.execute(sql: "INSERT INTO cloud_sync_map (recordName, recordType, key) VALUES ('r-m1', 'manga', 'm1')")
    }
    try migrator.migrate(db)
    let done = try db.read { try migrator.appliedMigrations($0) }
    check("upgrade: all migrations applied", done == names, "\(done.count)/\(names.count)")
    let c = try consistent(db)
    check("upgrade: integrity ok", c.integrity == ["ok"], "\(c.integrity)")
    check("upgrade: no broken foreign keys", c.fk == 0, "\(c.fk)")

    try db.read { db in
        let ids = try String.fetchAll(db, sql: "SELECT id FROM manga ORDER BY id")
        check("v25: dead import removed, library titles kept", ids == ["kept", "m1"], "\(ids)")
        check("v25: dead import's chapters removed",
              try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chapter WHERE mangaId = 'dead'") == 0)
        let sync = try Row.fetchAll(db, sql: "SELECT recordName, pendingChange FROM cloud_sync_map ORDER BY recordName")
            .map { "\($0["recordName"] as String)=\(($0["pendingChange"] as String?) ?? "-")" }
        check("v25: never-uploaded mapping dropped, uploaded one marked delete, others untouched",
              sync == ["r-m1=-", "r-up=delete"], "\(sync)")
        let state = try Row.fetchAll(db, sql: "SELECT id, isRead, progress FROM chapter WHERE mangaId = 'm1' ORDER BY id")
            .map { "\($0["id"] as String):\($0["isRead"] as Bool):\($0["progress"] as Double)" }
        check("upgrade: reading state kept", state == ["c1:true:1.0", "c2:false:0.4", "c3:false:0.0"], "\(state)")
        check("upgrade: novel kept", try Bool.fetchOne(db, sql: "SELECT isRead FROM novel_chapter WHERE id = 'nc1'") == true)
        // The app's own record types decode every upgraded row.
        let mangas = try Manga.fetchAll(db), chapters = try Chapter.fetchAll(db)
        let novels = try Novel.fetchAll(db), novelChapters = try NovelChapter.fetchAll(db)
        check("upgrade: rows decode as the app's models",
              mangas.count == 2 && chapters.count == 3 && novels.count == 1 && novelChapters.count == 1,
              "\(mangas.count) \(chapters.count) \(novels.count) \(novelChapters.count)")
        check("upgrade: stamps start empty",
              try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chapter WHERE stateChangedAt IS NOT NULL") == 0)
    }

    // v32 trigger: a real state change is stamped, a same-value write or a name change isn't.
    let before = Date().timeIntervalSince1970
    try db.write { db in
        try db.execute(sql: "UPDATE chapter SET isRead = 1 WHERE id = 'c2'")
        try db.execute(sql: "UPDATE chapter SET isRead = 1 WHERE id = 'c1'")      // already read
        try db.execute(sql: "UPDATE chapter SET name = 'Extra' WHERE id = 'c3'")
        try db.execute(sql: "UPDATE novel_chapter SET lastScrollPercent = 0.5 WHERE id = 'nc1'")
    }
    try db.read { db in
        let stamps = try Row.fetchAll(db, sql: "SELECT id, stateChangedAt FROM chapter WHERE mangaId = 'm1' ORDER BY id")
            .map { ($0["id"] as String, $0["stateChangedAt"] as Double?) }
        let c2 = stamps.first { $0.0 == "c2" }?.1
        check("v32: real change stamped ≈ now", c2.map { abs($0 - before) < 5 } == true, "\(stamps)")
        check("v32: same-value write not stamped", stamps.first { $0.0 == "c1" }?.1 == nil, "\(stamps)")
        check("v32: name change not stamped", stamps.first { $0.0 == "c3" }?.1 == nil, "\(stamps)")
        let n = try Double.fetchOne(db, sql: "SELECT stateChangedAt FROM novel_chapter WHERE id = 'nc1'")
        check("v32: novel change stamped", n.map { abs($0 - before) < 5 } == true, "\(String(describing: n))")
    }
} catch { check("v1 upgrade ran", false, "\(error)") }

if failures > 0 { print("\(failures) of \(checks) checks FAILED"); exit(1) }
print("OK \(checks) checks, \(DatabaseManager.makeMigrator().migrations.count) migrations")
