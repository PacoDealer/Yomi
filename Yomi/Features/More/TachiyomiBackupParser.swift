import Foundation
import GRDB
import UniformTypeIdentifiers

// MARK: - TachiyomiBackupParser
//
// Parses Tachiyomi / Mihon .tachibk files (gzip-compressed protobuf3). Tachimanga exports this format too
// (Premium only) — its own .tmb backup is read by the extension at the end of this file.
// Zero external dependencies:
//   • gzip decompression via libz (always linked on iOS) using inflateInit2_
//   • protobuf decoding via hand-written varint reader matching the known schema
//
// Field numbers checked against Mihon's live `data/backup/models/*.kt` (S147):
//   Backup          → backupManga(1), backupCategories(2), backupSources(101), backupExtensionStores(106)
//   BackupManga     → source(1), url(2), title(3), artist(4), author(5), description(6), genre(7),
//                     status(8), thumbnailUrl(9), chapters(16), categories(17, category ORDER values),
//                     favorite(100), history(104), memo(112)
//   BackupChapter   → url(1), name(2), scanlator(3), read(4), lastPageRead(6), chapterNumber(9, float), memo(13)
//   BackupCategory  → name(1), order(2)
//   BackupSource    → name(1), sourceId(2)
//   BackupHistory   → url(1, chapter url), lastRead(2, ms)
//   BackupExtensionStore → indexUrl(1), name(2)
//
// S147: titles come in as Keiyoushi titles (`keiyoushi_<Mihon source id>`) with the SAME manga/chapter ids and
// `keiyoushi://` chapter paths the bridge produces, because Keiyoushi runs the very same Mihon extensions. Once the
// source's extension is added the title opens and refreshes normally, and a refresh merges into the imported rows
// (INSERT OR IGNORE keeps the imported read state). A tachiyomix 1.6 "memo" (Asura keeps its slug there) is
// re-attached to the URL the way the bridge does it (`BridgeMemo`: url + "|mangayomi-memo|" + base64url JSON).
// Before S147 every source but MangaDex became a dead `tachiyomi_<id>` placeholder.

