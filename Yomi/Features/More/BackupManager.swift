import Foundation
import GRDB
import Observation

// MARK: - BackupManager

@Observable final class BackupManager {
    static let shared = BackupManager()
    private init() {}

    var isExporting = false
    var isImporting = false
    var lastBackupDate: Date? = nil
    var errorMessage: String? = nil

    // MARK: - Export

    func exportBackup() async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let mangas   = try MangaQueries.fetchAll()
            let chapters = try await appDatabase.read { try Chapter.fetchAll($0) }

            let payload: [String: Any] = [
                "version":    1,
                "exportedAt": ISO8601DateFormatter().string(from: Date()),
                "mangas":     mangas.map   { encodeManga($0) },
                "chapters":   chapters.map { encodeChapter($0) }
            ]

            let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            let datePart = Date().formatted(.iso8601)
                .replacingOccurrences(of: ":", with: "-")
            let filename = "yomi-backup-\(datePart).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            lastBackupDate = Date()
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Import

    func importBackup(from url: URL) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let data = try Data(contentsOf: url)
            guard
                let payload      = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let mangaDicts   = payload["mangas"]   as? [[String: Any]],
                let chapterDicts = payload["chapters"] as? [[String: Any]]
            else {
                throw NSError(
                    domain: "Yomi", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid backup file"]
                )
            }

            for dict in mangaDicts {
                if let manga = decodeManga(dict) {
                    try MangaQueries.upsert(manga)
                }
            }
            for dict in chapterDicts {
                if let chapter = decodeChapter(dict) {
                    try ChapterQueries.upsert(chapter)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Encode Helpers

    private func encodeManga(_ m: Manga) -> [String: Any] {
        var d: [String: Any] = [
            "id":             m.id,
            "path":           m.path,
            "sourceId":       m.sourceId,
            "title":          m.title,
            "status":         m.status.rawValue,
            "genres":         m.genres,
            "inLibrary":      m.inLibrary,
            "isLocal":        m.isLocal,
            "readingSeconds": m.readingSeconds
        ]
        if let v = m.coverURL?.absoluteString { d["coverURL"]      = v }
        if let v = m.summary                  { d["summary"]       = v }
        if let v = m.author                   { d["author"]        = v }
        if let v = m.artist                   { d["artist"]        = v }
        if let v = m.lastReadAt               { d["lastReadAt"]    = ISO8601DateFormatter().string(from: v) }
        if let v = m.lastUpdatedAt            { d["lastUpdatedAt"] = ISO8601DateFormatter().string(from: v) }
        return d
    }

    private func encodeChapter(_ c: Chapter) -> [String: Any] {
        var d: [String: Any] = [
            "id":             c.id,
            "mangaId":        c.mangaId,
            "path":           c.path,
            "name":           c.name,
            "isRead":         c.isRead,
            "isDownloaded":   c.isDownloaded,
            "progress":       c.progress,
            "readingSeconds": c.readingSeconds
        ]
        if let v = c.chapterNumber { d["chapterNumber"] = v }
        if let v = c.readAt        { d["readAt"] = ISO8601DateFormatter().string(from: v) }
        return d
    }

    // MARK: - Decode Helpers

    private func decodeManga(_ d: [String: Any]) -> Manga? {
        guard
            let id       = d["id"]       as? String,
            let path     = d["path"]     as? String,
            let sourceId = d["sourceId"] as? String,
            let title    = d["title"]    as? String
        else { return nil }
        let fmt = ISO8601DateFormatter()
        return Manga(
            id:             id,
            path:           path,
            sourceId:       sourceId,
            title:          title,
            coverURL:       (d["coverURL"] as? String).flatMap { URL(string: $0) },
            summary:        d["summary"] as? String,
            author:         d["author"]  as? String,
            artist:         d["artist"]  as? String,
            status:         MangaStatus(rawValue: d["status"] as? String ?? "") ?? .unknown,
            genres:         d["genres"]  as? [String] ?? [],
            inLibrary:      d["inLibrary"]  as? Bool ?? false,
            isLocal:        d["isLocal"]    as? Bool ?? false,
            lastReadAt:     (d["lastReadAt"]    as? String).flatMap { fmt.date(from: $0) },
            lastUpdatedAt:  (d["lastUpdatedAt"] as? String).flatMap { fmt.date(from: $0) },
            readingSeconds: d["readingSeconds"] as? Int ?? 0
        )
    }

    private func decodeChapter(_ d: [String: Any]) -> Chapter? {
        guard
            let id      = d["id"]      as? String,
            let mangaId = d["mangaId"] as? String,
            let path    = d["path"]    as? String,
            let name    = d["name"]    as? String
        else { return nil }
        let fmt = ISO8601DateFormatter()
        return Chapter(
            id:             id,
            mangaId:        mangaId,
            path:           path,
            name:           name,
            chapterNumber:  d["chapterNumber"]  as? Double,
            isRead:         d["isRead"]         as? Bool ?? false,
            isDownloaded:   d["isDownloaded"]   as? Bool ?? false,
            readAt:         (d["readAt"] as? String).flatMap { fmt.date(from: $0) },
            progress:       d["progress"]       as? Double ?? 0,
            readingSeconds: d["readingSeconds"] as? Int ?? 0
        )
    }
}
