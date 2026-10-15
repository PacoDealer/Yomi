import Foundation
import GRDB

/// When each library title is next expected to get a chapter (v27, S166) — `FetchInterval` reads the release days,
/// these read and store them. Device-local and not synced: every device works it out from its own chapter rows.
nonisolated enum UpdateScheduleQueries {

    enum Kind: Sendable {
        case manga, novel
        var table: String { self == .manga ? "manga" : "novel" }
    }

    /// The source's upload date per chapter id (`chapter.uploadedAt`); only Keiyoushi lists carry one.
    nonisolated static func setUploadDates(_ dates: [String: Date]) throws {
        guard !dates.isEmpty else { return }
        _ = try appDatabase.write { db in
            let statement = try db.makeStatement(sql: "UPDATE chapter SET uploadedAt = ? WHERE id = ?")
            for (id, date) in dates {
                try statement.execute(arguments: [date, id])
            }
        }
    }

    /// Mihon's `awaitUpdateFetchInterval` after a successful check. Recomputed when the check found chapters, when
    /// it was never worked out, or when the stored next update is already behind the window — otherwise kept, so a
    /// title waiting on its expected day keeps that day. `lastUpdate` is the title's `lastUpdatedAt` from BEFORE this
    /// check touched it.
    nonisolated static func recordCheck(_ kind: Kind, id: String, foundRelease: Bool, lastUpdate: Date?,
                                        now: Date = Date(), calendar: Calendar = .current) throws {
        let window = FetchInterval.window(now: now, calendar: calendar)
        _ = try appDatabase.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT fetchInterval, nextUpdate FROM \(kind.table) WHERE id = ?",
                                             arguments: [id]) else { return }
            let fetchInterval: Int = row["fetchInterval"]
            let nextUpdate: Date? = row["nextUpdate"]
            let isBeforeWindow = nextUpdate.map { $0 < window.lowerBound } ?? true
            guard foundRelease || fetchInterval == 0 || isBeforeWindow else { return }

            let chapters: [FetchInterval.ChapterDates] = switch kind {
            case .manga:
                try Row.fetchAll(db, sql: "SELECT uploadedAt, fetchedAt FROM chapter WHERE mangaId = ?", arguments: [id])
                    .map { FetchInterval.ChapterDates(uploaded: $0["uploadedAt"], fetched: $0["fetchedAt"]) }
            case .novel:
                try Date?.fetchAll(db, sql: "SELECT fetchedAt FROM novel_chapter WHERE novelId = ?", arguments: [id])
                    .map { FetchInterval.ChapterDates(uploaded: nil, fetched: $0) }
            }
            let update = FetchInterval.update(fetchInterval: fetchInterval, nextUpdate: nextUpdate, lastUpdate: lastUpdate,
                                              chapters: chapters, now: now, calendar: calendar, window: window,
                                              foundRelease: foundRelease)
            try db.execute(sql: "UPDATE \(kind.table) SET fetchInterval = ?, nextUpdate = ? WHERE id = ?",
                           arguments: [update.fetchInterval, update.nextUpdate, id])
        }
    }

    /// Library titles whose next expected update is after the window — "not expected to update" this refresh.
    /// Titles never worked out (no `nextUpdate`) are always checked.
    nonisolated static func notExpected(_ kind: Kind, now: Date = Date(), calendar: Calendar = .current) throws -> Set<String> {
        let upper = FetchInterval.window(now: now, calendar: calendar).upperBound
        return try appDatabase.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT id FROM \(kind.table) WHERE inLibrary = 1 AND nextUpdate IS NOT NULL AND nextUpdate > ?
                """, arguments: [upper]))
        }
    }
}
