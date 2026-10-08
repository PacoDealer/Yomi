import Foundation

// MARK: - TachiyomiBackupParser
//
// Parses Tachiyomi / Mihon .tachibk files (gzip-compressed protobuf3). Tachimanga exports this format too.
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

    private typealias BackupChapter = (url: String, name: String, read: Bool, lastPage: Int,
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

    private static func parseManga(_ data: Data) -> (manga: Manga, chapters: [Chapter], categoryOrders: [Int64])? {
        var mihonSourceId: UInt64 = 0
        var url = ""
        var title = ""
        var artist: String?
        var author: String?
        var description: String?
        var genres: [String] = []
        var statusCode: Int32 = 0
        var thumbnailUrl: String?
        var favorite = false
        var memo: Data?
        var categoryOrders: [Int64] = []
        var backupChapters: [BackupChapter] = []
        var lastReadByChapterURL: [String: Date] = [:]

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
            case 112: memo = try? reader.readLengthDelimited()
            case 104:
                if wire == 2, let hData = try? reader.readLengthDelimited(), let h = parseHistory(hData) {
                    lastReadByChapterURL[h.url] = h.lastRead
                }
            default:  try? reader.skip(wireType: wire)
            }
        }

        guard !url.isEmpty, !title.isEmpty else { return nil }

        let sourceId = String(mihonSourceId)
        var manga = KeiyoushiMapping.manga(
            from: KeiyoushiManga(url: bridgeURL(url, memo: memo), title: title, artist: artist, author: author, description: description,
                                 genre: genres.isEmpty ? nil : genres.joined(separator: ", "),
                                 status: Int(statusCode), thumbnail_url: thumbnailUrl, thumbnail_proxy_url: nil),
            sourceId: sourceId)
        manga.inLibrary = favorite
        manga.lastReadAt = lastReadByChapterURL.values.max()

        var seen = Set<String>()
        let chapters: [Chapter] = backupChapters.compactMap { ch in
            guard !ch.url.isEmpty else { return nil }
            var chapter = KeiyoushiMapping.chapter(
                from: KeiyoushiChapter(url: bridgeURL(ch.url, memo: ch.memo), name: ch.name, date_upload: nil,
                                       chapter_number: ch.chapterNumber, scanlator: ch.scanlator),
                mangaId: manga.id, sourceId: sourceId, mangaTitle: title)
            guard seen.insert(chapter.id).inserted else { return nil }
            chapter.isRead = ch.read
            chapter.lastPageRead = ch.lastPage
            chapter.progress = ch.read ? 1.0 : 0
            // Only a real history date: a read chapter without one stays out of History rather than
            // claiming it was read in 1970 (pre-S147 behaviour).
            chapter.readAt = lastReadByChapterURL[ch.url] ?? (ch.read ? manga.lastReadAt : nil)
            return chapter
        }

        return (manga, chapters, categoryOrders)
    }

    // MARK: - Nested message decoders

    private static func parseChapter(_ data: Data) -> BackupChapter? {
        var url            = ""
        var name           = ""
        var scanlator: String?
        var read           = false
        var lastPage       = 0
        var chapterNumber: Double = -1
        var memo: Data?

        let reader = ProtoReader(data)
        while reader.hasNext {
            guard let (field, wire) = try? reader.readTag() else { break }
            switch field {
            case 1:  url           = (try? reader.readString()) ?? ""
            case 2:  name          = (try? reader.readString()) ?? ""
            case 3:  scanlator     = try? reader.readString()
            case 4:  read          = ((try? reader.readVarint64()) ?? 0) != 0
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
        return (url: url, name: name, read: read, lastPage: lastPage,
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

// MARK: - Error

enum BackupParseError: LocalizedError {
    case notGzip
    case zlibError(Int32)
    case truncated
    case empty

    var errorDescription: String? {
        switch self {
        case .notGzip:             return "File is not a gzip archive (.tachibk)"
        case .zlibError(let c):   return "Decompression error (zlib code \(c))"
        case .truncated:           return "Backup file is incomplete"
        case .empty:               return "This backup has no titles in it"
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
        let length = Int(try readVarint64())
        guard pos + length <= data.endIndex else { throw BackupParseError.truncated }
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
