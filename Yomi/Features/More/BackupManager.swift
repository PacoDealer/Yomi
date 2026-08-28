import Foundation
import GRDB
import Observation

// MARK: - ICloudSyncStatus

enum ICloudSyncStatus: Equatable {
    case idle
    case uploading
    case downloading
    case success
    case unavailable
    case error(String)
}

// MARK: - BackupManager

@Observable final class BackupManager {
    static let shared = BackupManager()
    private init() {}

    var isExporting = false
    var isImporting = false
    var lastBackupDate: Date? = nil
    var errorMessage: String? = nil
    var lastTachiyomiImportSummary: String? = nil

    // MARK: - iCloud state

    var iCloudStatus: ICloudSyncStatus = .idle
    var lastICloudUploadDate: Date? = {
        UserDefaults.standard.object(forKey: "lastICloudUploadDate") as? Date
    }()

    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private nonisolated static let containerID  = "iCloud.pacodealer.Yomi"
    private nonisolated static let backupFilePrefix = "YomiBackup-"
    private nonisolated static let backupFileSuffix = ".json"
    private nonisolated static let maxRetainedBackups = 8

    struct ICloudBackupEntry: Identifiable, Equatable, Sendable {
        let url: URL
        let date: Date
        let size: Int64
        var id: String { url.lastPathComponent }
    }

    // MARK: - Tachiyomi Import

