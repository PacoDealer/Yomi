import Foundation
import GRDB

// MARK: - MigrationService
//
// Tachimanga/Mihon parity: move a library manga from one source to another, preserving reading
// progress/categories/status. S148 (Martin's picks): the old entry leaves the Library but stays in the database
// (nothing is deleted — downloads included); every chapter up to the highest one read becomes read (Mihon's
// `MigrateMangaUseCase` rule — sources number a little differently, e.g. 107 vs 107.5); real read dates move with
// the title, so History and the "Last Read" sort don't jump to today; one transaction per title.

enum MigrationService {

    nonisolated struct Result: Sendable {
        /// Chapters marked read on the new source.
        let readChapters: Int
        let oldReadChapters: Int
        let newChapterCount: Int
    }

    /// What moves with a title (Mihon's `MigrationFlag`, minus trackers — Yomi links trackers by title — and minus
    /// "remove downloads": Martin, S148, no delete).
    nonisolated struct Options: Sendable, Equatable {
        var chapters = true
        var categories = true
        var customCover = true
        var notes = true
    }

    enum MigrationError: LocalizedError {
        case noChaptersFromNewSource

        var errorDescription: String? {
            switch self {
            case .noChaptersFromNewSource:
                return "The new source returned no chapters. Nothing was changed — your original "
                     + "entry is untouched. The source may be temporarily blocked or unreachable."
            }
        }
    }

    /// Runs entirely off MainActor — safe to call from Task.detached.
    ///
    /// `newChapters` is the new source's chapter list, fetched by the caller FIRST (a JS plugin via its bridge,
    /// a Keiyoushi source via `KeiyoushiBridge` — S147). A plugin swallows its own JS exceptions and returns []
    /// on failure, indistinguishable from "this title genuinely has no chapters" — either way there is nothing to
    /// migrate to, so bail before touching the library.
    nonisolated static func migrate(
        from oldManga: Manga,
        to newManga: Manga,
        newChapters: [Chapter],
        options: Options = Options()
    ) throws -> Result {
        guard !newChapters.isEmpty else { throw MigrationError.noChaptersFromNewSource }
        let coverPath = options.customCover ? copyCustomCover(from: oldManga, to: newManga.id) : nil

        var categoryKeys: [String] = []
        var chapterKeys: [String] = []
        let result: Result = try appDatabase.write { db in
            // The target may already be saved (in the Library, or browsed before) — merge into it, never replace.
            let existing = try Manga.fetchOne(db, key: newManga.id)
            var target = existing ?? newManga
            target.inLibrary = true
            if target.readingStatus == .none { target.readingStatus = oldManga.readingStatus }
            if options.notes, let notes = oldManga.notes, !notes.isEmpty {
                let current = target.notes ?? ""
                target.notes = current.isEmpty ? notes : current.contains(notes) ? current : "\(current)\n\n\(notes)"
            }
            if target.customCoverPath == nil, let coverPath { target.customCoverPath = coverPath }
            target.lastReadAt = [target.lastReadAt, oldManga.lastReadAt].compactMap { $0 }.max()
            // max, not sum: migrating the same pair twice must not double the time.
            target.readingSeconds = max(target.readingSeconds, oldManga.readingSeconds)
            try target.save(db)

            for chapter in newChapters { try chapter.insert(db, onConflict: .ignore) }
            try CloudSyncManager.applyPendingChapterStates(newChapters, db: db)

            if options.categories {
                let ids = try String.fetchAll(db, sql: "SELECT categoryId FROM manga_category WHERE mangaId = ?",
                                              arguments: [oldManga.id])
                for id in ids {
                    try db.execute(sql: "INSERT OR IGNORE INTO manga_category (mangaId, categoryId) VALUES (?, ?)",
                                   arguments: [newManga.id, id])
                    categoryKeys.append("\(newManga.id)|\(id)")
                }
            }

            let oldChapters = try Chapter.filter(Column("mangaId") == oldManga.id).fetchAll(db)
            let readOld = oldChapters.filter(\.isRead)
            var marked = 0
            if options.chapters {
                let fresh = try Chapter.filter(Column("mangaId") == newManga.id).fetchAll(db)
                let plan = readStatePlan(old: oldChapters, new: fresh)
                for update in plan {
                    try db.execute(
                        sql: """
                            UPDATE chapter SET isRead = ?, readAt = COALESCE(readAt, ?), progress = MAX(progress, ?),
                                readingSeconds = MAX(readingSeconds, ?), lastPageRead = MAX(lastPageRead, ?)
                            WHERE id = ?
                            """,
                        arguments: [update.isRead, update.readAt, update.progress, update.readingSeconds,
                                    update.lastPageRead, update.id])
                    chapterKeys.append("\(newManga.id)|\(update.id)")
                    if update.isRead { marked += 1 }
                }
            }

            // The old entry stays (chapters, read flags, downloads, category links) — it only leaves the Library,
            // and its last-read date moved to the new title, so History doesn't show the title twice.
            try db.execute(sql: "UPDATE manga SET inLibrary = 0, lastReadAt = NULL WHERE id = ?",
                           arguments: [oldManga.id])

            let newCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chapter WHERE mangaId = ?",
                                            arguments: [newManga.id]) ?? 0
            return Result(readChapters: marked, oldReadChapters: readOld.count, newChapterCount: newCount)
        }