nonisolated enum TachiyomiBackupParser {

    // MARK: - Result

    struct ImportResult {
        var mangas: [Manga] = []
        var chapters: [Chapter] = []
        /// Backup categories in their order; a manga refers to one by its `order` value.
        var categories: [(name: String, order: Int64)] = []
        /// manga id → the `order` values of its categories.
        var mangaCategoryOrders: [String: [Int64]] = [:]
        /// Mihon source id → the source's name, as the backup recorded it.
        var sourceNames: [String: String] = [:]
        /// Extension repository index links the backup carried (Mihon 0.17+).
        var repoURLs: [String] = []
        /// manga id → groups hidden for it (Mihon BackupManga 108).
        var excludedScanlators: [String: Set<String>] = [:]

        /// The Mihon source ids the imported titles need.
        var sourceIds: Set<String> {
            Set(mangas.map { KeiyoushiMapping.mihonSourceId($0.sourceId) })
        }
    }

    // MARK: - Entry point

    static func parse(_ data: Data) throws -> ImportResult {
        let decompressed = try gunzip(data)
        return try decodeBackup(decompressed)
    }

    // MARK: - Gzip decompression (libz, windowBits=47 = auto gzip/zlib detection)

    /// Shared with the Keiyoushi repository index (also gzip'd protobuf).
    static func gunzip(_ data: Data) throws -> Data {
        guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else {
            throw BackupParseError.notGzip
        }
        var stream = z_stream()
        // 47 = MAX_WBITS(15) + 32 — tells zlib to auto-detect gzip or zlib wrapper
        let initResult = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { throw BackupParseError.zlibError(initResult) }
        defer { inflateEnd(&stream) }

        var output = Data(capacity: max(data.count * 4, 65_536))
        var status: Int32 = Z_OK
        let chunkSize = 65_536
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            stream.next_in  = UnsafeMutablePointer(mutating: src.baseAddress!.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(data.count)
            while status == Z_OK, stream.avail_in > 0 {
                chunk.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                    stream.next_out  = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), count: produced)
                    }
                }
            }
        }

        guard status == Z_STREAM_END || status == Z_OK else {
            throw BackupParseError.zlibError(status)
        }
        return output
    }

    // MARK: - Backup-level decoder

    private static func decodeBackup(_ data: Data) throws -> ImportResult {
        var result = ImportResult()
        var seenMangaIds = Set<String>()
        let reader = ProtoReader(data)

        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch (field, wire) {
            case (1, 2):
                if let mangaData = try? reader.readLengthDelimited(),
                   let parsed = parseManga(mangaData),
                   seenMangaIds.insert(parsed.manga.id).inserted {
                    result.mangas.append(parsed.manga)
                    result.chapters.append(contentsOf: parsed.chapters)
                    if !parsed.categoryOrders.isEmpty {
                        result.mangaCategoryOrders[parsed.manga.id] = parsed.categoryOrders
                    }
                    if !parsed.excludedScanlators.isEmpty {
                        result.excludedScanlators[parsed.manga.id] = parsed.excludedScanlators
                    }
                }
            case (2, 2):
                if let d = try? reader.readLengthDelimited(), let category = parseCategory(d) {
                    result.categories.append(category)
                }
            case (101, 2):
                if let d = try? reader.readLengthDelimited(), let source = parseSource(d) {
                    result.sourceNames[source.id] = source.name
                }
            case (106, 2):
                if let d = try? reader.readLengthDelimited(), let url = parseExtensionStore(d),
                   !result.repoURLs.contains(url) {
                    result.repoURLs.append(url)
                }
            default:
                try? reader.skip(wireType: wire)
            }
        }

        result.categories.sort { $0.order < $1.order }
        return result
    }

    // MARK: - BackupManga decoder

    private typealias BackupChapter = (url: String, name: String, read: Bool, bookmark: Bool, lastPage: Int,
                                       chapterNumber: Double, scanlator: String?, memo: Data?)

    /// The bridge's form of a URL with a memo (M-Extension-Server `BridgeMemo.encode`); an empty memo leaves it as is.
    static func bridgeURL(_ url: String, memo: Data?) -> String {
        guard let memo, let object = try? JSONSerialization.jsonObject(with: memo) as? [String: Any],
              !object.isEmpty else { return url }
        let payload = memo.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return url + "|mangayomi-memo|" + payload
    }

    private static func parseManga(_ data: Data)
        -> (manga: Manga, chapters: [Chapter], categoryOrders: [Int64], excludedScanlators: Set<String>)? {
        var mihonSourceId: UInt64 = 0
        var url = ""
        var title = ""
        var artist: String?
        var author: String?
        var description: String?
        var genres: [String] = []
        var statusCode: Int32 = 0
        var thumbnailUrl: String?
        // Mihon's default is TRUE, and kotlinx protobuf leaves out a field that equals its default — so an absent
        // field 100 means "in the library". Tachimanga's .tachibk never writes it (S147, Martin's 148-title backup).
        var favorite = true
        var memo: Data?
        var categoryOrders: [Int64] = []
        var backupChapters: [BackupChapter] = []
        var lastReadByChapterURL: [String: Date] = [:]
        var excludedScanlators = Set<String>()

        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1:   mihonSourceId     = (try? reader.readVarint64()) ?? 0
            case 2:   url               = (try? reader.readString())   ?? ""
            case 3:   title             = (try? reader.readString())   ?? ""
            case 4:   artist            = try? reader.readString()
            case 5:   author            = try? reader.readString()
            case 6:   description       = try? reader.readString()
            case 7:   if let g = try? reader.readString() { genres.append(g) }
            case 8:   statusCode        = Int32(truncatingIfNeeded: (try? reader.readVarint64()) ?? 0)
            case 9:   thumbnailUrl      = try? reader.readString()
            case 16:
                if wire == 2, let chData = try? reader.readLengthDelimited(),
                   let ch = parseChapter(chData) {
                    backupChapters.append(ch)
                }
            case 17:
                // kotlinx writes repeated Long unpacked (one varint per tag); accept the packed form too.
                if wire == 2, let packed = try? reader.readLengthDelimited() {
                    let inner = ProtoReader(packed)
                    while inner.hasNext, let v = try? inner.readVarint64() {
                        categoryOrders.append(Int64(bitPattern: v))
                    }
                } else if let v = try? reader.readVarint64() {
                    categoryOrders.append(Int64(bitPattern: v))
                }
            case 100: favorite = ((try? reader.readVarint64()) ?? 0) != 0
            case 108: if let g = try? reader.readString(), !g.isEmpty { excludedScanlators.insert(g) }
            case 112: memo = try? reader.readLengthDelimited()
            case 104:
                if wire == 2, let hData = try? reader.readLengthDelimited(), let h = parseHistory(hData) {
                    lastReadByChapterURL[h.url] = h.lastRead
                }
            default:  try? reader.skip(wireType: wire)
            }
        }

        guard !url.isEmpty, !title.isEmpty else { return nil }

        let built = build(sourceId: String(mihonSourceId),
                          manga: KeiyoushiManga(url: bridgeURL(url, memo: memo), title: title, artist: artist, author: author,
                                                description: description,
                                                genre: genres.isEmpty ? nil : genres.joined(separator: ", "),
                                                status: Int(statusCode), thumbnail_url: thumbnailUrl, thumbnail_proxy_url: nil),
                          favorite: favorite, lastReadAt: lastReadByChapterURL.values.max(),
                          chapters: backupChapters, readAtByChapterURL: lastReadByChapterURL)
        return (built.manga, built.chapters, categoryOrders, excludedScanlators)
    }

    /// One backup title as Yomi rows — shared by the .tachibk and the Tachimanga .tmb reader, so both produce the
    /// ids and `keiyoushi://` paths the bridge does.
    private static func build(sourceId: String, manga source: KeiyoushiManga, favorite: Bool, lastReadAt: Date?,
                              chapters backupChapters: [BackupChapter],
                              readAtByChapterURL: [String: Date]) -> (manga: Manga, chapters: [Chapter]) {
        var manga = KeiyoushiMapping.manga(from: source, sourceId: sourceId)
        manga.inLibrary = favorite
        manga.lastReadAt = lastReadAt

        var seen = Set<String>()
        let chapters: [Chapter] = backupChapters.compactMap { ch in
            guard !ch.url.isEmpty else { return nil }
            var chapter = KeiyoushiMapping.chapter(
                from: KeiyoushiChapter(url: bridgeURL(ch.url, memo: ch.memo), name: ch.name, date_upload: nil,
                                       chapter_number: ch.chapterNumber, scanlator: ch.scanlator),
                mangaId: manga.id, sourceId: sourceId, mangaTitle: source.title)
            guard seen.insert(chapter.id).inserted else { return nil }
            chapter.isRead = ch.read
            chapter.isBookmarked = ch.bookmark
            chapter.lastPageRead = ch.lastPage
            chapter.progress = ch.read ? 1.0 : 0
            // Only a real history date: a read chapter without one stays out of History rather than
            // claiming it was read in 1970 (pre-S147 behaviour).
            chapter.readAt = readAtByChapterURL[ch.url] ?? (ch.read ? manga.lastReadAt : nil)
            return chapter
        }

        return (manga, chapters)
    }

    // MARK: - Nested message decoders

    private static func parseChapter(_ data: Data) -> BackupChapter? {
        var url            = ""
        var name           = ""
        var scanlator: String?
        var read           = false
        var bookmark       = false
        var lastPage       = 0
        var chapterNumber: Double = 0   // Mihon's default (absent = 0); unknown is written explicitly as -1
        var memo: Data?

        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1:  url           = (try? reader.readString()) ?? ""
            case 2:  name          = (try? reader.readString()) ?? ""
            case 3:  scanlator     = try? reader.readString()
            case 4:  read          = ((try? reader.readVarint64()) ?? 0) != 0
            case 5:  bookmark      = ((try? reader.readVarint64()) ?? 0) != 0
            case 6:  lastPage      = Int((try? reader.readVarint64()) ?? 0)
            case 9 where wire == 5:
                if let bits = try? reader.readFixed32() {
                    chapterNumber = Double(Float(bitPattern: bits))
                }
            case 13: memo = try? reader.readLengthDelimited()
            default: try? reader.skip(wireType: wire)
            }
        }

        guard !name.isEmpty else { return nil }
        return (url: url, name: name, read: read, bookmark: bookmark, lastPage: lastPage,
                chapterNumber: chapterNumber, scanlator: scanlator, memo: memo)
    }

    private static func parseHistory(_ data: Data) -> (url: String, lastRead: Date)? {
        var url = ""
        var lastRead: UInt64 = 0
        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1: url = (try? reader.readString()) ?? ""
            case 2: lastRead = (try? reader.readVarint64()) ?? 0
            default: try? reader.skip(wireType: wire)
            }
        }
        guard !url.isEmpty, lastRead > 0 else { return nil }
        return (url, Date(timeIntervalSince1970: Double(lastRead) / 1000))
    }

    private static func parseCategory(_ data: Data) -> (name: String, order: Int64)? {
        var name = ""
        var order: Int64 = 0
        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1: name = (try? reader.readString()) ?? ""
            case 2: order = Int64(bitPattern: (try? reader.readVarint64()) ?? 0)
            default: try? reader.skip(wireType: wire)
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : (trimmed, order)
    }

    private static func parseSource(_ data: Data) -> (id: String, name: String)? {
        var name = ""
        var id: UInt64 = 0
        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1: name = (try? reader.readString()) ?? ""
            case 2: id = (try? reader.readVarint64()) ?? 0
            default: try? reader.skip(wireType: wire)
            }
        }
        return id == 0 || name.isEmpty ? nil : (String(id), name)
    }

    private static func parseExtensionStore(_ data: Data) -> String? {
        var indexUrl = ""
        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            if field == 1 { indexUrl = (try? reader.readString()) ?? "" } else { try? reader.skip(wireType: wire) }
        }
        return indexUrl.hasPrefix("http") ? indexUrl : nil
    }
}

