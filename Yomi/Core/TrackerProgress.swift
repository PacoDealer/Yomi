import Foundation
import GRDB

/// Database half of `TrackerProgress` (rule in ProgressRules.swift): the highest numbered chapter already read.
extension TrackerProgress {
    nonisolated static func highestReadManga(mangaId: String) -> Double? {
        try? appDatabase.read { db in
            try Double.fetchOne(db, sql: "SELECT MAX(chapterNumber) FROM chapter WHERE mangaId = ? AND isRead = 1",
                                arguments: [mangaId])
        }
    }

    nonisolated static func highestReadNovel(novelId: String) -> Double? {
        try? appDatabase.read { db in
            try Double.fetchOne(db, sql: "SELECT MAX(chapterNumber) FROM novel_chapter WHERE novelId = ? AND isRead = 1",
                                arguments: [novelId])
        }
    }
}