        markCloudDirty(.manga, key: newManga.id)
        markCloudDirty(.manga, key: oldManga.id)
        markCloudDirtyBatch(.mangaCategoryLink, keys: categoryKeys)
        markCloudDirtyBatch(.mangaChapterState, keys: chapterKeys)
        return result
    }

    // MARK: - Read state

    nonisolated struct ChapterUpdate: Sendable {
        let id: String
        let isRead: Bool
        let readAt: Date?
        let progress: Double
        let readingSeconds: Int
        let lastPageRead: Int
    }

    /// Mihon's rule: every new chapter numbered at or below the highest read old chapter is read. A new chapter
    /// with the same number as an old one also takes its progress/time/page. The read date is the matching old
    /// chapter's, else the closest read old chapter below it — never "now".
    nonisolated static func readStatePlan(old: [Chapter], new: [Chapter]) -> [ChapterUpdate] {
        let maxRead = old.filter(\.isRead).compactMap(\.chapterNumber).max()
        var oldByNumber: [Double: Chapter] = [:]
        for ch in old {
            guard let n = ch.chapterNumber else { continue }
            // Prefer the read copy when a source lists a number twice (two scanlators).
            if let seen = oldByNumber[n], seen.isRead || !ch.isRead { continue }
            oldByNumber[n] = ch
        }
        let readDates = old.filter(\.isRead).compactMap { ch in ch.chapterNumber.map { ($0, ch.readAt) } }
            .sorted { $0.0 < $1.0 }

        var updates: [ChapterUpdate] = []
        for ch in new {
            guard let n = ch.chapterNumber else { continue }
            let match = oldByNumber[n]
            let read = (maxRead.map { n <= $0 } ?? false) || match?.isRead == true
            let hasProgress = (match?.progress ?? 0) > 0 || (match?.lastPageRead ?? 0) > 0
            guard read || hasProgress else { continue }
            let readAt = read ? (match?.readAt ?? readDates.last(where: { $0.0 <= n })?.1 ?? readDates.first?.1) : nil
            updates.append(ChapterUpdate(
                id: ch.id,
                isRead: read || ch.isRead,
                readAt: readAt,
                progress: match?.progress ?? (read ? 1 : 0),
                readingSeconds: match?.readingSeconds ?? 0,
                lastPageRead: match?.lastPageRead ?? 0
            ))
        }
        return updates
    }

    // MARK: - Cover

    /// Copies the old title's custom cover file for the new one (the old entry keeps its own).
    nonisolated private static func copyCustomCover(from old: Manga, to newId: String) -> String? {
        guard let source = old.resolvedCustomCoverPath, FileManager.default.fileExists(atPath: source) else {
            return nil
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let relative = "Covers/\(newId).jpg"
        let destination = docs.appendingPathComponent(relative)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard (try? FileManager.default.copyItem(atPath: source, toPath: destination.path)) != nil else {
                return nil
            }
        }
        return relative
    }
}