// MARK: - Tachimanga .tmb
//
// S155: Tachimanga's own backup (its .tachibk export is a Premium feature, so most of its users only have this).
// A .tmb is a zip of `meta.json` + `contents.zip`; the inner zip holds `tachimanga.db` (the Suwayomi-style SQLite
// database), the extension jars and the preference plists. Only the database is read — the plists carry tracker
// logins and are never opened.
//
// Scope matches what Tachimanga itself writes to a .tachibk (checked on Martin's same-minute pair: 148 titles,
// 16,694 read chapters, 5 categories): library titles (`in_library`), the chapters that carry state (read, a
// saved page, a bookmark or last opened — the rest come back on the first refresh), categories, and history. The database also
// caches every title ever browsed (28,072 rows there); those stay behind. Dates are in SECONDS here.
// It adds two things the .tachibk lacks: a read date per chapter and the repository links.

nonisolated extension TachiyomiBackupParser {

    /// What the import picker offers: a Yomi backup (.json), .tachibk and Tachimanga's .tmb.
    static var backupFileTypes: [UTType] {
        [.json] + ["tachibk", "tmb"].map { UTType(filenameExtension: $0) ?? .data }
    }

    /// A zip ("PK") rather than the .tachibk's gzip.
    static func isTachimangaBackup(_ url: URL) -> Bool { leadingBytes(url) == Data([0x50, 0x4b]) }

    /// A .tachibk (gzip) or a .tmb — anything else the picker lets through is a Yomi backup.
    static func isOtherReaderBackup(_ url: URL) -> Bool {
        let head = leadingBytes(url)
        return head == Data([0x1f, 0x8b]) || head == Data([0x50, 0x4b])
    }

    private static func leadingBytes(_ url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) ?? Data()
    }

    static func parseTachimanga(at url: URL) throws -> ImportResult {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // The inner zip and the database go through disk: ZipArchive maps a file, and SQLite needs one.
        let innerURL = workDir.appendingPathComponent("contents.zip")
        let dbURL = workDir.appendingPathComponent("tachimanga.db")
        guard let inner = try ZipArchive(url: url).contents(of: "contents.zip") else { throw BackupParseError.notTachimanga }
        try inner.write(to: innerURL)
        guard let database = try ZipArchive(url: innerURL).contents(of: "tachimanga.db") else { throw BackupParseError.notTachimanga }
        try database.write(to: dbURL)

        return try DatabaseQueue(path: dbURL.path).read { db in
            var result = ImportResult()

            // Older Tachimanga databases lack some of these (the memo columns came with tachiyomix 1.6).
            func has(_ table: String, _ column: String) throws -> Bool {
                try db.tableExists(table) && db.columns(in: table).contains { $0.name == column }
            }
            let mangaMemo = try has("Manga", "memo") ? "memo" : "NULL"
            let chapterMemo = try has("Chapter", "memo") ? "memo" : "NULL"
            let liveCategory = try has("Category", "is_delete") ? "c.is_delete = 0" : "1"

            var lastReadByManga: [Int64: Date] = [:]
            if try db.tableExists("History") {
                let live = try has("History", "is_delete") ? "is_delete = 0 AND" : ""
                for row in try Row.fetchAll(db, sql: "SELECT manga_id, last_read_at FROM History WHERE \(live) last_read_at > 0") {
                    lastReadByManga[row["manga_id"]] = Date(timeIntervalSince1970: row["last_read_at"])
                }
            }

            // The chapter a title was last opened on travels too, read or not — as in Tachimanga's .tachibk.
            let lastOpened = try db.tableExists("History") ? "OR id IN (SELECT last_chapter_id FROM History)" : ""
            var chaptersByManga: [Int64: [BackupChapter]] = [:]
            var readAtByManga: [Int64: [String: Date]] = [:]
            let chapterRows = try Row.fetchCursor(db, sql: """
                SELECT manga, url, name, chapter_number, scanlator, read, bookmark, last_page_read, last_read_at, \(chapterMemo) AS memo
                FROM Chapter
                WHERE manga IN (SELECT id FROM Manga WHERE in_library = 1) AND (read = 1 OR last_page_read > 0 OR bookmark = 1 \(lastOpened))
                ORDER BY manga, source_order
                """)
            while let row = try chapterRows.next() {
                let mangaRow: Int64 = row["manga"]
                let chapterURL: String = row["url"]
                let name: String = row["name"]
                guard !name.isEmpty else { continue }
                chaptersByManga[mangaRow, default: []].append(
                    (url: chapterURL, name: name, read: row["read"], bookmark: row["bookmark"], lastPage: row["last_page_read"],
                     chapterNumber: row["chapter_number"], scanlator: row["scanlator"],
                     memo: (row["memo"] as String?).map { Data($0.utf8) }))
                // A title removed from Tachimanga's history keeps its read marks but brings no dates.
                let readAt: Int64 = row["last_read_at"]
                if readAt > 0, lastReadByManga[mangaRow] != nil {
                    readAtByManga[mangaRow, default: [:]][chapterURL] = Date(timeIntervalSince1970: TimeInterval(readAt))
                }
            }

            var mangaIdByRow: [Int64: String] = [:]
            var seenMangaIds = Set<String>()
            for row in try Row.fetchAll(db, sql: """
                SELECT id, url, title, artist, author, description, genre, status, thumbnail_url, source, \(mangaMemo) AS memo
                FROM Manga WHERE in_library = 1 AND source != 0
                """) {
                let rowId: Int64 = row["id"]
                let url: String = row["url"]
                let title: String = row["title"]
                guard !url.isEmpty, !title.isEmpty else { continue }
                let genre: String? = row["genre"]
                let built = build(
                    sourceId: String(row["source"] as Int64),
                    manga: KeiyoushiManga(url: bridgeURL(url, memo: (row["memo"] as String?).map { Data($0.utf8) }),
                                          title: title, artist: row["artist"], author: row["author"],
                                          description: row["description"], genre: genre?.isEmpty == true ? nil : genre,
                                          status: row["status"], thumbnail_url: row["thumbnail_url"], thumbnail_proxy_url: nil),
                    favorite: true, lastReadAt: lastReadByManga[rowId],
                    chapters: chaptersByManga[rowId] ?? [], readAtByChapterURL: readAtByManga[rowId] ?? [:])
                guard seenMangaIds.insert(built.manga.id).inserted else { continue }
                mangaIdByRow[rowId] = built.manga.id
                result.mangas.append(built.manga)
                result.chapters.append(contentsOf: built.chapters)
            }

            for row in try Row.fetchAll(db, sql: "SELECT name, \"order\" FROM Category c WHERE \(liveCategory) ORDER BY \"order\"") {
                let name = (row["name"] as String).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { result.categories.append((name, row["order"])) }
            }
            for row in try Row.fetchAll(db, sql: """
                SELECT cm.manga, c."order" FROM CategoryManga cm JOIN Category c ON c.id = cm.category WHERE \(liveCategory)
                """) {
                if let mangaId = mangaIdByRow[row["manga"]] {
                    result.mangaCategoryOrders[mangaId, default: []].append(row["order"])
                }
            }

            let needed = result.sourceIds
            for row in try Row.fetchAll(db, sql: "SELECT id, name FROM Source") {
                let id = String(row["id"] as Int64)
                if needed.contains(id) { result.sourceNames[id] = row["name"] }
            }

            if try db.tableExists("Repo") {
                let index = try has("Repo", "index_url") ? "index_url" : "NULL"
                for row in try Row.fetchAll(db, sql: "SELECT \(index) AS index_url, meta_url FROM Repo WHERE deleted = 0") {
                    let indexURL: String? = row["index_url"]
                    let link = indexURL?.isEmpty == false ? indexURL! : (row["meta_url"] as String)
                    if link.hasPrefix("http"), !result.repoURLs.contains(link) { result.repoURLs.append(link) }
                }
            }
            return result
        }
    }
}

