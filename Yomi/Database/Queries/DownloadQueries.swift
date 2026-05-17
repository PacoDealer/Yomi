import Foundation
import GRDB

/// Download operations for the chapter table.
enum DownloadQueries {

    /// Sets isDownloaded=true and downloadedAt=now for the given chapter.
    nonisolated static func markDownloaded(chapterId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isDownloaded = 1, downloadedAt = ? WHERE id = ?",
                arguments: [Date(), chapterId]
            )
        }
    }

    /// Sets isDownloaded=false and downloadedAt=nil for the given chapter.
    nonisolated static func markNotDownloaded(chapterId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isDownloaded = 0, downloadedAt = NULL WHERE id = ?",
                arguments: [chapterId]
            )
        }
    }

    /// Returns downloaded chapters for a manga, ordered by chapterNumber ASC NULLS LAST.
    nonisolated static func fetchDownloaded(mangaId: String) throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .filter(Column("isDownloaded") == true)
                .order(Column("chapterNumber").ascNullsLast)
                .fetchAll(db)
        }
    }

    /// Returns all downloaded chapters across all manga.
    nonisolated static func fetchAllDownloaded() throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("isDownloaded") == true)
                .fetchAll(db)
        }
    }

    /// Clears isDownloaded and downloadedAt for the given chapter.
    /// Does not delete the local file — file deletion is the caller's responsibility.
    nonisolated static func deleteDownloadRecord(chapterId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isDownloaded = 0, downloadedAt = NULL WHERE id = ?",
                arguments: [chapterId]
            )
        }
    }
}
