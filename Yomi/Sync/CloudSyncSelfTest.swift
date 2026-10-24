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
    private static func stateRecord(chapterId: String, path: String?, read: Bool, scroll: Double) -> CKRecord {
        let key = "\(novelId)|\(chapterId)|\(path ?? "")"
        let record = CKRecord(recordType: "NovelChapterState",
                              recordID: CloudSyncManager.recordID(type: .novelChapterState, key: key, zoneID: zone))
        record["novelId"] = novelId
        record["chapterId"] = chapterId
        if let path { record["path"] = path }
        record["isRead"] = read
        record["readAt"] = read ? Date(timeIntervalSince1970: 1_790_000_000) : nil
        record["readingSeconds"] = Int64(60)
        record["lastScrollPercent"] = scroll
        record["isBookmarked"] = false
        return record
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

        cleanUp()
        NSLog("SYNC-SELFTEST DONE %@", failures == 0 ? "all passed" : "\(failures) FAILED")
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