    func importTachiyomiBackup(from url: URL) async {
        isImporting = true
        errorMessage = nil
        lastTachiyomiImportSummary = nil
        defer { isImporting = false }

        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let result = try TachiyomiBackupParser.parse(data)

            for manga in result.mangas {
                try MangaQueries.upsert(manga)
            }
            for chapter in result.chapters {
                try ChapterQueries.upsert(chapter)
            }

            lastTachiyomiImportSummary = "\(result.mangas.count) manga imported (\(result.mappedCount) matched, \(result.unmappedCount) unrecognized sources)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export

    func exportBackup() async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let data = try await buildBackupData()
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

    // MARK: - Tachiyomi Export

    /// Migrating *out* to Tachiyomi/Mihon or a fork — one-way interop, the reverse of
    /// importTachiyomiBackup. Metadata + read-state only, matching TachiyomiBackupExporter's scope.
    func exportTachiyomiBackup() async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            // One bulk query grouped client-side, off MainActor — was one synchronous DB round-trip
            // per library manga, on the main thread (Known Issue #140).
            let (mangas, chaptersByMangaId) = try await Task.detached(priority: .userInitiated) {
                let mangas = try MangaQueries.fetchLibrary()
                let grouped = try ChapterQueries.fetchAllGrouped(mangaIds: mangas.map { $0.id })
                return (mangas, grouped)
            }.value
            let data = TachiyomiBackupExporter.export(mangas: mangas, chaptersByMangaId: chaptersByMangaId)
            let datePart = Date().formatted(.iso8601)
                .replacingOccurrences(of: ":", with: "-")
            let filename = "yomi-export-\(datePart).tachibk"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func buildBackupData() async throws -> Data {
        let mangas         = try MangaQueries.fetchAll()
        let chapters       = try await appDatabase.read { try Chapter.fetchAll($0) }
        let novels         = try NovelQueries.fetchAll()
        let novelChapters  = try await appDatabase.read { try NovelChapter.fetchAll($0) }
        let novelCatPairs  = try await appDatabase.read { db -> [[String: String]] in
            try Row.fetchAll(db, sql: "SELECT novelId, categoryId FROM novel_category").map {
                ["novelId": $0["novelId"], "categoryId": $0["categoryId"]]
            }
        }
        let mangaCatPairs  = try await appDatabase.read { db -> [[String: String]] in
            try Row.fetchAll(db, sql: "SELECT mangaId, categoryId FROM manga_category").map {
                ["mangaId": $0["mangaId"], "categoryId": $0["categoryId"]]
            }
        }
        let categories = try CategoryQueries.fetchAll()

        // Encoding + serializing a whole library is pure CPU work and used to run on MainActor,
        // freezing "Export Backup"/"Upload to iCloud" for a large library (Known Issue #139).
        // `.prettyPrinted` is gone too — this format is only ever read back by `decodeBackup`.
        let exportedAt = ISO8601DateFormatter().string(from: Date())
        return try await Task.detached(priority: .userInitiated) {
            let payload: [String: Any] = [
                "version":         3,
                "exportedAt":      exportedAt,
                "categories":      categories.map     { Self.encodeCategory($0) },
                "mangas":          mangas.map         { Self.encodeManga($0) },
                "chapters":        chapters.map       { Self.encodeChapter($0) },
                "novels":          novels.map         { Self.encodeNovel($0) },
                "novelChapters":   novelChapters.map  { Self.encodeNovelChapter($0) },
                "novelCategories": novelCatPairs,
                "mangaCategories": mangaCatPairs
            ]
            return try JSONSerialization.data(withJSONObject: payload)
        }.value
    }

    // MARK: - iCloud upload / download

    func uploadToICloud() async {
        guard isICloudAvailable else { iCloudStatus = .unavailable; return }
        iCloudStatus = .uploading
        do {
            let data = try await buildBackupData()
            try await Task.detached {
                guard let dir = Self.iCloudBackupsDirectory() else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let datePart = Date().formatted(.iso8601)
                    .replacingOccurrences(of: ":", with: "-")
                let dest = dir.appendingPathComponent(
                    "\(Self.backupFilePrefix)\(datePart)\(Self.backupFileSuffix)"
                )
                try data.write(to: dest)
                try Self.pruneOldBackups(in: dir)
            }.value
            let now = Date()
            UserDefaults.standard.set(now, forKey: "lastICloudUploadDate")
            lastICloudUploadDate = now
            iCloudStatus = .success
        } catch {
            iCloudStatus = .error(error.localizedDescription)
        }
    }

    func downloadFromICloud(_ entry: ICloudBackupEntry) async {
        guard isICloudAvailable else { iCloudStatus = .unavailable; return }
        iCloudStatus = .downloading
        do {
            let data = try await Task.detached {
                let url = entry.url
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                // Ensure the file is downloaded locally before reading
                let vals = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if vals.ubiquitousItemDownloadingStatus != .current {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                    let deadline = Date().addingTimeInterval(30)
                    while Date() < deadline {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        let status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                        if status.ubiquitousItemDownloadingStatus == .current { break }
                    }
                }
                return try Data(contentsOf: url)
            }.value

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("YomiBackup_restore.json")
            try data.write(to: tmp)
            await importBackup(from: tmp)
            iCloudStatus = errorMessage == nil ? .success : .error(errorMessage ?? "Unknown error")
        } catch {
            iCloudStatus = .error(error.localizedDescription)
        }
    }

    func deleteICloudBackup(_ entry: ICloudBackupEntry) async {
        await Task.detached {
            try? FileManager.default.removeItem(at: entry.url)
        }.value
    }

    func listICloudBackups() async -> [ICloudBackupEntry] {
        guard isICloudAvailable else { return [] }
        return await Task.detached {
            guard let dir = Self.iCloudBackupsDirectory() else { return [] }
            return (try? Self.listBackupFiles(in: dir)) ?? []
        }.value
    }

    private nonisolated static func iCloudBackupsDirectory() -> URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: containerID
        ) else { return nil }
        let docs = container.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    private nonisolated static func listBackupFiles(in dir: URL) throws -> [ICloudBackupEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let entries: [ICloudBackupEntry] = urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix(backupFilePrefix) else { return nil }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = vals?.contentModificationDate ?? .distantPast
            let size = Int64(vals?.fileSize ?? 0)
            return ICloudBackupEntry(url: url, date: date, size: size)
        }
        return entries.sorted { $0.date > $1.date }
    }

    private nonisolated static func pruneOldBackups(in dir: URL) throws {
        let entries = try listBackupFiles(in: dir)
        guard entries.count > maxRetainedBackups else { return }
        for entry in entries.dropFirst(maxRetainedBackups) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    // MARK: - Import

    func importBackup(from url: URL) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            // File read + JSON parse + model decoding all run off MainActor; the writes below go
            // through GRDB's own writer queue in bulk transactions rather than one per row. This
            // used to be entirely main-thread with a separate transaction (plus its own
            // markCloudDirty write) per manga/chapter — 24,000+ sequential transactions for a
            // realistic library, which froze the UI for the whole restore.
            let decoded = try await Task.detached(priority: .userInitiated) {
                try Self.decodeBackup(at: url)
            }.value

            _ = try await appDatabase.write { db in
                for manga in decoded.mangas { try manga.save(db) }
                for chapter in decoded.chapters { try chapter.save(db) }

                // Categories (v3 backup) — must restore before assignment pairs
                for category in decoded.categories {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO category (id, name, sort) VALUES (?, ?, ?)",
                        arguments: [category.id, category.name, category.sort]
                    )
                }

                // Novels (v2 backup)
                for novel in decoded.novels { try novel.save(db) }
                // INSERT OR IGNORE, matching NovelQueries.insertAllIgnoringConflicts — never
                // overwrites existing read/progress state for a chapter already present locally.
                for chapter in decoded.novelChapters { try chapter.insert(db, onConflict: .ignore) }
                try CloudSyncManager.applyPendingNovelChapterStates(decoded.novelChapters, db: db)

                for pair in decoded.novelCatPairs {
                    guard let novelId = pair["novelId"], let catId = pair["categoryId"] else { continue }
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO novel_category (novelId, categoryId) VALUES (?, ?)",
                        arguments: [novelId, catId]
                    )
                }
                for pair in decoded.mangaCatPairs {
                    guard let mangaId = pair["mangaId"], let catId = pair["categoryId"] else { continue }
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO manga_category (mangaId, categoryId) VALUES (?, ?)",
                        arguments: [mangaId, catId]
                    )
                }
            }

            // One batched dirty-mark per record type instead of one write per restored row.
            markCloudDirtyBatch(.manga, keys: decoded.mangas.map(\.id))
            markCloudDirtyBatch(
                .mangaChapterState,
                keys: decoded.chapters.map { "\($0.mangaId)|\($0.id)" }
            )
            markCloudDirtyBatch(.novel, keys: decoded.novels.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Everything a Yomi JSON backup restores, already decoded into models.
    private nonisolated struct DecodedBackup: Sendable {
        nonisolated struct CategoryRow: Sendable {
            let id: String
            let name: String
            let sort: Int
        }
        var mangas: [Manga] = []
        var chapters: [Chapter] = []
        var categories: [CategoryRow] = []
        var novels: [Novel] = []
        var novelChapters: [NovelChapter] = []
        var novelCatPairs: [[String: String]] = []
        var mangaCatPairs: [[String: String]] = []
    }

    /// Reads and fully decodes a backup file. Pure I/O + parsing, no DB access and no observable
    /// state — safe to call from `Task.detached`.
    private nonisolated static func decodeBackup(at url: URL) throws -> DecodedBackup {
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

        var result = DecodedBackup()
        result.mangas   = mangaDicts.compactMap   { decodeManga($0) }
        result.chapters = chapterDicts.compactMap { decodeChapter($0) }
        result.categories = (payload["categories"] as? [[String: Any]] ?? []).compactMap { dict in
            guard
                let id   = dict["id"]   as? String,
                let name = dict["name"] as? String,
                let sort = dict["sort"] as? Int
            else { return nil }
            return DecodedBackup.CategoryRow(id: id, name: name, sort: sort)
        }
        result.novels = (payload["novels"] as? [[String: Any]] ?? [])
            .compactMap { decodeNovel($0) }
        result.novelChapters = (payload["novelChapters"] as? [[String: Any]] ?? [])
            .compactMap { decodeNovelChapter($0) }
        result.novelCatPairs = payload["novelCategories"] as? [[String: String]] ?? []
        result.mangaCatPairs = payload["mangaCategories"] as? [[String: String]] ?? []
        return result
    }

    // MARK: - Encode Helpers

    private nonisolated static func encodeCategory(_ c: Category) -> [String: Any] {
        ["id": c.id, "name": c.name, "sort": c.sort]
    }

    private nonisolated static func encodeManga(_ m: Manga) -> [String: Any] {
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
        if let v = m.lastReadAt               { d["lastReadAt"]       = ISO8601DateFormatter().string(from: v) }
        if let v = m.lastUpdatedAt            { d["lastUpdatedAt"]    = ISO8601DateFormatter().string(from: v) }
        if m.readingStatus != .none            { d["readingStatus"]    = m.readingStatus.rawValue }
        if let v = m.customCoverPath          { d["customCoverPath"]  = v }
        if let v = m.notes                    { d["notes"]            = v }
        return d
    }

    private nonisolated static func encodeChapter(_ c: Chapter) -> [String: Any] {
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
        if let v = c.readAt        { d["readAt"]        = ISO8601DateFormatter().string(from: v) }
        if let v = c.scanlator     { d["scanlator"]     = v }
        if c.lastPageRead > 0      { d["lastPageRead"]  = c.lastPageRead }
        return d
    }

    // MARK: - Decode Helpers

    private nonisolated static func decodeManga(_ d: [String: Any]) -> Manga? {
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
            readingSeconds: d["readingSeconds"] as? Int ?? 0,
            readingStatus:  ReadingStatus(rawValue: d["readingStatus"] as? String ?? "none") ?? .none,
            customCoverPath: d["customCoverPath"] as? String,
            notes: d["notes"] as? String
        )
    }

    private nonisolated static func decodeChapter(_ d: [String: Any]) -> Chapter? {
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
            // The backup never contains the actual downloaded page files (only on-disk, never
            // serialized) — trusting a backed-up isDownloaded=true here would leave the chapter
            // showing as "downloaded" in the UI (filterable/badged) with nothing on disk to back
            // it up. See finding #102.
            isDownloaded:   false,
            downloadedAt:   nil,
            readAt:         (d["readAt"] as? String).flatMap { fmt.date(from: $0) },
            progress:       d["progress"]       as? Double ?? 0,
            readingSeconds: d["readingSeconds"] as? Int ?? 0,
            lastPageRead:   d["lastPageRead"]   as? Int ?? 0,
            scanlator:      d["scanlator"]      as? String
        )
    }

    private nonisolated static func encodeNovel(_ n: Novel) -> [String: Any] {
        var d: [String: Any] = [
            "id":             n.id,
            "path":           n.path,
            "sourceId":       n.sourceId,
            "title":          n.title,
            "status":         n.status,
            "genres":         n.genres,
            "inLibrary":      n.inLibrary,
            "readingSeconds": n.readingSeconds,
            "readingStatus":  n.readingStatus.rawValue
        ]
        if let v = n.coverURL?.absoluteString { d["coverURL"]      = v }
        if let v = n.summary                  { d["summary"]       = v }
        if let v = n.author                   { d["author"]        = v }
        if let v = n.lastReadAt               { d["lastReadAt"]    = ISO8601DateFormatter().string(from: v) }
        if let v = n.lastUpdatedAt            { d["lastUpdatedAt"] = ISO8601DateFormatter().string(from: v) }
        if let v = n.notes                    { d["notes"]           = v }
        if let v = n.customCoverPath          { d["customCoverPath"] = v }
        return d
    }

    private nonisolated static func encodeNovelChapter(_ c: NovelChapter) -> [String: Any] {
        var d: [String: Any] = [
            "id":             c.id,
            "novelId":        c.novelId,
            "path":           c.path,
            "name":           c.name,
            "isRead":         c.isRead,
            "readingSeconds": c.readingSeconds
        ]
        if let v = c.chapterNumber    { d["chapterNumber"]    = v }
        if let v = c.readAt           { d["readAt"]           = ISO8601DateFormatter().string(from: v) }
        if let v = c.releaseTime      { d["releaseTime"]      = v }
        if let v = c.lastScrollPercent { d["lastScrollPercent"] = v }
        return d
    }

    private nonisolated static func decodeNovel(_ d: [String: Any]) -> Novel? {
        guard
            let id       = d["id"]       as? String,
            let path     = d["path"]     as? String,
            let sourceId = d["sourceId"] as? String,
            let title    = d["title"]    as? String
        else { return nil }
        let fmt = ISO8601DateFormatter()
        return Novel(
            id:             id,
            path:           path,
            sourceId:       sourceId,
            title:          title,
            coverURL:       (d["coverURL"] as? String).flatMap { URL(string: $0) },
            summary:        d["summary"] as? String,
            author:         d["author"]  as? String,
            status:         d["status"]  as? String ?? "",
            genres:         d["genres"]  as? [String] ?? [],
            inLibrary:      d["inLibrary"]      as? Bool ?? false,
            lastReadAt:     (d["lastReadAt"]    as? String).flatMap { fmt.date(from: $0) },
            lastUpdatedAt:  (d["lastUpdatedAt"] as? String).flatMap { fmt.date(from: $0) },
            readingSeconds: d["readingSeconds"] as? Int ?? 0,
            readingStatus:  ReadingStatus(rawValue: d["readingStatus"] as? String ?? "none") ?? .none,
            notes:          d["notes"] as? String,
            customCoverPath: d["customCoverPath"] as? String
        )
    }

    private nonisolated static func decodeNovelChapter(_ d: [String: Any]) -> NovelChapter? {
        guard
            let id      = d["id"]      as? String,
            let novelId = d["novelId"] as? String,
            let path    = d["path"]    as? String,
            let name    = d["name"]    as? String
        else { return nil }
        let fmt = ISO8601DateFormatter()
        return NovelChapter(
            id:             id,
            novelId:        novelId,
            path:           path,
            name:           name,
            chapterNumber:  d["chapterNumber"] as? Double,
            isRead:         d["isRead"]        as? Bool ?? false,
            readAt:         (d["readAt"] as? String).flatMap { fmt.date(from: $0) },
            releaseTime:    d["releaseTime"]   as? String,
            readingSeconds:    d["readingSeconds"]    as? Int ?? 0,
            lastScrollPercent: d["lastScrollPercent"] as? Double
        )
    }
}
