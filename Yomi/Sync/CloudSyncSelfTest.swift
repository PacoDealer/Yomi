#if DEBUG
import CloudKit
import Foundation
import GRDB

/// `-yomiSyncSelfTest`: applies hand-built CloudKit records to throwaway rows and logs one `SYNC-SELFTEST` line per
/// check (S191). No iCloud account is needed: records are built locally and go through the same apply code as a fetch.
/// Every row it writes has an id starting with `selftest-` and is deleted at the end.
nonisolated enum CloudSyncSelfTest {
    static func startIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-yomiSyncSelfTest") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))   // let launch work settle, or it shows up as main-actor gaps
            await run()
        }
    }

    private static let novelId = "selftest-novel"
    private static let zone = CKRecordZone.ID(zoneName: "LibraryZone", ownerName: CKCurrentUserDefaultName)
    nonisolated(unsafe) private static var failures = 0   // touched only from run(), on the main actor

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures += 1 }
        NSLog("SYNC-SELFTEST %@ %@ %@", ok ? "PASS" : "FAIL", name, ok ? "" : detail())
    }

    private static func chapter(_ index: Int, path: String) -> NovelChapter {
        NovelChapter(id: "\(novelId)-ch-\(index)", novelId: novelId, path: path, name: "Chapter \(index)",
                     chapterNumber: Double(index + 1), isRead: false, readAt: nil, releaseTime: nil, readingSeconds: 0)
    }

    /// A NovelChapterState record as another device sends it: ITS id for the chapter, plus the path when it has one.
    private static func stateRecord(chapterId: String, path: String?, read: Bool, scroll: Double,
                                    changedAt: Date? = nil, seconds: Int = 60) -> CKRecord {
        let key = "\(novelId)|\(chapterId)|\(path ?? "")"
        let record = CKRecord(recordType: "NovelChapterState",
                              recordID: CloudSyncManager.recordID(type: .novelChapterState, key: key, zoneID: zone))
        record["novelId"] = novelId
        record["chapterId"] = chapterId
        if let path { record["path"] = path }
        record["isRead"] = read
        record["readAt"] = read ? Date(timeIntervalSince1970: 1_790_000_000) : nil
        record["readingSeconds"] = Int64(seconds)
        record["lastScrollPercent"] = scroll
        record["isBookmarked"] = false
        if let changedAt { record["stateChangedAt"] = changedAt }
        return record
    }

    /// stateChangedAt + readingSeconds + id of this device's chapter at `path` (S192, #242).
    private static func state(_ path: String) -> (stamp: Double?, seconds: Int, id: String)? {
        let novelId = novelId
        return try? appDatabase.read { db in
            try Row.fetchOne(db, sql: "SELECT stateChangedAt, readingSeconds, id FROM novel_chapter WHERE novelId = ? AND path = ?",
                             arguments: [novelId, path]).map { ($0["stateChangedAt"], $0["readingSeconds"], $0["id"]) }
        } ?? nil
    }

    private static func mangaChapterRow(_ chapterId: String) -> (isRead: Bool, page: Int)? {
        try? appDatabase.read { db in
            try Row.fetchOne(db, sql: "SELECT isRead, lastPageRead FROM chapter WHERE id = ?", arguments: [chapterId])
                .map { ($0["isRead"] as Bool, $0["lastPageRead"] as Int) }
        } ?? nil
    }

    /// Whether this chapter's own record waits to be sent (no engine in the sim → `cloud_sync_map.pendingChange`).
    private static func queuedToSend(novelId: String, chapterId: String) -> Bool {
        let name = CloudSyncManager.recordID(type: .novelChapterState, key: "\(novelId)|\(chapterId)", zoneID: zone).recordName
        return ((try? appDatabase.read { db in
            try String.fetchOne(db, sql: "SELECT pendingChange FROM cloud_sync_map WHERE recordName = ?", arguments: [name])
        }) ?? nil) == "save"
    }

    private static func sql(_ statement: String, _ arguments: StatementArguments) {
        _ = try? appDatabase.write { db in try db.execute(sql: statement, arguments: arguments) }
    }

    private static func row(_ path: String) -> (isRead: Bool, scroll: Double?)? {
        let novelId = novelId
        return try? appDatabase.read { db in
            try Row.fetchOne(db, sql: "SELECT isRead, lastScrollPercent FROM novel_chapter WHERE novelId = ? AND path = ?",
                             arguments: [novelId, path]).map { ($0["isRead"] as Bool, $0["lastScrollPercent"] as Double?) }
        } ?? nil
    }

    @MainActor
    static func run() async {
        failures = 0
        cleanUp()
        let novel = Novel(id: novelId, path: "/selftest", sourceId: "selftest", title: "Sync Self-Test", coverURL: nil,
                          summary: nil, author: nil, status: "", genres: [], inLibrary: false, lastReadAt: nil,
                          lastUpdatedAt: nil, readingSeconds: 0, readingStatus: .none, notes: nil)
        insert(novel)
        // This device: /a is position 0, /b position 1.
        try? NovelQueries.insertAllIgnoringConflicts([chapter(0, path: "/a"), chapter(1, path: "/b")])

        // 1. The other device has a Q&A chapter before /b, so for it /b is position 0 — the id that is /a here.
        await CloudSyncManager.applyRemoteBatch(
            records: [stateRecord(chapterId: "\(novelId)-ch-0", path: "/b", read: true, scroll: 0.5)], deletions: [])
        check("path wins over a colliding id: /b read", row("/b")?.isRead == true, "\(String(describing: row("/b")))")
        check("path wins over a colliding id: /a untouched", row("/a")?.isRead == false && row("/a")?.scroll == nil,
              "\(String(describing: row("/a")))")

        // 2. A record from before S191 (no path) still applies by id.
        await CloudSyncManager.applyRemoteBatch(
            records: [stateRecord(chapterId: "\(novelId)-ch-0", path: nil, read: false, scroll: 0.25)], deletions: [])
        check("old record without path applies by id", row("/a")?.scroll == 0.25, "\(String(describing: row("/a")))")

        // 3. State for a chapter this device hasn't listed yet waits, and lands on that PATH once it arrives — even
        //    though the sender's id is /a's id here.
        await CloudSyncManager.applyRemoteBatch(
            records: [stateRecord(chapterId: "\(novelId)-ch-0", path: "/c", read: true, scroll: 0.9)], deletions: [])
        check("unknown path stashed, /a untouched", row("/a")?.isRead == false, "\(String(describing: row("/a")))")
        try? NovelQueries.insertAllIgnoringConflicts([chapter(0, path: "/a"), chapter(1, path: "/b"), chapter(2, path: "/c")])
        check("stash replayed onto /c", row("/c")?.isRead == true && row("/c")?.scroll == 0.9,
              "\(String(describing: row("/c")))")
        let leftover = count("SELECT COUNT(*) FROM pending_novel_chapter_state WHERE novelId = ?")
        check("stash emptied", leftover == 0, "\(leftover) left")

        // 4. A big batch is written off the main actor: the main actor keeps ticking while 3,000 records apply.
        let many = (0..<3_000).map { i in
            try? NovelQueries.insertAllIgnoringConflicts([chapter(10 + i, path: "/bulk/\(i)")])
            return stateRecord(chapterId: "x-\(i)", path: "/bulk/\(i)", read: true, scroll: 1)
        }
        let idleGap = await longestMainGap { try? await Task.sleep(for: .seconds(1)) }
        let t0 = Date()
        let longestGap = await longestMainGap { await CloudSyncManager.applyRemoteBatch(records: many, deletions: []) }
        let elapsed = Date().timeIntervalSince(t0)
        // The pre-S191 shape for comparison: the same records written on the main actor, one transaction each.
        let mainGap = await longestMainGap {
            await Task.yield()
            applyOneTransactionEach(many)
        }
        NSLog("SYNC-SELFTEST INFO longest main-actor gap: idle %.0f ms · batch off main %.0f ms · per-record on main %.0f ms",
              idleGap * 1000, longestGap * 1000, mainGap * 1000)
        let applied = count("SELECT COUNT(*) FROM novel_chapter WHERE novelId = ? AND path LIKE '/bulk/%' AND isRead = 1")
        check("3000 records applied", applied == 3_000, "\(applied)")
        NSLog("SYNC-SELFTEST INFO batch of 3000 took %.0f ms", elapsed * 1000)
        check("main actor not blocked (gap < 250 ms)", longestGap < 0.25, "\(Int(longestGap * 1000)) ms")

        await conflictChecks()
        cleanUp()
        NSLog("SYNC-SELFTEST DONE %@", failures == 0 ? "all passed" : "\(failures) FAILED")
    }

    /// S192 (#242): the newer change wins, by when it happened on its device.
    @MainActor
    private static func conflictChecks() async {
        let id = novelId
        try? NovelQueries.insertAllIgnoringConflicts([chapter(500, path: "/k1"), chapter(501, path: "/k2"), chapter(502, path: "/k3")])

        // 5. A local change is stamped by the trigger; writing the same values again is not a change.
        sql("UPDATE novel_chapter SET isRead = 1, readingSeconds = 500 WHERE novelId = ? AND path = '/k1'", [id])
        let stamped = state("/k1")?.stamp
        check("local change stamped ≈ now", stamped.map { abs($0 - Date().timeIntervalSince1970) < 5 } == true,
              "\(String(describing: stamped))")
        sql("UPDATE novel_chapter SET stateChangedAt = 1000 WHERE novelId = ? AND path = '/k1'", [id])
        sql("UPDATE novel_chapter SET isRead = 1 WHERE novelId = ? AND path = '/k1'", [id])
        check("same value again: no new stamp", state("/k1")?.stamp == 1000, "\(String(describing: state("/k1")))")
        sql("UPDATE novel_chapter SET stateChangedAt = ? WHERE novelId = ? AND path = '/k1'",
            [Date().timeIntervalSince1970, id])

        // 6. An OLDER iCloud copy (unread, an hour ago) never overwrites the offline read; this device's record is
        //    queued to be sent again, and the reading time isn't lowered.
        let localId = state("/k1")?.id ?? "?"
        await CloudSyncManager.applyRemoteBatch(records: [
            stateRecord(chapterId: "other-0", path: "/k1", read: false, scroll: 0.1,
                        changedAt: Date().addingTimeInterval(-3600), seconds: 900)
        ], deletions: [])
        check("older remote: local read kept", row("/k1")?.isRead == true, "\(String(describing: row("/k1")))")
        check("older remote: reading time takes the larger", state("/k1")?.seconds == 900, "\(String(describing: state("/k1")))")
        check("older remote: this device's record queued", queuedToSend(novelId: id, chapterId: localId))

        // 7. A NEWER change from the other device applies, and the chapter keeps ITS time (not "now").
        let later = Date().addingTimeInterval(60)
        await CloudSyncManager.applyRemoteBatch(records: [
            stateRecord(chapterId: "other-0", path: "/k1", read: false, scroll: 0.3, changedAt: later, seconds: 10)
        ], deletions: [])
        check("newer remote applies", row("/k1")?.isRead == false && row("/k1")?.scroll == 0.3, "\(String(describing: row("/k1")))")
        check("newer remote: stamp is the record's", state("/k1")?.stamp == later.timeIntervalSince1970,
              "\(String(describing: state("/k1")?.stamp)) vs \(later.timeIntervalSince1970)")
        check("newer remote: reading time never lowered", state("/k1")?.seconds == 900, "\(String(describing: state("/k1")))")

        // 8. A sender that didn't know when its state changed (stamp 0 — a re-sent library) never beats a known change…
        sql("UPDATE novel_chapter SET isRead = 1 WHERE novelId = ? AND path = '/k2'", [id])
        await CloudSyncManager.applyRemoteBatch(records: [
            stateRecord(chapterId: "other-1", path: "/k2", read: false, scroll: 0, changedAt: Date(timeIntervalSince1970: 0))
        ], deletions: [])
        check("unknown-time sender loses to a local change", row("/k2")?.isRead == true, "\(String(describing: row("/k2")))")
        // …but still fills a chapter this device never touched.
        await CloudSyncManager.applyRemoteBatch(records: [
            stateRecord(chapterId: "other-2", path: "/k3", read: true, scroll: 0.7, changedAt: Date(timeIntervalSince1970: 0))
        ], deletions: [])
        check("unknown-time sender fills an untouched chapter", row("/k3")?.isRead == true, "\(String(describing: row("/k3")))")

        // 9. Two states for a chapter not listed here yet: the stash keeps the NEWER one whatever the arrival order.
        await CloudSyncManager.applyRemoteBatch(records: [
            stateRecord(chapterId: "other-9", path: "/k9", read: true, scroll: 0.9, changedAt: Date().addingTimeInterval(-10))
        ], deletions: [])
        await CloudSyncManager.applyRemoteBatch(records: [
            stateRecord(chapterId: "other-9", path: "/k9", read: false, scroll: 0.2, changedAt: Date().addingTimeInterval(-500))
        ], deletions: [])
        try? NovelQueries.insertAllIgnoringConflicts([chapter(509, path: "/k9")])
        check("stash keeps the newer state", row("/k9")?.isRead == true && row("/k9")?.scroll == 0.9, "\(String(describing: row("/k9")))")
        check("replayed stash keeps its time", state("/k9")?.stamp.map { $0 < Date().timeIntervalSince1970 - 5 } == true,
              "\(String(describing: state("/k9")?.stamp))")

        // 10. Manga chapters (their own SQL): offline read beats an older copy, a newer one applies.
        let mangaId = "selftest-manga", chapterId = "selftest-manga-ch1"
        let manga = Manga(id: mangaId, path: "/m", sourceId: "selftest", title: "Sync Self-Test", coverURL: nil, summary: nil,
                          author: nil, artist: nil, status: .unknown, genres: [], inLibrary: false, isLocal: false,
                          lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0)
        let ch = Chapter(id: chapterId, mangaId: mangaId, path: "/m/1", name: "1", chapterNumber: 1, isRead: false,
                         isDownloaded: false, downloadedAt: nil, readAt: nil, progress: 0, readingSeconds: 0, lastPageRead: 0,
                         scanlator: nil)
        try? ChapterQueries.insertMangaAndChapters(manga: manga, chapters: [ch])
        sql("UPDATE chapter SET isRead = 1, lastPageRead = 12 WHERE id = ?", [chapterId])
        func mangaRecord(read: Bool, page: Int, at: Date) -> CKRecord {
            let r = CKRecord(recordType: "MangaChapterState", recordID: CloudSyncManager.recordID(
                type: .mangaChapterState, key: "\(mangaId)|\(chapterId)", zoneID: zone))
            r["mangaId"] = mangaId; r["chapterId"] = chapterId; r["isRead"] = read; r["progress"] = 0.0
            r["lastPageRead"] = Int64(page); r["readingSeconds"] = Int64(5); r["isBookmarked"] = false; r["stateChangedAt"] = at
            return r
        }
        func mangaRow() -> (isRead: Bool, page: Int)? { mangaChapterRow(chapterId) }
        await CloudSyncManager.applyRemoteBatch(records: [mangaRecord(read: false, page: 0, at: Date().addingTimeInterval(-600))],
                                                deletions: [])
        check("manga: older remote loses", mangaRow().map { $0.isRead && $0.page == 12 } == true, "\(String(describing: mangaRow()))")
        await CloudSyncManager.applyRemoteBatch(records: [mangaRecord(read: false, page: 3, at: Date().addingTimeInterval(60))],
                                                deletions: [])
        check("manga: newer remote applies", mangaRow().map { !$0.isRead && $0.page == 3 } == true, "\(String(describing: mangaRow()))")
        sql("DELETE FROM chapter WHERE mangaId = ?", [mangaId])
        sql("DELETE FROM manga WHERE id = ?", [mangaId])
        sql("DELETE FROM cloud_sync_map WHERE key LIKE ?", ["\(mangaId)%"])
    }

    /// Longest time the main actor went without running a 10 ms ticker while `work` ran.
    @MainActor
    private static func longestMainGap(_ work: @MainActor () async -> Void) async -> TimeInterval {
        var longest: TimeInterval = 0
        var last = Date()
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                longest = max(longest, Date().timeIntervalSince(last))
                last = Date()
            }
        }
        await Task.yield()
        await work()
        longest = max(longest, Date().timeIntervalSince(last))
        ticker.cancel()
        return longest
    }

    /// Synchronous, so called from the main actor it runs ON the main thread — like the pre-S191 apply.
    private static func applyOneTransactionEach(_ records: [CKRecord]) {
        for record in records { _ = try? appDatabase.write { db in try CloudSyncManager.applyRemote(record: record, db: db) } }
    }

    private static func insert(_ novel: Novel) {
        _ = try? appDatabase.write { db in try novel.insert(db) }
    }

    /// One COUNT(*) query whose only argument is the self-test novel id.
    private static func count(_ sql: String) -> Int {
        let id = novelId
        return ((try? appDatabase.read { db in try Int.fetchOne(db, sql: sql, arguments: [id]) }) ?? nil) ?? -1
    }

    private static func cleanUp() {
        let novelId = novelId
        _ = try? appDatabase.write { db in
            try db.execute(sql: "DELETE FROM novel_chapter WHERE novelId = ?", arguments: [novelId])
            try db.execute(sql: "DELETE FROM pending_novel_chapter_state WHERE novelId = ?", arguments: [novelId])
            try db.execute(sql: "DELETE FROM novel WHERE id = ?", arguments: [novelId])
            try db.execute(sql: "DELETE FROM cloud_sync_map WHERE key LIKE ?", arguments: ["\(novelId)%"])
        }
    }
}
#endif