// MARK: - Error

enum BackupParseError: LocalizedError {
    case notGzip
    case zlibError(Int32)
    case truncated
    case empty
    case notTachimanga

    var errorDescription: String? {
        switch self {
        case .notGzip:             return String(localized: "File is not a gzip archive (.tachibk)")
        case .zlibError(let c):   return String(localized: "Decompression error (zlib code \(c))")
        case .truncated:           return String(localized: "Backup file is incomplete")
        case .empty:               return String(localized: "This backup has no titles in it")
        case .notTachimanga:       return String(localized: "This isn't a Tachimanga backup (.tmb)")
        }
    }
}

// MARK: - ProtoReader (protobuf3 binary format)

/// Shared with `KeiyoushiRepository`'s index decoder; nonisolated so decoding can run in `Task.detached`.
nonisolated final class ProtoReader {
    private let data: Data
    private var pos: Int

    init(_ data: Data) {
        self.data = data
        self.pos  = data.startIndex
    }

    var hasNext: Bool { pos < data.endIndex }

    // Returns (fieldNumber, wireType)
    func readTag() throws -> (Int, Int) {
        let raw = try readVarint64()
        return (Int(raw >> 3), Int(raw & 0x7))
    }

    func readVarint64() throws -> UInt64 {
        var result: UInt64 = 0
        var shift = 0
        while pos < data.endIndex {
            let byte = UInt64(data[pos]); pos += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else { throw BackupParseError.truncated }
        }
        throw BackupParseError.truncated
    }

    func readString() throws -> String {
        let raw = try readLengthDelimited()
        return String(data: raw, encoding: .utf8) ?? ""
    }

    func readLengthDelimited() throws -> Data {
        // Check against the bytes left BEFORE converting: a crafted 2^63+ length would trap in Int() or in `pos + length`.
        let raw = try readVarint64()
        guard raw <= UInt64(data.endIndex - pos) else { throw BackupParseError.truncated }
        let length = Int(raw)
        let slice = data[pos ..< pos + length]
        pos += length
        return slice
    }

    func readFixed32() throws -> UInt32 {
        guard pos + 4 <= data.endIndex else { throw BackupParseError.truncated }
        let v = data[pos ..< pos + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        pos += 4
        return v
    }

    func skip(wireType: Int) throws {
        switch wireType {
        case 0: _ = try readVarint64()
        case 1:
            guard pos + 8 <= data.endIndex else { throw BackupParseError.truncated }
            pos += 8
        case 2: _ = try readLengthDelimited()
        case 5:
            guard pos + 4 <= data.endIndex else { throw BackupParseError.truncated }
            pos += 4
        default: throw BackupParseError.truncated
        }
    }
}
